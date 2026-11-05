# frozen_string_literal: true

require "json"

require_relative "../lemma_keys"
require_relative "../normalize"
require_relative "../query/token_glosses"

module Nabu
  module Store
    # The token-gloss lane of the fulltext index (architecture §5): FTS over
    # the upstream LEXICAL glosses some sources store on each token
    # (Query::TokenGlosses — bhsa/achemenet English, aes/tlhdig German), so
    # "every word glossed king" is one lookup ACROSS lemmas instead of the
    # lemma-anchored filter (`search --lemma X --gloss Y`) alone.
    #
    # == Shape: one row per WORD, not per token
    #
    # token_glosses holds one FTS5 row per distinct (source, language,
    # lemma, gloss) among the source's live tokens — the lemma read through
    # LemmaKeys exactly as the lemma index reads it (bhsa: the consonantal
    # lex_utf8), a lemma-less token keyed by its surface form instead. A
    # hit is therefore a word ("מלך ‘king’, 2,523 tokens"), never a page of
    # identical verses; the attestations are one hop away through the
    # existing lemma-anchored filter. Each row points back at its FIRST
    # attestation (passage_id + the token's index in the passage's
    # tokens array, lowest passage id first) so a hit renders the word in
    # a real passage, and counts its tokens and passages.
    #
    # Unlike the passage-keyed contentless lanes, the table is CONTENTFUL:
    # the word row is an aggregate with no single catalog home to
    # re-extract from, and it is small (one row per distinct word).
    # `gloss` is the folded match column; `language` and `source` carry the
    # main table's sentinel tokens (Indexer.language_token / source_token)
    # so --lang/--source/--axis filter INSIDE the MATCH; everything else is
    # UNINDEXED display payload.
    #
    # Folding: the GENERIC fold (Normalize.search_form, no language — NFC,
    # downcase, mark strip): the gloss language is a metalanguage, not the
    # passage language. The query folds the same one way (fold-both-sides).
    # FTS tokens are whole words, matching TokenGlosses' whole-word filter
    # ("art" never finds "party").
    #
    # token_glosses_scope records, per source, the words and glossed tokens
    # THIS build indexed — the surfaces' honest coverage line.
    #
    # == Lifecycle (the translations-lane contract)
    #
    # The reference rebuild derives it whole (stage "glosses"); a sync
    # re-derives the synced source's slice when the lane exists (a word row
    # aggregates across passages, so the slice is the grain — no delta);
    # reconcile_stages! and `rake index:glosses` re-derive it standalone.
    # Derived, disposable, never migrated — the Indexer stance.
    module GlossIndex
      TABLE = :token_glosses
      SCOPE_TABLE = :token_glosses_scope
      STAGE = "glosses"

      # Raw FTS5 DDL — the Indexer's scoped raw-DDL exception (virtual
      # tables have no Sequel API).
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE token_glosses USING fts5(
          gloss,
          language,
          source,
          lemma UNINDEXED,
          display UNINDEXED,
          form UNINDEXED,
          passage_id UNINDEXED,
          token UNINDEXED,
          tokens UNINDEXED,
          passages UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # const: a write-batch size (statement bound), not a corpus claim
      BATCH_SIZE = 2_000

      module_function

      def built?(fulltext) = fulltext.table_exists?(TABLE) && fulltext.table_exists?(SCOPE_TABLE)

      # Drop and derive the whole lane over +slugs+ (default: the
      # TokenGlosses registry). +stamp+ advances the stage stamp (the
      # standalone/rake path; the reference rebuild stamps every stage
      # itself). Returns {words:, tokens:, sources:}.
      def rebuild!(catalog:, fulltext:, slugs: Query::TokenGlosses.sources, stamp: false)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(SCOPE_TABLE)
        fulltext.run(CREATE_TABLE)
        create_scope_table(fulltext)
        totals = { words: 0, tokens: 0, sources: 0 }
        fulltext.transaction do
          slugs.each do |slug|
            words, tokens = insert_source(catalog, fulltext, slug)
            next if words.nil?

            totals[:words] += words
            totals[:tokens] += tokens
            totals[:sources] += 1
          end
        end
        Indexer.stamp_stages!(fulltext, versions: { STAGE => Indexer::STAGE_VERSIONS.fetch(STAGE) }) if stamp
        totals
      end

      # Re-derive ONE source's slice (sync time). Hands-off (nil) when the
      # lane does not exist or the source is neither registered nor in the
      # last build's scope; a source the registry has dropped loses its
      # rows. Returns the source's indexed word count (0 after a drop).
      def refresh_source!(catalog:, fulltext:, slug:, registry_slugs: Query::TokenGlosses.sources)
        return nil unless built?(fulltext)

        registered = registry_slugs.include?(slug)
        in_scope = !fulltext[SCOPE_TABLE].where(slug: slug).empty?
        return nil unless registered || in_scope

        fulltext.transaction do
          source_rowids(fulltext, slug).each_slice(BATCH_SIZE) do |batch|
            fulltext[TABLE].where(rowid: batch).delete
          end
          fulltext[SCOPE_TABLE].where(slug: slug).delete
          registered ? insert_source(catalog, fulltext, slug)&.first.to_i : 0
        end
      end

      # The one fold both sides share (class note).
      def fold(text) = Normalize.search_form(text, language: nil)

      # Aggregate +slug+'s live glossed tokens into word rows, insert them
      # and the scope row. Returns [words, tokens], or nil when the source
      # is not in the catalog or carries no glossed token.
      def insert_source(catalog, fulltext, slug)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return nil if source_id.nil?

        words = aggregate(source_passages(catalog, source_id, slug), slug)
        return nil if words.empty?

        source = Indexer.source_token(slug)
        words.each_value.each_slice(BATCH_SIZE) do |batch|
          fulltext[TABLE].multi_insert(batch.map { |word| word.merge(source: source) })
        end
        tokens = words.each_value.sum { |word| word.fetch(:tokens) }
        fulltext[SCOPE_TABLE].insert(slug: slug, words: words.size, tokens: tokens)
        [words.size, tokens]
      end

      # {key => word row} in first-attestation order (passages stream in id
      # order, tokens in upstream order — a deterministic build).
      def aggregate(passages, slug)
        spec = LemmaKeys.spec_for(slug)
        words = {}
        passages.each do |passage|
          tokens = JSON.parse(passage.fetch(:annotations_json))["tokens"]
          next unless tokens.is_a?(Array)

          passage_id = passage.fetch(:passage_id)
          language = Indexer.language_token(passage[:language])
          tokens.each_with_index do |token, index|
            display = Query::TokenGlosses.gloss(token, source: slug)
            next if display.nil?

            lemma = LemmaKeys.lemmas(token, spec).first
            form = token["form"].is_a?(String) ? token["form"] : nil
            key = [language, lemma, lemma ? nil : form, display]
            word = words[key] ||= { gloss: fold(display), language: language, lemma: lemma.to_s,
                                    display: display, form: form.to_s, passage_id: passage_id,
                                    token: index, tokens: 0, passages: 0, last: nil }
            word[:tokens] += 1
            next if word[:last] == passage_id

            word[:passages] += 1
            word[:last] = passage_id
          end
        end
        words.each_value { |word| word.delete(:last) }
        words
      end

      def create_scope_table(fulltext)
        fulltext.create_table(SCOPE_TABLE) do
          String :slug, primary_key: true
          Integer :words, null: false
          Integer :tokens, null: false
        end
      end

      # The source's live passages that MIGHT carry a gloss: the two-level
      # visibility rule plus a LIKE prefilter on the registered gloss key,
      # in passage-id order. TokenGlosses.gloss re-checks exactly.
      def source_passages(catalog, source_id, slug)
        key = Query::TokenGlosses::FIELDS.fetch(slug).key
        annotations = Sequel[:passages][:annotations_json]
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel.like(annotations, "%\"#{key}\"%"))
          .order(Sequel[:passages][:id])
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:language], annotations)
      end

      # The rowids the lane holds for +slug+, found through the source
      # sentinel column (an FTS posting-list read).
      def source_rowids(fulltext, slug)
        fulltext[TABLE].where(Sequel.lit("token_glosses MATCH ?", %(source : "#{Indexer.source_token(slug)}")))
                       .select_map(:rowid)
      end
    end
  end
end
