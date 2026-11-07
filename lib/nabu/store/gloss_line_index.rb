# frozen_string_literal: true

require_relative "../normalize"
require_relative "../gloss_lines"

module Nabu
  module Store
    # The gloss-lines lane of the fulltext index (architecture §5): FTS
    # over each passage's upstream TOKEN glosses read in token order — the
    # interlinear gloss line (Nabu::GlossLines; the Query::TokenGlosses
    # sources: bhsa/achemenet English, aes/tlhdig German) — behind `search
    # --gloss-lines`. The CONTENT search of the gloss layer: passages
    # whose words are glossed king, whatever language the passage is in.
    #
    # == Grain: the passage, not the word
    #
    # The word-grain lane (Store::GlossIndex, `search --gloss WORD`)
    # already answers "which WORDS are glossed king" — one row per
    # distinct (source, language, lemma, gloss), a lexicon view. It cannot
    # answer a content query about a PASSAGE: a gloss row holds ONE word's
    # gloss, so "king" AND "eternity" can only meet inside a single gloss,
    # a phrase cannot run from one token's gloss into the next ("to the
    # king" is three BHSA tokens), and the hit is a word, never the verse
    # that says it. Glosses attach to tokens, tokens to passages, and the
    # passage is the unit a reader opens — so here one row per passage:
    # its glossed tokens' glosses in token order, one space apart, in one
    # `gloss` column. A hit names the passage (`nabu show <urn>`); the
    # read side re-extracts the matching tokens for the displayed page.
    # Token grain was rejected: one FTS row per token (~1.86M live) buys
    # nothing a passage row lacks — every display re-reads the passage
    # anyway — and loses co-occurrence and cross-token phrases.
    #
    # == Shape
    #
    # passages_gloss_lines is CONTENTLESS FTS5 (the annotations lane's
    # shape): rowid = the catalog passage id; nothing but the inverted
    # index is stored (the glosses live once, in annotations_json).
    # `language` and `source` hold the main table's sentinel tokens
    # (Indexer.language_token / source_token) — the PASSAGE's language, so
    # --lang names the text language ("king" in Aramaic), and
    # --source/--axis filter INSIDE the MATCH.
    #
    # Folding: each source's glosses fold by their declared GLOSS language
    # (GlossLines.fold — Field#language), never the passage's: Akkadian's
    # sign-join fold must not split an English "son-in-law". The query
    # folds once per declared gloss language, ORed (GlossLines.query_forms).
    #
    # passages_gloss_lines_scope records, per source, how many passages
    # THIS build indexed — the surface's honest coverage line.
    #
    # == Lifecycle (the annotations-lane contract)
    #
    # The reference rebuild derives it whole (stage "gloss_lines"); a sync
    # refreshes the synced source's slice when the lane exists (delta
    # grain when usable; never bootstraps it); reconcile_stages! and `rake
    # index:gloss_lines` re-derive it standalone over a live catalog, and
    # `rake index:gloss_lines[slug]` (build_source!) derives ONE declared
    # source's slice — creating the lane if absent — without touching the
    # rest. Derived, disposable, never migrated — the Indexer stance.
    module GlossLineIndex
      TABLE = :passages_gloss_lines
      SCOPE_TABLE = :passages_gloss_lines_scope
      STAGE = "gloss_lines"

      # Raw FTS5 DDL — the Indexer's scoped raw-DDL exception (virtual
      # tables have no Sequel API).
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_gloss_lines USING fts5(
          gloss,
          language,
          source,
          content = '',
          contentless_delete = 1,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # const: a write-batch size (statement bound), not a corpus claim
      BATCH_SIZE = 2_000

      module_function

      def built?(fulltext) = fulltext.table_exists?(TABLE) && fulltext.table_exists?(SCOPE_TABLE)

      # Drop and derive the whole lane over +slugs+ (default: the
      # declared gloss sources). +stamp+ advances the stage stamp (the
      # standalone/rake path; the reference rebuild stamps every stage
      # itself). Returns {passages:, sources:}.
      def rebuild!(catalog:, fulltext:, slugs: GlossLines.slugs, stamp: false)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(SCOPE_TABLE)
        create_tables(fulltext)
        total = 0
        sources = 0
        fulltext.transaction do
          slugs.each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            # A registry source absent from this catalog still gets its
            # scope row at 0 — the coverage line lists every DECLARED
            # source honestly (the annotations-lane convention).
            count = source_id ? insert_rows(fulltext, source_passages(catalog, source_id, slug), slug) : 0
            fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
            total += count
            sources += 1 if count.positive?
          end
        end
        Indexer.stamp_stages!(fulltext, versions: { STAGE => Indexer::STAGE_VERSIONS.fetch(STAGE) }) if stamp
        { passages: total, sources: sources }
      end

      # The targeted builder: derive ONE declared source's slice without a
      # rebuild, creating the (empty) lane first when the fulltext file
      # predates it. Leaves every other source's rows alone and never
      # advances the stage stamp (a partial lane is not the stage's whole
      # derivation). Returns the source's indexed passage count.
      def build_source!(catalog:, fulltext:, slug:)
        unless GlossLines.registered?(slug)
          raise ArgumentError, "#{slug}: not declared in Nabu::Query::TokenGlosses (declared: " \
                               "#{GlossLines.slugs.join(', ')})"
        end

        create_tables(fulltext) unless built?(fulltext)
        refresh_source!(catalog: catalog, fulltext: fulltext, slug: slug)
      end

      # Re-derive ONE source's slice (sync time). Hands-off (nil) when the
      # lane does not exist or the source is neither registered nor in the
      # last build's scope (delta grain when usable, else the whole slice;
      # a source dropped from the registry loses its rows and scope row).
      # Returns the source's indexed passage count (0 after a drop).
      def refresh_source!(catalog:, fulltext:, slug:, delta: nil, registry_slugs: GlossLines.slugs)
        return nil unless built?(fulltext)

        registered = registry_slugs.include?(slug)
        in_scope = !fulltext[SCOPE_TABLE].where(slug: slug).empty?
        return nil unless registered || in_scope

        source_id = catalog[:sources].where(slug: slug).get(:id)
        fulltext.transaction do
          if registered && in_scope && delta && !delta.overflowed? && source_id
            delete_rowids(fulltext, delta.changed_ids)
            insert_rows(fulltext, ids_scoped(source_passages(catalog, source_id, slug), delta.upserted_ids), slug)
          else
            delete_rowids(fulltext, source_rowids(fulltext, slug))
            insert_rows(fulltext, source_passages(catalog, source_id, slug), slug) if registered && source_id
          end
          fulltext[SCOPE_TABLE].where(slug: slug).delete
          next 0 unless registered

          # A declared source absent from the catalog keeps its scope
          # row at 0 — same coverage honesty as the full rebuild.
          count = source_id ? source_rowids(fulltext, slug).size : 0
          fulltext[SCOPE_TABLE].insert(slug: slug, passages: count)
          count
        end
      end

      # The FTS row for one catalog row, or nil when no token carries a
      # gloss. The line folds by the source's declared gloss language.
      def row(passage, slug)
        entries = GlossLines.entries(passage.fetch(:annotations_json), slug)
        return nil if entries.empty?

        { rowid: passage.fetch(:passage_id),
          gloss: GlossLines.fold(GlossLines.line(entries), slug),
          language: Indexer.language_token(passage[:language]),
          source: Indexer.source_token(slug) }
      end

      def create_tables(fulltext)
        fulltext.run(CREATE_TABLE)
        fulltext.create_table(SCOPE_TABLE) do
          String :slug, primary_key: true
          Integer :passages, null: false
        end
      end

      def insert_rows(fulltext, passages, slug)
        count = 0
        passages.each_slice(BATCH_SIZE) do |batch|
          rows = batch.filter_map { |passage| row(passage, slug) }
          fulltext[TABLE].multi_insert(rows)
          count += rows.size
        end
        count
      end

      # The source's live passages that MIGHT carry a gloss: the two-level
      # visibility rule plus a LIKE prefilter on the declared token key
      # (GlossLines.entries re-checks exactly).
      def source_passages(catalog, source_id, slug)
        annotations = Sequel[:passages][:annotations_json]
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel.like(annotations, "%\"#{GlossLines.key(slug)}\"%"))
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:language], annotations)
      end

      # Chunked id-scoping of a catalog dataset, streamed for insert_rows.
      def ids_scoped(dataset, ids)
        Enumerator.new do |y|
          ids.to_a.each_slice(BATCH_SIZE) do |batch|
            dataset.where(Sequel[:passages][:id] => batch).each { |row| y << row }
          end
        end
      end

      # The rowids the lane holds for +slug+, found through the source
      # sentinel column (an FTS posting-list read — no catalog scan).
      def source_rowids(fulltext, slug)
        fulltext[TABLE].where(Sequel.lit("passages_gloss_lines MATCH ?",
                                         %(source : "#{Indexer.source_token(slug)}")))
                       .select_map(:rowid)
      end

      # contentless_delete=1 makes rowid DELETE real (absent rowids no-op).
      def delete_rowids(fulltext, ids)
        ids.to_a.each_slice(BATCH_SIZE) { |batch| fulltext[TABLE].where(rowid: batch).delete }
      end
    end
  end
end
