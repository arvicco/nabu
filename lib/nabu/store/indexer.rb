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
    # - The tier column (P26-0): each row carries its source's lemma TIER —
    #   "gold" (verified annotation; the default, and everything that existed
    #   before the column) or "silver" (automatic lemmatization, declared per
    #   source via sources.yml `lemma_tier: silver` and threaded in as the
    #   +lemma_tiers+ map). The tier lives HERE, on the fulltext-side rows,
    #   not in the catalog: it is registry posture × source identity, both
    #   known at index-build time, and the table drops and rebuilds anyway —
    #   no catalog migration, no schema change for existing adapters.
    #   attested_count consumers (ReflexViews) keep gold-only semantics and
    #   surface silver as a separate labeled count; LemmaSearch serves both
    #   tiers with per-hit labels and a gold-only filter. The third tier,
    #   "equivalence" (P34-3), mints from a DIFFERENT token key — see the
    #   EQUIVALENCE_TIER constants below.
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

      # The default lemma tier (P26-0): a source absent from the lemma_tiers
      # map is gold — verified annotation, the only kind that existed before
      # the tier column.
      GOLD_TIER = "gold"

      # The equivalence tier (P34-3): a source declared `lemma_tier:
      # equivalence` (CEIPoM) carries NO citation-form "lemma" key — its
      # lemma layer is an opaque ID space — but its tokens carry
      # scholar-curated Classical-Latin equivalents under EQUIVALENCE_KEY.
      # Those values mint the source's lemma-index rows as LATIN keys
      # (folded AND labeled EQUIVALENCE_LANGUAGE) on the non-Latin passages,
      # so `search --lemma quinque` reaches Oscan and Umbrian. The tier is
      # DISTINCT from silver by owner ruling: silver means
      # upstream-automatic; this is curated cross-language equivalence — a
      # different honesty — and it is never attestation in the key's
      # language, so every gold-scoped consumer excludes it and every
      # render labels it. Should a second equivalence source ever arrive
      # with a different key/target language, generalize these constants
      # into per-source registry config; one source does not justify the
      # machinery today.
      EQUIVALENCE_TIER = "equivalence"
      EQUIVALENCE_KEY = "latin_equivalent"
      EQUIVALENCE_LANGUAGE = "lat"

      # Insert in slices so a 238k-passage corpus never materializes at once.
      BATCH_SIZE = 2_000

      # FTS5 DDL (see class note). text_normalized carries the folded search
      # form; urn + passage_id ride along UNINDEXED so a hit joins back to the
      # catalog (where the pristine text and annotations stay) without
      # duplicating them.
      #
      # == The language column (P42-3) — index-side --lang
      #
      # MEASURED problem (the P40-r2 starvation genus, P41 scale review): a
      # catalog-side --lang WHERE thins the bounded inner window AFTER the
      # MATCH, so a term whose hits concentrate in other languages starves
      # the page — empty results at any realistic --limit while matches
      # exist. The honest fix puts the filter INSIDE the MATCH: `language`
      # is an INDEXED fts5 column holding one sentinel token per row
      # (language_token: "0lang" + the code downcased with non-alphanumerics
      # stripped — "grc" → "0langgrc", "san-Deva" → "0langsandeva"), and
      # Query::Search composes `... AND language : ("0langgrc")`, so the
      # window can never fill with wrong-language rows.
      #
      # Why a SENTINEL token, not the bare code:
      # - Bare codes are real words ("is" is both the Icelandic code and the
      #   English verb). Indexed bare, every no---lang query for such a word
      #   would match that whole language's rows through the language
      #   column, and the P42-2 fts5vocab 'row' df probe (which aggregates
      #   across ALL columns) would inflate that term's document frequency,
      #   skewing the ubiquity guard. The leading-digit prefix makes the
      #   language vocabulary DISJOINT from every natural-language token, so
      #   plain MATCHes and the guard's df lookups cannot see it — neither
      #   needed any change.
      # - Multi-part stored codes ("san-Deva") would tokenize into several
      #   tokens, breaking the equality semantics --lang has always had
      #   (catalog `language IN (...)`): `language:san` would prefix-bleed
      #   into san-Deva rows. The mint collapses each code to ONE token, so
      #   the filter stays equality (case-insensitive — the one deliberate
      #   widening over the case-sensitive catalog WHERE, documented on
      #   Query::Search).
      #
      # The column appears when this table is next built FROM SCRATCH (the
      # owner's scheduled full rebuild). Incremental refreshes write the
      # shape the live table actually has (insert_passage_batches feature-
      # detects), so a pre-P42-3 index keeps taking syncs unchanged until
      # then, and Query::Search serves the old catalog-side path against it.
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized,
          language,
          urn UNINDEXED,
          passage_id UNINDEXED,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # The language sentinel-token prefix (CREATE_TABLE note): a leading
      # digit guarantees no natural-language token ever collides.
      LANGUAGE_TOKEN_PREFIX = "0lang"

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
      # +lemma_tiers+ (P26-0) is SourceRegistry#lemma_tiers — { slug => tier }
      # for the non-gold sources only (absent slug = gold; nil = every source
      # gold, the pre-tier world exactly).
      #
      # Reads the catalog through raw datasets (not the Store models) so it is
      # independent of whichever db the global models are currently bound to.
      # +profile+ (P36-0) is a Nabu::RebuildProfile or nil — when present, the
      # four corpus-wide sub-stages (fts+lemma streaming pass, trigram,
      # alignment refs, reflex roots) each fold their wall time into it. The FTS
      # tokenize and lemma build are ONE stage (fts_lemma): they share this
      # single streaming row scan, so separating them would need a per-passage
      # timer. nil keeps the sync-time incremental path unmeasured.
      def rebuild!(catalog:, fulltext:, alignments: nil, fuzzy_slugs: nil, lemma_tiers: nil, profile: nil)
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(LEMMA_TABLE)
        fulltext.run(CREATE_TABLE)
        create_lemma_table(fulltext)
        tiers = source_tiers(catalog, lemma_tiers || {})

        count = 0
        timed(profile, :fts_lemma) do
          fulltext.transaction do
            count, = insert_passage_batches(fulltext, live_passages(catalog), tiers)
          end
          # P36-2: the lemma table was created BARE (create_lemma_table); build
          # its three B-tree indexes now, in one sorted pass over the populated
          # table, rather than maintaining them incrementally across millions of
          # per-row inserts. Still inside the fts_lemma stage and BEFORE the
          # reflex pass, which reads passage_lemmas by these very indexes.
          create_lemma_indexes(fulltext)
        end
        timed(profile, :trigram) do
          rebuild_trigram!(catalog: catalog, fulltext: fulltext, fuzzy_slugs: Array(fuzzy_slugs))
        end
        timed(profile, :alignment) do
          AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: alignments)
        end
        # The cognate root closure (P15-3) rebuilds AFTER passage_lemmas: its
        # gold-language scope and suppression stats are snapshots of the lemma
        # table built moments ago in this same pass, so the two can never drift.
        timed(profile, :reflex) do
          ReflexRootsIndexer.rebuild!(catalog: catalog, fulltext: fulltext)
        end
        count
      end

      # Fold a corpus-wide index sub-stage's wall time into +profile+, or just
      # run the block when there is none (P36-0).
      def timed(profile, stage, &)
        return yield if profile.nil?

        profile.measure(scope: Nabu::RebuildProfile::CORPUS, stage: stage, &)
      end

      # Incrementally refresh ONE source's slice of the index (P26-5) — the
      # sync-time replacement for the full drop-and-rebuild above, which stays
      # `nabu rebuild`'s from-scratch guarantee. The contract is ROW IDENTITY:
      # after refresh_source!, the fulltext state equals what rebuild! would
      # produce from the same catalog (pinned by test).
      #
      # Mechanism, table by table:
      # - passages_fts / passages_trigram are REGULAR (contentful) FTS5
      #   tables, so per-row DELETE is real deletion (contentless/external-
      #   content tables would need the special 'delete' insert — not our
      #   shape). passage_id is UNINDEXED, so rather than one full-table scan
      #   per IN-batch, ONE streaming scan collects the doomed rowids (every
      #   row whose passage_id belongs to the source — withdrawn rows
      #   included, since the loader never hard-deletes a passage row, every
      #   indexed id resolves against the catalog forever) and the deletes go
      #   by rowid. ~4.3M-row scan, seconds — against the minutes of a full
      #   rebuild.
      # - passage_lemmas deletes by urn IN-batches (B-tree indexed).
      # - trigram: only touched when the source is in scope — flagged now
      #   (fuzzy_slugs) or indexed by the last build (the scope table); a
      #   de-flagged source loses its rows AND its scope row, so coverage
      #   reads honestly. Live scope: papyri/oracc/edh, 1.71M rows total.
      # - alignment_refs: rebuilt via AlignmentIndexer ONLY when the source
      #   holds a registry witness document — the index is registry-scoped
      #   (157k rows live) so the full rebuild is cheap, and a non-witness
      #   sync skips it entirely.
      # - reflex_roots/stats: rebuilt when the source's lemma rows changed
      #   (84k rows live, ~seconds) or when +reflexes_changed+ says the
      #   crosswalk itself did (dictionary syncs); a lemma-less source skips.
      #
      # Fallback: a fulltext db missing any table (first-ever sync) or whose
      # lemma table predates the tier column falls back to the full rebuild!.
      # Returns the SOURCE's live passage count — never the corpus total.
      def refresh_source!(catalog:, fulltext:, slug:, alignments: nil, fuzzy_slugs: nil,
                          lemma_tiers: nil, reflexes_changed: false)
        unless incremental_ready?(fulltext)
          rebuild!(catalog: catalog, fulltext: fulltext, alignments: alignments,
                   fuzzy_slugs: fuzzy_slugs, lemma_tiers: lemma_tiers)
          return source_live_count(catalog, slug)
        end

        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        ids, urns = source_passage_keys(catalog, source_id)
        count = 0
        lemmas_changed = false
        fulltext.transaction do
          deleted = delete_source_lemma_rows(fulltext, urns)
          delete_fts_rows(fulltext, TABLE, ids)
          count, inserted = insert_passage_batches(
            fulltext, live_passages(catalog).where(Sequel[:documents][:source_id] => source_id),
            source_tiers(catalog, lemma_tiers || {})
          )
          lemmas_changed = deleted.positive? || inserted.positive?
          refresh_trigram_slice(catalog, fulltext, slug, Array(fuzzy_slugs), ids)
        end
        refresh_alignment(catalog, fulltext, alignments, source_id)
        ReflexRootsIndexer.rebuild!(catalog: catalog, fulltext: fulltext) if lemmas_changed || reflexes_changed
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

      # -- refresh_source! internals (P26-5) ---------------------------------

      # Every table refresh_source! maintains must already exist in its
      # CURRENT shape (the tier column is the probe precedent: a pre-tier
      # lemma table cannot take tiered inserts). Anything missing → the
      # caller falls back to the full rebuild, which creates them all.
      def incremental_ready?(fulltext)
        [TABLE, LEMMA_TABLE, TRIGRAM_TABLE, TRIGRAM_SCOPE_TABLE,
         AlignmentIndexer::TABLE, ReflexRootsIndexer::TABLE, ReflexRootsIndexer::STATS_TABLE]
          .all? { |table| fulltext.table_exists?(table) } &&
          fulltext[LEMMA_TABLE].columns.include?(:tier)
      end

      # The language column's one-token search value for +code+ (CREATE_TABLE
      # note): prefix + downcased code, non-alphanumerics stripped so a
      # multi-part code stays one token. Shared by the write side here and by
      # Query::Search's `language :` filter — the fold-both-sides contract,
      # applied to language codes.
      def language_token(code)
        LANGUAGE_TOKEN_PREFIX + code.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      # Whether the LIVE fts table carries the P42-3 language column — the
      # write-side feature detect (insert_passage_batches) and Query::Search's
      # read-side one. A fresh rebuild! always creates it; an incremental
      # refresh into a pre-rebuild file honestly reports false and keeps
      # writing the old shape.
      def fts_language_column?(fulltext)
        fulltext[TABLE].columns.include?(:language)
      end

      # One streaming pass feeding the FTS and lemma tables (shared by
      # rebuild! and refresh_source!). Returns [passage count, lemma-row
      # count]. The fts row shape is detected ONCE from the live table
      # (CREATE_TABLE note): a pre-P42-3 table takes language-less rows.
      def insert_passage_batches(fulltext, dataset, tiers)
        with_language = fts_language_column?(fulltext)
        count = 0
        lemma_count = 0
        dataset.each_slice(BATCH_SIZE) do |batch|
          fulltext[TABLE].multi_insert(batch.map { |row| fts_row(row, language: with_language) })
          rows = batch.flat_map { |row| lemma_rows(row, tiers: tiers) }
          fulltext[LEMMA_TABLE].multi_insert(rows)
          count += batch.size
          lemma_count += rows.size
        end
        [count, lemma_count]
      end

      # ALL of the source's passage ids and urns — withdrawn included: rows
      # indexed while live must be deletable after their withdrawal, and the
      # catalog never hard-deletes, so this set covers every indexed row the
      # source ever contributed. Returns [Set of ids, Array of urns].
      def source_passage_keys(catalog, source_id)
        ids = Set.new
        urns = []
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id)
          .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:urn])
          .each do |row|
            ids << row.fetch(:passage_id)
            urns << row.fetch(:urn)
          end
        [ids, urns]
      end

      # Delete the source's rows from an FTS5 table: one streaming scan
      # collects the rowids whose passage_id is in +ids+ (passage_id is
      # UNINDEXED — per-batch IN deletes would each rescan the table), then
      # targeted rowid deletes. Returns the number of rows deleted.
      def delete_fts_rows(fulltext, table, ids)
        return 0 if ids.empty?

        doomed = []
        fulltext[table].select(:rowid, :passage_id).each do |row|
          doomed << row.fetch(:rowid) if ids.include?(row.fetch(:passage_id))
        end
        doomed.each_slice(BATCH_SIZE) { |batch| fulltext[table].where(rowid: batch).delete }
        doomed.size
      end

      # Delete the source's lemma rows by urn (B-tree indexed — no scan).
      # Returns the number of rows deleted.
      def delete_source_lemma_rows(fulltext, urns)
        urns.each_slice(BATCH_SIZE).sum do |batch|
          fulltext[LEMMA_TABLE].where(urn: batch).delete
        end
      end

      # The trigram slice: refresh when the source is flagged now, drop its
      # rows (and scope row) when the last build indexed it but the flag is
      # gone, and stay entirely hands-off otherwise (class note on
      # refresh_source!).
      def refresh_trigram_slice(catalog, fulltext, slug, fuzzy_slugs, ids)
        fuzzy = fuzzy_slugs.include?(slug)
        in_scope = !fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).empty?
        return unless fuzzy || in_scope

        delete_fts_rows(fulltext, TRIGRAM_TABLE, ids) if in_scope
        if fuzzy
          fulltext[TRIGRAM_SCOPE_TABLE].insert(slug: slug) unless in_scope
          trigram_passages(catalog, [slug]).each_slice(BATCH_SIZE) do |batch|
            fulltext[TRIGRAM_TABLE].multi_insert(batch.map { |row| index_row(row) })
          end
        else
          fulltext[TRIGRAM_SCOPE_TABLE].where(slug: slug).delete
        end
      end

      # Full alignment rebuild, but ONLY when the source holds a document the
      # registry names as a witness — the index is registry-scoped (157k rows
      # live), so regenerating it whole is cheap and keeps AlignmentIndexer
      # the single owner of its semantics; every other sync skips it.
      def refresh_alignment(catalog, fulltext, registry, source_id)
        return if registry.nil? || registry.empty?

        witness_urns = registry.works.flat_map(&:witnesses).flat_map(&:document_urns)
        return if catalog[:documents].where(source_id: source_id, urn: witness_urns).empty?

        AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext, registry: registry)
      end

      # The source's live passage count (two-level visibility) — what the
      # rebuild-fallback path reports, keeping "indexed N" per-source honest.
      def source_live_count(catalog, slug)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .where(Sequel[:sources][:slug] => slug)
          .count
      end

      # The lemma table (see class note). Plain Sequel DSL — no raw DDL. Created
      # BARE (P36-2): the three secondary indexes are deferred to
      # #create_lemma_indexes, built in one pass after the bulk insert rather
      # than maintained incrementally per row. rebuild! owns that call; the
      # sync incremental path (refresh_source!) never creates this table, so it
      # always sees the indexes the last rebuild left.
      def create_lemma_table(fulltext)
        fulltext.create_table(LEMMA_TABLE) do
          String :lemma_folded, null: false
          String :lemma_raw, null: false
          Integer :passage_id, null: false
          String :urn, null: false
          String :language, null: false
          String :surface_forms, null: false
          # The per-row lemma tier (P26-0, class note): "gold" | "silver".
          # No index — tier is always a residual filter AFTER an indexed
          # lemma_folded/urn/language equality.
          String :tier, null: false
        end
      end

      # Build the lemma table's three deferred secondary indexes (P36-2) over
      # the now-populated table, in one sorted pass each:
      # - lemma_folded: the primary lemma-search key.
      # - urn (P15-1): the lemma-aware second signals — parallels' rare-lemma
      #   co-occurrence and cognate-in-parallel (design §6) — look a passage's
      #   lemmas up BY urn. Without it the anchor lookup scans 2.6M rows
      #   (~1.7 s measured); with it, one B-tree hit. ~30–45 MB.
      # - language (P18-4 follow-up): `nabu language CODE` counts a language's
      #   gold rows; without it the card scans 2.85M rows (owner-measured 11.6 s
      #   per card). All rebuilt with the table (never migrated — the fulltext
      #   db is derived-of-derived; class note).
      def create_lemma_indexes(fulltext)
        fulltext.add_index(LEMMA_TABLE, :lemma_folded)
        fulltext.add_index(LEMMA_TABLE, :urn)
        fulltext.add_index(LEMMA_TABLE, :language)
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
            Sequel[:passages][:annotations_json],
            # source_id rides along for the lemma tier only (P26-0): the
            # per-source tier resolves through the small source_tiers map, not
            # a third join on the 2.6M-row streaming pass.
            Sequel[:documents][:source_id].as(:source_id)
          )
      end

      # { source_id => tier } from the catalog's sources and the registry's
      # non-gold map (P26-0). Absent slug = gold; the whole map is a handful
      # of rows, resolved once per rebuild.
      def source_tiers(catalog, lemma_tiers)
        catalog[:sources].select_map(%i[id slug]).to_h do |id, slug|
          [id, lemma_tiers.fetch(slug, GOLD_TIER)]
        end
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
      # This is the trigram table's whole row shape, and the passages_fts
      # base that fts_row builds on.
      def index_row(row)
        {
          text_normalized: row.fetch(:text_normalized),
          urn: row.fetch(:urn),
          passage_id: row.fetch(:passage_id)
        }
      end

      # The passages_fts row: index_row plus — when the live table carries
      # the P42-3 column — the language sentinel token. The language-less
      # branch keeps incremental syncs into a pre-rebuild file unchanged.
      def fts_row(row, language:)
        return index_row(row) unless language

        index_row(row).merge(language: language_token(row.fetch(:language)))
      end

      # The passage's lemma-index rows: one per distinct FOLDED lemma its
      # stored annotations attest, with the distinct surface forms aggregated
      # (class note). The cheap substring probe skips the JSON parse for the
      # vast non-treebank majority (annotations_json defaults to "{}"); a
      # false positive just parses and finds no token lemmas. annotations_json
      # is our own canonical_json output, so a parse failure is real corruption
      # and honestly raises.
      def lemma_rows(row, tiers: {})
        tier = tiers.fetch(row[:source_id], GOLD_TIER)
        return equivalence_rows(row) if tier == EQUIVALENCE_TIER

        json = row.fetch(:annotations_json)
        return [] if json.nil? || !json.include?('"lemma"')

        tokens = JSON.parse(json)["tokens"]
        return [] unless tokens.is_a?(Array)

        group_lemmas(tokens, language: row.fetch(:language)).map do |folded, entry|
          {
            lemma_folded: folded, lemma_raw: entry[:raw],
            passage_id: row.fetch(:passage_id), urn: row.fetch(:urn),
            language: row.fetch(:language), surface_forms: entry[:forms].join(", "),
            tier: tier
          }
        end
      end

      # The equivalence source's rows (P34-3, class constants above): keys
      # come from EQUIVALENCE_KEY only — never from "lemma", which the tier
      # declaration says is not a citation form there — and both the fold
      # and the stored language are EQUIVALENCE_LANGUAGE (a lemma row's
      # language IS the language its key is a dictionary form of; the hit's
      # passage keeps its own language catalog-side). The surface forms are
      # the non-Latin attestations, which is what makes a cross-language
      # hit readable ("quinque attested as pumperias").
      def equivalence_rows(row)
        json = row.fetch(:annotations_json)
        return [] if json.nil? || !json.include?("\"#{EQUIVALENCE_KEY}\"")

        tokens = JSON.parse(json)["tokens"]
        return [] unless tokens.is_a?(Array)

        group_lemmas(tokens, language: EQUIVALENCE_LANGUAGE, key: EQUIVALENCE_KEY)
          .map do |folded, entry|
            {
              lemma_folded: folded, lemma_raw: entry[:raw],
              passage_id: row.fetch(:passage_id), urn: row.fetch(:urn),
              language: EQUIVALENCE_LANGUAGE, surface_forms: entry[:forms].join(", "),
              tier: EQUIVALENCE_TIER
            }
          end
      end

      # { folded lemma => { raw:, forms: [] } } over the passage's tokens.
      # forms stays empty for a lemma attested only by form-less tokens
      # (PROIEL empty tokens carry no lemma in practice, but stay tolerated).
      # +key+ is the token field the dictionary form is read from — "lemma"
      # for the treebank families, EQUIVALENCE_KEY for the equivalence tier.
      def group_lemmas(tokens, language:, key: "lemma")
        tokens.each_with_object({}) do |token, grouped|
          lemma = token[key] if token.is_a?(Hash)
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
