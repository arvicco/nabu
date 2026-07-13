# frozen_string_literal: true

require "json"

require_relative "../normalize"

module Nabu
  module Store
    # Builds the FTS5 fulltext index AND the gold-treebank lemma index
    # (architecture §2/§5) from the catalog.
    #
    # == Why the index is not a numbered migration
    #
    # Numbered migrations in db/migrate/ own the CATALOG only — the small,
    # precious, forward-only source of truth. The fulltext index is
    # derived-of-derived (catalog ⇐ canonical): fully disposable, rebuilt at
    # will, and living in its OWN SQLite file (Config#fulltext_path). So its
    # schema is created here, imperatively, on every rebuild — never migrated.
    # Drop the file and re-run and you lose nothing.
    #
    # == The one place a raw SQL string is allowed
    #
    # CLAUDE.md forbids SQL strings outside Sequel datasets. That rule governs
    # QUERY paths (which stay on db[:passages_fts] datasets — see #rebuild!'s
    # multi_insert, and P4-2's MATCH). FTS5 virtual-table DDL has no Sequel
    # dataset API, so CREATE_TABLE below is a raw db.run heredoc. This is scoped
    # to DDL only — the lemma table below is a PLAIN table and is created
    # through the ordinary Sequel create_table DSL; the raw-DDL exception does
    # not widen with it.
    #
    # == No folding here (P6-4)
    #
    # text_normalized is indexed exactly AS STORED: it is already the true
    # per-language search form, minted once at the adapter boundary
    # (Passage.new → Normalize.search_form — marks stripped, downcased, plus
    # grc final-sigma / lat v-u,j-i rules; conventions.md §9). The tokenizer's
    # `remove_diacritics 2` still cannot fold precomposed polytonic Greek
    # (see Normalize.fold_diacritics), which is exactly why the folding lives
    # application-side at all — just upstream of here now, not in the index
    # build. Query::Search matches the query against the UNION of the
    # per-language folds (Normalize.query_forms), since queries carry no
    # language.
    #
    # == The lemma index (P7-5) — the first annotation-derived index
    #
    # passage_lemmas maps a FOLDED lemma to every live passage whose gold
    # treebank annotations attest it. It sets the pattern for future
    # annotation-derived indexes (Phase 8 enrichment output): derived from the
    # catalog's stored annotations_json — NEVER by re-parsing canonical — and
    # sharing the drop-and-rebuild lifecycle of the FTS table above (same
    # rebuild!, same "not a migration" stance, same fulltext.sqlite3 file).
    #
    # Shape decisions:
    #
    # - A PLAIN table with a real SQL index on lemma_folded, not FTS: a lemma
    #   is an atomic dictionary-form key looked up by exact equality (after
    #   folding), so a B-tree index answers it directly — FTS tokenization
    #   would add machinery for phrase/prefix semantics lemma search does not
    #   have.
    # - One row per (passage, folded lemma), NOT per token: a search hit is a
    #   passage, so hit-shaped rows need no query-time GROUP BY, and the
    #   distinct pristine surface forms attesting the lemma in that passage
    #   ride along in surface_forms (", "-joined) — what makes a hit READABLE
    #   ("λέγω attested as εἶπας"). Fixture arithmetic: dedup only trims
    #   ~10–14% off per-token rows (~7–21 lemma rows per passage across the
    #   three treebank families), so the row-count argument is secondary; the
    #   query shape is the reason.
    # - lemma_folded is Normalize.search_form(lemma, passage language) — a
    #   lemma is a dictionary form in language L, so the index side folds
    #   exactly like text_normalized (grc λόγος → λογοσ), and the query side
    #   matches the Normalize.query_forms union (Query::LemmaSearch), the same
    #   fold-both-sides contract as P6-4. lemma_raw keeps the first-seen
    #   upstream spelling for display.
    # - Extraction: both parser families store token lists under the
    #   annotations "tokens" key with per-token "lemma"/"form" (CoNLL-U LEMMA
    #   column via ConlluParser; PROIEL/TOROT token/@lemma via ProielParser).
    #   Tokens without a lemma (CoNLL-U `_`, MWT ranges, PROIEL empty tokens)
    #   and passages without lemma annotations contribute no rows — honest
    #   absence; the non-treebank ~1.45M passages simply are not here.
    # == The trigram index (P16-4) — fragment search, documentary scope
    #
    # passages_trigram is a second FTS5 table over the SAME folded search form
    # as passages_fts, tokenized into character trigrams so `search --fuzzy`
    # can match mid-word fragments (the papyrologist's ]μηνιν αει[). It is
    # deliberately NOT corpus-wide: at ~6 bytes/char the whole corpus costs
    # 3.6–4.1 GB, the documentary shelves ~250–270 MB (intertext design §4,
    # the owner-approved line). Which sources are in is an owner posture in
    # config/sources.yml (`fuzzy_index: true` — see SourceRegistry::Entry for
    # the where-does-the-flag-live argument); callers thread the resulting
    # slug list in as +fuzzy_slugs+. The companion passages_trigram_scope
    # table records the slugs THIS build actually indexed, so the query
    # surface reports real coverage, never a config that may have drifted
    # since the last reindex. Same lifecycle as everything else here:
    # drop-and-rebuild, never migrated, disposable.
    module Indexer
      TABLE = :passages_fts
      LEMMA_TABLE = :passage_lemmas
      TRIGRAM_TABLE = :passages_trigram
      TRIGRAM_SCOPE_TABLE = :passages_trigram_scope

      # Insert in slices so a 238k-passage corpus never materializes at once.
      BATCH_SIZE = 2_000

      # FTS5 DDL (see class note). text_normalized is the sole indexed column;
      # urn + passage_id ride along UNINDEXED so a hit joins back to the catalog
      # (where the pristine text and annotations stay) without duplicating them.
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized,
          urn UNINDEXED,
          passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # Trigram FTS5 DDL (class note; same raw-DDL exception as CREATE_TABLE —
      # virtual-table DDL has no Sequel API). Same column shape as
      # passages_fts so index_row feeds both; only the tokenizer differs.
      CREATE_TRIGRAM_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_trigram USING fts5(
          text_normalized,
          urn UNINDEXED,
          passage_id UNINDEXED,
          tokenize = 'trigram'
        )
      SQL

      module_function

      # Drop and rebuild the whole index (FTS + lemma table + alignment refs)
      # from +catalog+ into +fulltext+. Indexes every passage that is itself
      # live AND whose document is live (the two-level visibility rule from
      # P1-4). Bulk + transactional; one streaming pass feeds the FTS and
      # lemma tables; the alignment-ref pass (P11-3) walks only the registry's
      # witness documents. Returns the number of passages indexed.
      #
      # +alignments+ is the Nabu::AlignmentRegistry (config/alignments.yml) —
      # nil still creates the empty alignment table, so queries degrade to
      # "no rows", never "index missing".
      #
      # +fuzzy_slugs+ (P16-4) scopes the trigram fragment index — callers pass
      # SourceRegistry#fuzzy_slugs (config/sources.yml `fuzzy_index: true`).
      # Empty/nil still creates the (empty) trigram + scope tables, so
      # `search --fuzzy` degrades to "no rows + honest scope line", never
      # "index missing".
      #
      # Reads the catalog through raw datasets (not the Store models) so it is
      # independent of whichever db the global models are currently bound to.
      def rebuild!(catalog:, fulltext:, alignments: nil, fuzzy_slugs: nil)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(LEMMA_TABLE)
        fulltext.run(CREATE_TABLE)
        create_lemma_table(fulltext)

        count = 0
        fulltext.transaction do
          live_passages(catalog).each_slice(BATCH_SIZE) do |batch|
            fulltext[TABLE].multi_insert(batch.map { |row| index_row(row) })
            fulltext[LEMMA_TABLE].multi_insert(batch.flat_map { |row| lemma_rows(row) })
            count += batch.size
          end
        end
        rebuild_trigram!(catalog: catalog, fulltext: fulltext, fuzzy_slugs: Array(fuzzy_slugs))
        AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: alignments)
        # The cognate root closure (P15-3) rebuilds AFTER passage_lemmas: its
        # gold-language scope and suppression stats are snapshots of the lemma
        # table built moments ago in this same pass, so the two can never drift.
        ReflexRootsIndexer.rebuild!(catalog: catalog, fulltext: fulltext)
        count
      end

      # Drop and rebuild the trigram fragment index (class note) over the live
      # passages of the +fuzzy_slugs+ sources, and record that scope. A second
      # streaming pass rather than a branch in the main one: the scope is a
      # small subset of the corpus, and the fts/lemma pass stays untouched.
      # Returns the number of passages trigram-indexed.
      def rebuild_trigram!(catalog:, fulltext:, fuzzy_slugs:)
        fulltext.drop_table?(TRIGRAM_TABLE)
        fulltext.drop_table?(TRIGRAM_SCOPE_TABLE)
        fulltext.run(CREATE_TRIGRAM_TABLE)
        fulltext.create_table(TRIGRAM_SCOPE_TABLE) do
          String :slug, null: false
        end

        count = 0
        fulltext.transaction do
          fulltext[TRIGRAM_SCOPE_TABLE].multi_insert(fuzzy_slugs.map { |slug| { slug: slug } })
          trigram_passages(catalog, fuzzy_slugs).each_slice(BATCH_SIZE) do |batch|
            fulltext[TRIGRAM_TABLE].multi_insert(batch.map { |row| index_row(row) })
            count += batch.size
          end
        end
        count
      end

      # The lemma table (see class note). Plain Sequel DSL — no raw DDL.
      def create_lemma_table(fulltext)
        fulltext.create_table(LEMMA_TABLE) do
          String :lemma_folded, null: false
          String :lemma_raw, null: false
          Integer :passage_id, null: false
          String :urn, null: false
          String :language, null: false
          String :surface_forms, null: false
          index :lemma_folded
          # urn index (P15-1): the lemma-aware second signals — parallels'
          # rare-lemma co-occurrence and cognate-in-parallel (design §6) — look
          # a passage's lemmas up BY urn (the anchor probe). Without this the
          # anchor lookup scans 2.6M rows (~1.7 s measured); with it, one B-tree
          # hit. ~30–45 MB, rebuilt with the table (never migrated — the fulltext
          # db is derived-of-derived; class note).
          index :urn
        end
      end

      # Streaming dataset of catalog rows for every live passage under a live
      # document. Qualified selects avoid the passages/documents column-name
      # collisions (both carry urn, withdrawn, revision, id). The dataset is
      # Enumerable and streams; #each_slice buffers only one batch at a time.
      # language + annotations_json ride along for the lemma extraction only.
      def live_passages(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .select(
            Sequel[:passages][:text_normalized],
            Sequel[:passages][:urn],
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:language],
            Sequel[:passages][:annotations_json]
          )
      end

      # The trigram pass's slice of live_passages: same two-level visibility
      # rule, additionally scoped to the fuzzy-flagged sources (empty slugs =
      # empty dataset). The sources join hangs off documents.source_id;
      # text_normalized is indexed AS STORED, exactly like the fts pass — the
      # trigram table differs only in tokenization, never in folding.
      def trigram_passages(catalog, slugs)
        return [] if slugs.empty?

        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel[:sources][:slug] => slugs)
          .select(
            Sequel[:passages][:text_normalized],
            Sequel[:passages][:urn],
            Sequel[:passages][:id].as(:passage_id)
          )
      end

      # Turn a catalog row into an FTS index row — a pure column mapping, NO
      # text transform (class note: text_normalized is already the search
      # form). Kept separate so that invariant is testable and obvious.
      def index_row(row)
        {
          text_normalized: row.fetch(:text_normalized),
          urn: row.fetch(:urn),
          passage_id: row.fetch(:passage_id)
        }
      end

      # The passage's lemma-index rows: one per distinct FOLDED lemma its
      # stored annotations attest, with the distinct surface forms aggregated
      # (class note). The cheap substring probe skips the JSON parse for the
      # vast non-treebank majority (annotations_json defaults to "{}"); a
      # false positive just parses and finds no token lemmas. annotations_json
      # is our own canonical_json output, so a parse failure is real corruption
      # and honestly raises.
      def lemma_rows(row)
        json = row.fetch(:annotations_json)
        return [] if json.nil? || !json.include?('"lemma"')

        tokens = JSON.parse(json)["tokens"]
        return [] unless tokens.is_a?(Array)

        group_lemmas(tokens, language: row.fetch(:language)).map do |folded, entry|
          {
            lemma_folded: folded, lemma_raw: entry[:raw],
            passage_id: row.fetch(:passage_id), urn: row.fetch(:urn),
            language: row.fetch(:language), surface_forms: entry[:forms].join(", ")
          }
        end
      end

      # { folded lemma => { raw:, forms: [] } } over the passage's tokens.
      # forms stays empty for a lemma attested only by form-less tokens
      # (PROIEL empty tokens carry no lemma in practice, but stay tolerated).
      def group_lemmas(tokens, language:)
        tokens.each_with_object({}) do |token, grouped|
          lemma = token["lemma"] if token.is_a?(Hash)
          next if lemma.nil? || lemma.empty?

          folded = Normalize.search_form(lemma, language: language)
          entry = grouped[folded] ||= { raw: lemma, forms: [] }
          form = token["form"]
          entry[:forms] << form if form && !form.empty? && !entry[:forms].include?(form)
        end
      end
    end
  end
end
