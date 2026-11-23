# frozen_string_literal: true

require "json"

require_relative "../normalize"
require_relative "../lemma_keys"

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
    # - Passage-keyed, urn-free (fts_lemma "v2-passage-keyed"): a row names
    #   its passage by the catalog passage id ONLY. The urn is derivable
    #   through the catalog (one primary-key hop), and storing it cost ~2 GB
    #   in-table plus a ~2.6 GB urn B-tree at 56M rows; the passage-keyed
    #   lookups (sync slice deletes, the frequency snapshots, the silver
    #   coverage guard, the parallels/cognates/vocab probes) ride a
    #   passage_id B-tree (~0.7 GB) instead. The v1 table (urn column + urn
    #   index) is RETIRED: its dual-shape write/read paths are gone, and a
    #   live v1 file meets require_v2_lemmas! at every entry point that
    #   once branched on it — one actionable error (run a full rebuild)
    #   instead of a silent second code path.
    # == The trigram index (P16-4) — fragment search, documentary scope
    #
    # passages_trigram is a second FTS5 table over the SAME folded search form
    # as passages_fts, tokenized into character trigrams so `search --fuzzy`
    # can match mid-word fragments (the papyrologist's ]μηνιν αει[). It is
    # deliberately NOT corpus-wide: at ~6 bytes/char the whole corpus costs
    # 3.6–4.1 GB, the documentary shelves ~250–270 MB (intertext design §4,
    # the owner-approved line). Which sources are in is an owner posture in
    # config/sources/ (`fuzzy_index: true` — see SourceRegistry::Entry for
    # the where-does-the-flag-live argument); callers thread the resulting
    # slug list in as +fuzzy_slugs+. The companion passages_trigram_scope
    # table records the slugs THIS build actually indexed, so the query
    # surface reports real coverage, never a config that may have drifted
    # since the last reindex. Same lifecycle as everything else here:
    # drop-and-rebuild, never migrated, disposable.
    #
    # == The lane files (the incrementality review's split)
    #
    # The trigram lane and the cjk lane below live in their OWN database
    # files beside this one (Store::Lanes — db/fulltext-trigram.sqlite3,
    # db/fulltext-cjk.sqlite3), ATTACHed onto every connect_fulltext
    # connection. Only their BUILDS know: rebuild_trigram!/rebuild_cjk!
    # ready the lane schema and qualify their DDL with it; every other
    # read and write here — and in the query layer — names the tables
    # unqualified and SQLite resolves them into the lane file.
    module Indexer
      TABLE = :passages_fts
      LEMMA_TABLE = :passage_lemmas
      TRIGRAM_TABLE = :passages_trigram
      TRIGRAM_SCOPE_TABLE = :passages_trigram_scope
      # P93-3: the CJK bigram lane — a CONTENTLESS second lane
      # over the cjk-flagged sources (sources.yml `cjk_index: true`).
      # REBUILD-CADENCE since the 2026-11-11 maintenance ruling: written
      # ONLY by rebuild_cjk!/refresh_cjk_lane! on the rebuild paths — a
      # sync or source refresh NEVER touches it (its in-place slice
      # rewrites were the 2026-11 multi-hour stall class), so between
      # rebuilds it serves the last rebuild's rows, at most one
      # rebuild-cadence stale. Each
      # Han/kana run of the folded text indexes as its overlapping
      # character pairs plus a trailing unigram (CjkBigrams — the mint
      # AND the query grammar), so a mid-run substring matches as a
      # phrase of consecutive bigrams — the thing unicode61's
      # one-token-per-run treatment can never answer. rowid = passages.id
      # (the P93-1 convention); language/source sentinel columns compose
      # exactly like the main table's; the scope table records what THIS
      # build actually indexed (the trigram honesty contract). Runless
      # passages contribute no row.
      CJK_TABLE = :passages_cjk
      CJK_SCOPE_TABLE = :passages_cjk_scope
      # P65: per-(source, char, language) counts of live passages containing
      # each Han character — the `nabu char` corpus panel's precompiled
      # answer. Minted here because the desk-time alternative is a LIKE scan
      # of the whole passages table (180 s at the 68M-row census,
      # 2026-08-10 — the owner-caught hang); the ruling is that the card
      # touches only precompiled data. Same lifecycle as everything else in
      # this file: derived, disposable, never migrated.
      CHAR_POSTINGS_TABLE = :char_postings

      # P72-1 (the Edubba graded-reading lane): per LIVE Han-bearing passage,
      # its distinct sorted (already-folded) chars, their count, and the four
      # RAREST by global docs-rank — r1..r4, each indexed. The coverage
      # search's candidate columns: a passage with ≤N foreign chars must
      # carry one of its N+1 rarest INSIDE the charset, so candidates come
      # from indexed r_i IN (charset) lookups whose selectivity tracks the
      # answer size — never a scan. Ranks are performance-only (the exact
      # subset check re-verifies), so refresh may rank against current
      # postings. Same lifecycle as the postings: derived, disposable.
      PASSAGE_CHARS_TABLE = :passage_chars
      RAREST_SLOTS = 4

      # P86-3 (owner-ruled 2026-08-28, B3): the postings' character class widens from Han-only
      # to EVERY character outside plain ASCII — the universal char card's
      # corpus panel ("where does ᚠ / α / ௐ actually occur") for any writing
      # system. Row count stays bounded by sources × alphabet × languages
      # (alphabets are small; Han was always the big one); the cost is the
      # accumulation pass now scanning nearly every passage instead of the
      # Han-bearing minority — a one-time re-accumulation that rides the next
      # owner-fired rebuild. passage_chars (the Edubba graded-reading lane)
      # deliberately stays HAN — its consumer is Han pedagogy.
      HAN = /\p{Han}/
      POSTED = /[^\x00-\x7F]/

      # The sentinel row stamping WHICH class an index was built with
      # (source_id −1, the language column carries the class token): the card
      # reads it to tell "zero attestation" from "index predates the
      # widening" — never a silent wrong zero.
      POSTINGS_CLASS = "non-ascii-v1"
      POSTINGS_CLASS_SOURCE = -1

      # P77-r16 (sign-learning survey P-3): the SIGN twins of the two Han
      # coverage tables, for the ATF corpora. sign_postings = per (source,
      # sign, language) passage counts (the rarity-rank source and the
      # corpus sign census); passage_signs = per resolvable passage its
      # distinct top-level OSL sign names, stray-token count, and the
      # RAREST_SLOTS rarest signs (r1..r4, indexed — the graded-candidate
      # columns, exactly the passage_chars trick). Built ONLY when a
      # SignList is supplied (no osl sync = no tables = the honest
      # absent-index answer) and only over SIGN_SOURCES — the ATF corpora
      # the sign-table census already scans; a new ATF source joins by
      # deliberate listing, never by drive-by. sign_postings refreshes at
      # full rebuild only (ranks are performance-only; the exact coverage
      # check re-verifies every candidate).
      SIGN_POSTINGS_TABLE = :sign_postings
      PASSAGE_SIGNS_TABLE = :passage_signs
      SIGN_SOURCES = %w[cdli oracc tlhdig].freeze
      # Sign names may contain dots/pipes/digits — a tab-joined list is
      # unambiguous where the chars column could simply concatenate.
      SIGN_SEP = "\t"

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
      EQUIVALENCE_SPEC = LemmaKeys::Spec.new(keys: [EQUIVALENCE_KEY].freeze, reject: nil, strip: nil)

      # Insert in slices so a 238k-passage corpus never materializes at once.
      BATCH_SIZE = 2_000

      # == The bulk slice mode (P111-1) — big content-bearing re-parses
      #
      # MEASURED problem: refresh_source!'s slice rewrite (delete + reinsert)
      # is FTS5-pathological at millions of rows — the deletemerge machinery
      # (default: a segment with 10% tombstones becomes merge-eligible)
      # fires DURING the contentless_delete tombstone storm, repeatedly
      # rewriting multi-GB segments as the ratio climbs (the kanripo shape:
      # 6h18m for an 8.75M-row slice, spinning in fts5IndexMergeLevel/
      # fts5DataDelete; P110-1's skip only covers the nothing-changed case).
      # Bulk mode sets deletemerge=0 for the pass so tombstones append
      # merge-free, ENSURE-restores the default (persisted index config — a
      # crashed run must never leave tombstones uncompactable), then
      # consolidates in an announced bounded loop of positive ('merge', N)
      # commands until the total_changes probe reports no work (< 2).
      #
      # automerge and crisismerge are DELIBERATELY left alone — the live
      # lesson (2026-10-01, fts5_index.c read at the crash): fts5 has a hard
      # cap of FTS5_MAX_SEGMENT = 2000 TOTAL segments, and fts5AllocateSegid
      # returns SQLITE_FULL ("database or disk is full") at the cap;
      # crisismerge is silently clamped to 1999 and fires per LEVEL, so with
      # automerge=0 a big insert flood accumulates level-0 segments until
      # the TOTAL (higher levels included) hits 2000 — the allocation fails
      # before crisis merge can ever trigger, and the index is left
      # write-WEDGED (even the merge command needs a segment allocation).
      # The first two cbeta runs died exactly there, deterministically, with
      # half a terabyte of disk free.
      #
      # What was once written here — that insert-side automerge is the same
      # amortized logarithmic cost every rebuild pays and was never the
      # pathology — the two 2026-11-11 merge stalls FALSIFIED. Twice, a
      # 3.77M-row ndl-kotenseki slice refresh ran its whole announced
      # insert loop in ~10 min, then ground for hours (3h+, then ~9h)
      # inside ONE sqlite3_step. The autopsy of the second (committed
      # state read after the kill): the stall was NOT the main loop at all
      # — every row and sidecar sha had committed — but the then-SILENT
      # cjk slice rewrite that follows it, and the committed structure sat
      # CALM the whole time (≤4 segments per level, both tables), so no
      # between-statement structure read could have seen it coming. Both
      # live stack samples agree on the grind itself: fts5IndexMergeLevel
      # → fts5DataDelete — the engine, inside an ordinary row-insert's
      # flush, continuing a merge whose input-segment cleanup walks a
      # deleted data range across a 26 GB-class b-tree, I/O-bound, sized
      # by the segments being consumed and not by the statement that
      # happened to trigger it. Changing the engine's knobs is no answer
      # (automerge=0 is the wedge above), and no statement-side budget can
      # bound work the engine schedules on its own clock inside a flush.
      # The defenses that remain OURS: the cjk lane left the write path
      # entirely (the 2026-11-11 maintenance ruling — REBUILD-CADENCE:
      # rebuilt whole as a linear append at rebuilds, zero inline
      # tombstones; the 2 × 3.77M-statement slice rewrites where both
      # grinds lived are gone by construction); every heavy stage
      # announces and ticks (a grind is then a visible event in a named
      # stage, caught by the run's watchdog — never a silent hang); the
      # heal grain reconciles the main index instead of re-deriving
      # (exact_heal_diff — million-row floods are rare arrival events, not
      # routine heals); and the merge governor below keeps segment-count
      # pressure paid down in bounded announced chunks between statements
      # (GOVERNOR_CHECK_EVERY_BATCHES / GOVERNOR_LEVEL_LIMIT /
      # FtsStructure::SEGMENT_WARN), so the flush-time heuristics find as
      # little standing debt as we can arrange. Why the engine chose an
      # hours-scale merge against a calm committed structure is OPEN — the
      # rolled-back statement's in-flight structure is unobservable; the
      # governor is a real backstop for the pressure it can see, not a
      # proof against this grind class.
      #
      # Contentless shape only — a legacy contentful file keeps the old path
      # until its next full rebuild, like every other shape arrival.
      #
      # == The deferral is universal (the 2026-11-11 ndl-kotenseki hang)
      #
      # MEASURED: a parse-only sync of ndl-kotenseki (+616 books, a 17,505-row
      # index delta) hung 5h+ at 100% CPU in its index stage — a live stack
      # sample read fts5UpdateMethod → fts5IndexFlush → fts5IndexMerge →
      # fts5IndexMergeLevel → fts5DataDelete: deletemerge-triggered segment
      # merges firing during the delta's inserts against a 57 GB index
      # carrying the tombstone debt of many earlier incremental syncs. The
      # gate measured the DELTA (ids >= threshold) while the hazard is the
      # INDEX's accumulated tombstone debt — a small delta ran with
      # deletemerge=10 live and paid the debt's merges inside one atomic
      # transaction. So the deferral + consolidation recipe now governs
      # EVERY slice write against the contentless shape (governed_fts_tables
      # keys on shape alone); on a debt-free index the consolidation probe
      # exits after one no-op chunk, so the universal recipe costs nothing
      # when there is no debt, and where there IS debt it is paid down in
      # the announced, ticked, checkpointed loop OUTSIDE the write's
      # transaction. BULK_SLICE_THRESHOLD now decides ONLY the transaction
      # shape (P111-1b below): atomic swap under it, autocommit + checkpoint
      # at/above it.
      BULK_SLICE_THRESHOLD = 500_000
      BULK_MERGE_SETTINGS = { "deletemerge" => 0 }.freeze
      DEFAULT_MERGE_SETTINGS = { "deletemerge" => 10 }.freeze
      MERGE_CHUNK_PAGES = 2_000

      # The merge governor's cadence (class note above): one structure
      # read per this many batches. A read is one small-blob fetch (the
      # shadow table's row 10) plus a varint decode — microseconds against
      # the 2,000-row batch it rides between — while 25 batches (50k rows)
      # is far too few for an insert flood to carry a level from the limit
      # below to the engine's crisis line between two reads.
      GOVERNOR_CHECK_EVERY_BATCHES = 25

      # The crisis-distance invariant: no level of a governed table holds
      # more than half of fts5's crisismerge (16) segments when our code
      # can help it — the engine's to-completion crisis merge is never
      # reached. The total-segment line is FtsStructure::SEGMENT_WARN
      # (1200 against the hard cap of 2000), shared with the health gauges.
      GOVERNOR_LEVEL_LIMIT = 8

      # == P111-1b — the transaction shape and the slice-pending marker
      #
      # MEASURED crash (2026-10-01, the first at-scale bulk run): the slice
      # refresh historically wrapped ALL its work in ONE transaction, and
      # SQLite's WAL retains every page version written inside an open
      # transaction — the 8.9M-row cbeta slice filled ~500 GB of free disk
      # at 11% of the insert pass (SQLITE_FULL), because a monolithic txn
      # also blocks every auto-checkpoint. So BULK slices run with NO
      # wrapping transaction: each statement batch autocommits (short txns
      # let the auto-checkpoint reclaim WAL continuously) and the pass ends
      # with an explicit TRUNCATE checkpoint. The price is atomicity — a
      # mid-run failure leaves a PARTIAL slice — paid deliberately, because
      # the refresh is re-entrant: delete + reinsert heals on the next run.
      # The ordinary (small) slice keeps its single-txn atomic swap.
      #
      # Which is why the fulltext file itself must record an unfinished
      # slice: a crashed refresh leaves the index behind the catalog while
      # the next idempotent load changes NOTHING — the P110-1 skip would
      # freeze the staleness in place. slice_refreshes marks a slug pending
      # at refresh start and finished at the end; SyncRunner's skip gate
      # defers to it, and a full rebuild clears it wholesale.
      SLICE_REFRESHES_TABLE = :slice_refreshes

      # == The row-sha sidecar — what makes a heal exact
      #
      # The contentless index cannot say what it indexed (no column value
      # reads back), so a crashed slice used to heal by rewriting the WHOLE
      # slice: delete + reinsert of millions of rows for a crash that left
      # a few thousand behind — tombstones, segments and WAL churn on the
      # multi-GB main index, proportional to the slice rather than to the
      # damage. fts_row_shas records, per indexed
      # rowid (= the catalog passage id), its source and the FIRST 8 BYTES
      # of the catalog content_sha256 the row was indexed from. Eight bytes
      # is the grain because the question is per-row change detection
      # within one passage's own history, not global identity: a 64-bit
      # prefix collision between a row's old and new content is a 2^-64
      # event per revision.
      #
      # The consistency invariant: a row's sidecar sha is REMOVED before
      # any of its fts/lemma rows go (the delete loops run sidecar first)
      # and UPSERTED as the last statement of each insert batch (after the
      # batch's fts and lemma rows). So a rowid whose sidecar sha matches
      # the catalog is fully indexed at the fts+lemma grain; a crash
      # between any two statements leaves the sidecar BEHIND the index,
      # never ahead of it, and the heal's diff counts that row as drift and
      # re-does it. refresh_source! heals by that diff when the sidecar
      # holds rows for the source (exact_heal_diff); a fulltext predating
      # the sidecar keeps the full-slice heal, and the table arrives at the
      # next full rebuild or full-slice rewrite — the standard
      # shape-arrival contract. Contentless shape only (a legacy rowid is
      # not the passage id). Never a readiness prerequisite.
      ROW_SHAS_TABLE = :fts_row_shas

      # == Above-budget rewrites become shadow builds (the incrementality review)
      #
      # The measured hours-class grinds (the two 2026-11-11 stalls, the
      # kanripo 6h18m) were all multi-million-row IN-PLACE rewrites of a
      # built fts5 structure: every delete leaves a tombstone, every
      # re-insert a segment, and the engine repays the resulting merge debt
      # on ITS clock, inside whichever later statement trips it — a debt no
      # between-statement governor can see coming. FTS5 is excellent at the
      # other shape: a linear append into a FRESH structure (every rebuild
      # proves it). So the write path now has a hard row budget on in-place
      # fts writes, per lane per run:
      #
      #   - AT or under IN_PLACE_ROW_BUDGET rows, the lane is written in
      #     place as before (the deferred-deletemerge recipe and the merge
      #     governor stay the backstop);
      #   - OVER it, the lane's new content is built as an APPEND-ONLY
      #     shadow — linear writes, batch-ticked, governed — and swapped in
      #     atomically; the old structure is DROPPED WHOLE. Zero tombstones,
      #     zero merge debt, no old structure for the engine to grind; the
      #     cost is linear and announced.
      #
      # Two grains, matching where each lane lives:
      #
      #   - passages_fts (the main file): the in-main-file SHADOW TABLE
      #     (SHADOW_TABLE). It is filled from the catalog with exactly the
      #     membership the old table had — every row the row-sha sidecar
      #     records for OTHER sources (re-derived from the catalog by id, so
      #     a deferred source's behind slice stays exactly as behind) plus
      #     the refreshing source's live rows — then one transaction drops
      #     the old table and renames the shadow over it. The lemma table,
      #     the sidecar and the aggregates are plain B-trees (no tombstone
      #     pathology) and keep their in-place slice writes, with the fts
      #     half of each batch skipped. The shadow needs a COMPLETE sidecar
      #     (shadow_ready?): a slice indexed before the sidecar existed has
      #     no recorded membership, so a shadow would silently drop it —
      #     that file stays in place, announced, until the next full
      #     rebuild backfills the sidecar.
      #   - the trigram lane (its own file, Store::Lanes): Lanes.build!
      #     already IS this pattern for whole-lane builds — an over-budget
      #     trigram write runs rebuild_trigram! (a fresh lane file, renamed
      #     over the serving one) instead of the in-place slice. The cjk
      #     lane never takes inline writes at all (rebuild-cadence).
      #
      # Crash honesty: the shadow is built BEFORE any destructive slice
      # write and under the pending marker. A death mid-build leaves the
      # old table serving untouched and an orphan shadow, which the next
      # refresh drops at entry; a death after the swap leaves an index
      # AHEAD of the sidecar, never behind it (the sidecar invariant still
      # holds — a current sha still means fully indexed), and the pending
      # marker heals the rest.
      #
      # The budget: 100k rows is the line the review drew between the
      # measured minutes-class in-place writes (the 17.5k-row ndl delta;
      # the ~35-document heals) and the hours-class ones (3.77M, 8.75M) —
      # comfortably above routine sync deltas, two orders below the grinds.
      # A named constant so a re-measurement moves it in one place. It now
      # governs the TRIGRAM lane only (rows written — that lane carries no
      # sidecar to count deletions by); passages_fts is classified by the
      # rows it DELETES (REWRITE_CEILING below).
      IN_PLACE_ROW_BUDGET = 100_000

      # == passages_fts classifies its write by rows DELETED (the mid-delta design)
      #
      # The row budget above classified the main index's write by rows
      # WRITTEN, while the pathology it guards against — tombstones plus
      # merge debt the engine repays on its own clock — is caused by rows
      # DELETED into a built structure. MEASURED (2026-11): a 580,254-row
      # NEW source, deleting nothing, paid a ~135M-row shadow (~55 min) for
      # what is a pure tail append — the very write shape the shadow itself
      # uses and proves fast (~41k rows/s). So per run, counting the doomed
      # rowids the index actually holds (fts_deleted_rows — the row-sha
      # sidecar's membership, conservative wherever it cannot vouch):
      #
      #   1. deleted == 0 → APPEND: no row cap; the batch-ticked governed
      #      writer appends at the rowid tail (no delete statement at all),
      #      then the EAGER consolidation (eager_consolidate! — the merge
      #      governor's own bounded chunks and stall detection) runs until
      #      every level is back under the governor's limit;
      #   2. 0 < deleted ≤ REWRITE_CEILING → REWRITE: delete + append in
      #      place as the small path always did, then the same eager loop —
      #      the debt is repaid on OUR clock, ticked and watcher-visible,
      #      never inside a later statement;
      #   3. above the ceiling — or when the ledger-priced rewrite forecast
      #      exceeds the full-shadow one (fts_path_forecast) — the SHADOW,
      #      unchanged. A shadow the sidecar cannot support (shadow_ready?
      #      false) keeps the pre-classifier contract: written in place,
      #      announced, until a full rebuild backfills the sidecar.
      #
      # Each run logs its decision in one line (fts_path_line: path, rows
      # written, rows deleted, forecast) and the append/rewrite unit is
      # ledgered under its path's stage (fts_append / fts_rewrite, the rows
      # it touched), so the ceiling — CONSERVATIVE at 1M deleted rows — is
      # raised from measured timings, never guessed. Bucket-sharded fts5
      # tables were rejected: bm25 corpus statistics are per table, so
      # ranked results would reorder across shards.
      REWRITE_CEILING = 1_000_000
      SHADOW_TABLE = :passages_fts_shadow
      # Shadow batches commit in groups: per-batch autocommit would flush a
      # level-0 segment per 2,000 rows, one wrapping transaction would hold
      # the whole multi-GB build in the WAL — 50 batches (100k rows) per
      # commit keeps both bounded.
      SHADOW_COMMIT_BATCHES = 50

      # == The heal's lemma census, bounded to the healed source
      #
      # lemma_frequencies and reflex_root_stats are corpus aggregates the
      # slice moves by its before/after delta. A healing refresh used to
      # throw the delta away and re-census lemma_frequencies over the WHOLE
      # lemma table (tens of millions of rows) — "the crashed run's
      # before-snapshot is lost". Whether it is lost depends on the crashed
      # run's TRANSACTION SHAPE, which slice_refreshes now records:
      #
      #   - "atomic" (the ordinary slice — one transaction holds the lemma
      #     writes AND the census delta): a crash rolled the whole unit
      #     back, so the census still matches the lemma table and the
      #     heal's own before/after delta is exact. O(Δ).
      #   - "bulk" (autocommit statement batches — P111-1b): the lemma
      #     writes and the census delta are NOT atomic, so before its first
      #     destructive write a bulk run journals the source's WHOLE
      #     contribution to both aggregates here (O(source) — inside a run
      #     that is already O(slice) by definition), and moves the census
      #     by baseline → the source's whole current contribution, clearing
      #     the baseline in the SAME transaction. A run that crashes leaves
      #     the baseline standing; the next run — heal or not — finds it
      #     and finishes the move exactly. Bounded to the healed source.
      #   - unrecorded (a marker minted before shapes were): the heal still
      #     applies its own delta, and flags the census stale
      #     (Store::StaleAggregates, "lemma_census") for the maintenance
      #     rail's corpus re-census — never inline.
      #
      # Rows: (slug, kind "freq"|"stats", lemma_folded, language, tier, n);
      # dropped by every full rebuild. Same lifecycle as the rest of the
      # file: derived, disposable, never migrated.
      CENSUS_BASELINES_TABLE = :lemma_census_baselines
      CENSUS_AGGREGATE = "lemma_census"

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
      # == The source column (P81-3) — index-side --source/--axis
      #
      # The SAME starvation genus, found live 2026-08-20: `search 王 --source
      # sillok` returned empty because --source post-filtered the bounded
      # global window, which the Han-dense cbeta/kanripo shelves had filled.
      # `source` holds one sentinel token per row ("0src" + the slug
      # downcased with non-alphanumerics stripped — "sillok" → "0srcsillok",
      # "nabu-data" → "0srcnabudata"), and Query::Search composes
      # `... AND source : ("0srcsillok")`. --axis needs no column of its
      # own: an axis is a registry TAG over the source list, already
      # expanded to member slugs CLI-side, so it compiles to an OR of
      # source tokens inside the one column filter.
      #
      # The column appears when this table is next built FROM SCRATCH (the
      # owner's scheduled full rebuild). Incremental refreshes write the
      # shape the live table actually has (insert_passage_batches feature-
      # detects), so a pre-P42-3/P81-3 index keeps taking syncs unchanged
      # until then, and Query::Search serves the old catalog-side path
      # against it.
      #
      # == The contentless shape (P93-1) — the text lives ONCE
      #
      # MEASURED problem (2026-09-02): fulltext.sqlite3 stood at 87 GB
      # beside a 118 GB catalog — passages_fts stored a full second copy of
      # every passage's folded text, and nothing has READ it since P39-r3
      # moved snippets onto the pristine catalog text (StoredSnippet). The
      # fresh shape is `content='' , contentless_delete=1`: only the
      # inverted index is stored, and — contentless semantics — NO column
      # value is readable back (UNINDEXED payloads included), so the urn/
      # passage_id columns are GONE and identity is the ROWID, minted as
      # the catalog passage id (the passage_chars rowid convention). Every
      # reader joins back to the catalog by rowid;
      # fts_passage_id_expression is the shape-aware read seam.
      # contentless_delete (SQLite ≥3.43; the bundled engine is 3.54.1) makes per-row
      # DELETE real, so the incremental slice refresh keeps working — by
      # key now, no streaming scan (delete_fts_rows_by_rowid).
      # Same arrival contract as the columns above: the shape appears at
      # the next FULL rebuild; a legacy contentful file keeps taking syncs
      # in its own shape, payload columns populated, until then.
      CREATE_TABLE = <<~SQL
        CREATE VIRTUAL TABLE passages_fts USING fts5(
          text_normalized,
          language,
          source,
          content = '',
          contentless_delete = 1,
          tokenize = 'unicode61 remove_diacritics 2'
        )
      SQL

      # The language sentinel-token prefix (CREATE_TABLE note): a leading
      # digit guarantees no natural-language token ever collides.
      LANGUAGE_TOKEN_PREFIX = "0lang"

      # The source sentinel-token prefix (P81-3, source-column note): same
      # leading-digit disjointness, distinct from the language namespace.
      SOURCE_TOKEN_PREFIX = "0src"

      # Trigram FTS5 DDL (class note; same raw-DDL exception as CREATE_TABLE —
      # virtual-table DDL has no Sequel API). Same column shape as
      # passages_fts so index_row feeds both; only the tokenizer differs.
      # A template over the SCHEMA the table is created in: the lane lives
      # in its own attached file (Store::Lanes), so the build qualifies its
      # DDL with the lane schema while every reader stays unqualified.
      CREATE_TRIGRAM_TABLE = <<~SQL
        CREATE VIRTUAL TABLE %<schema>s.passages_trigram USING fts5(
          text_normalized,
          urn UNINDEXED,
          passage_id UNINDEXED,
          tokenize = 'trigram'
        )
      SQL

      # The CJK lane's DDL (P93-3, CJK_TABLE note): contentless like the
      # main table; plain unicode61 — the cjk column holds space-joined
      # bigram tokens, already the token grain, and the sentinel columns
      # tokenize as they always have. Schema-templated like the trigram's.
      CREATE_CJK_TABLE = <<~SQL
        CREATE VIRTUAL TABLE %<schema>s.passages_cjk USING fts5(
          cjk,
          language,
          source,
          content = '',
          contentless_delete = 1,
          tokenize = 'unicode61'
        )
      SQL

      module_function

      # The lane DDL for +schema+ (the attached lane schema at a build; any
      # schema name SQLite knows).
      def create_trigram_sql(schema) = format(CREATE_TRIGRAM_TABLE, schema: schema)
      def create_cjk_sql(schema) = format(CREATE_CJK_TABLE, schema: schema)

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
      # SourceRegistry#fuzzy_slugs (config/sources/ `fuzzy_index: true`).
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
      # +lemma_shelf+ (P84-1) is the Nabu::LemmaShelf (local-lemmas) — when
      # present, the silver-lemma projection runs AFTER the annotation pass
      # and its index build (insert-if-absent needs the passage-key B-tree) and
      # BEFORE the frequency census, so lemma_frequencies counts silver
      # rows wholesale. +lemma_filter_slugs+ names the sources under the
      # epigraphy dictionary filter (sources.yml `lemma_dictionary_filter`).
      def rebuild!(catalog:, fulltext:, alignments: nil, fuzzy_slugs: nil, cjk_slugs: nil,
                   lemma_tiers: nil, profile: nil, sign_list: nil, progress: nil, lemma_shelf: nil,
                   lemma_filter_slugs: nil) # rubocop:disable Lint/UnusedMethodArgument -- since 2026-08-29 the full path no longer projects (filter slugs ride the owner-fired apply); kept for caller stability
        fulltext.drop_table?(TABLE)
        fulltext.drop_table?(LEMMA_TABLE)
        fulltext.drop_table?(CHAR_POSTINGS_TABLE)
        # P111-1b: a full rebuild refreshes every slice by construction —
        # nothing stays pending (absent table = nothing pending).
        fulltext.drop_table?(SLICE_REFRESHES_TABLE)
        fulltext.drop_table?(ROW_SHAS_TABLE)
        fulltext.drop_table?(SHADOW_TABLE) # a killed shadow build's orphan
        StaleAggregates.drop!(fulltext) # every aggregate is fresh by construction
        fulltext.drop_table?(CENSUS_BASELINES_TABLE)
        fulltext.run(CREATE_TABLE)
        create_row_shas_table(fulltext, indexed: false)
        create_lemma_table(fulltext)
        create_char_postings_table(fulltext)
        tiers = source_tiers(catalog, lemma_tiers || {})

        count = 0
        timed(profile, :fts_lemma) do
          fulltext.transaction do
            count, _lemmas, chars = insert_passage_batches(fulltext, live_passages(catalog), tiers,
                                                           source_slugs(catalog), progress: progress)
            write_char_postings(fulltext, chars, stamp_class: true)
          end
          # P36-2: the lemma table was created BARE (create_lemma_table); build
          # its three B-tree indexes now, in one sorted pass over the populated
          # table, rather than maintaining them incrementally across millions of
          # per-row inserts. Still inside the fts_lemma stage and BEFORE the
          # reflex pass, which reads passage_lemmas by these very indexes.
          create_lemma_indexes(fulltext)
          index_row_shas(fulltext) # the sidecar's source_id B-tree, the same deferred pass
          # Owner-ruled 2026-08-29: the silver projection LEFT the rebuild
          # path — a full rebuild never pays the whole-shelf replay again
          # (the 2026-08-29 profile: 99m39s). The shelf is announced
          # honestly; `nabu lemma-enrich <lang> --index-only` projects it
          # when the owner chooses. The sync-refresh slice re-apply below
          # stays, ARM-GATED, so an owner-projected index survives routine
          # syncs but silver never sneaks back into a clean one.
          if lemma_shelf
            progress&.stage("silver lemmas: shelf present, NOT projected (owner-ruled 2026-08-29) — " \
                            "nabu lemma-enrich <lang> --index-only applies it")
          end
          # P42-1: the corpus lemma-frequency census, one grouped INSERT-SELECT
          # over the now-indexed lemma table (vocab's denominator + etym's
          # per-reflex counts read it instead of re-aggregating per query).
          LemmaFrequencies.rebuild!(fulltext)
        end
        timed(profile, :trigram) do
          rebuild_trigram!(catalog: catalog, fulltext: fulltext, fuzzy_slugs: Array(fuzzy_slugs))
        end
        # P93-3: the CJK bigram lane — its own scoped streaming pass, the
        # trigram precedent exactly.
        timed(profile, :cjk) do
          rebuild_cjk!(catalog: catalog, fulltext: fulltext, cjk_slugs: Array(cjk_slugs), progress: progress)
        end
        # P72-1: the coverage index — its own streaming pass (the trigram
        # precedent), AFTER the postings exist (the rarity ranks read them).
        timed(profile, :passage_chars) do
          rebuild_passage_chars!(catalog: catalog, fulltext: fulltext)
        end
        # P77-r16: the sign twins — two bounded passes over SIGN_SOURCES
        # only; a nil sign_list (no osl) builds nothing, honestly.
        timed(profile, :passage_signs) do
          rebuild_sign_coverage!(catalog: catalog, fulltext: fulltext, sign_list: sign_list,
                                 progress: progress)
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
        # The clarify lane (nabu_clarify): titles/sources/headwords/places,
        # a catalog-only pass over names — no passage text. It rides inside
        # the "fulltext index" umbrella stage, not yet a profiled sub-stage
        # of its own: a stage label lives in RebuildProfile (the shared
        # derivation core), whose edit would dirty every source stamp.
        rebuild_clarify!(catalog: catalog, fulltext: fulltext)
        # The translations lane (annotation-held translations,
        # Store::TranslationIndex): a scoped pass over the registry's
        # sources — same umbrella-stage stance as clarify above.
        TranslationIndex.rebuild!(catalog: catalog, fulltext: fulltext)
        # The token-gloss lane (Store::GlossIndex): a scoped pass over the
        # TokenGlosses sources — the same umbrella-stage stance.
        GlossIndex.rebuild!(catalog: catalog, fulltext: fulltext)
        # The annotations lane (Store::AnnotationIndex — declared
        # searchable annotation layers): a scoped pass over the
        # AnnotationKeys sources — the same umbrella-stage stance.
        AnnotationIndex.rebuild!(catalog: catalog, fulltext: fulltext)
        # The gloss-lines lane (Store::GlossLineIndex — passage-grain
        # content search of the token glosses): a scoped pass over the
        # declared gloss sources — the same umbrella-stage stance.
        GlossLineIndex.rebuild!(catalog: catalog, fulltext: fulltext)
        # P87-3: the reference path stamps every stage at its current
        # derivation version — the incremental path's comparison baseline.
        stamp_stages!(fulltext)
        count
      end

      # Fold a corpus-wide index sub-stage's wall time into +profile+, or just
      # run the block when there is none (P36-0).
      def timed(profile, stage, &)
        return yield if profile.nil?

        profile.measure(scope: Nabu::RebuildProfile::CORPUS, stage: stage, &)
      end

      # The language column's one-token search value for +code+ (CREATE_TABLE
      # note): prefix + downcased code, non-alphanumerics stripped so a
      # multi-part code stays one token. Shared by the write side here and by
      # Query::Search's `language :` filter — the fold-both-sides contract,
      # applied to language codes.
      def language_token(code)
        LANGUAGE_TOKEN_PREFIX + code.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      # The source column's one-token search value for +slug+ (P81-3,
      # source-column note): the language_token mint over source slugs.
      # Slugs are lowercase-and-dashes by house convention, so the strip
      # only ever removes separators; the write side and Query::Search's
      # `source :` filter share this mint, fold-both-sides.
      def source_token(slug)
        SOURCE_TOKEN_PREFIX + slug.to_s.downcase.gsub(/[^a-z0-9]/, "")
      end

      # Whether the LIVE fts table carries the P42-3 language column — the
      # write-side feature detect (insert_passage_batches) and Query::Search's
      # read-side one. A fresh rebuild! always creates it; an incremental
      # refresh into a pre-rebuild file honestly reports false and keeps
      # writing the old shape.
      def fts_language_column?(fulltext)
        fulltext[TABLE].columns.include?(:language)
      end

      # Whether the LIVE fts table carries the P81-3 source column — same
      # contract as fts_language_column?, same next-full-rebuild arrival.
      def fts_source_column?(fulltext)
        fulltext[TABLE].columns.include?(:source)
      end

      # Whether the LIVE fts table is the P93-1 contentless shape (no
      # payload columns — every legacy generation carried passage_id).
      # Same feature-detect contract, same next-full-rebuild arrival.
      def fts_contentless?(fulltext)
        !fulltext[TABLE].columns.include?(:passage_id)
      end

      # The shape-aware passage-id read (P93-1): contentless identity is
      # the rowid (= passages.id), aliased so every reader keeps consuming
      # row[:passage_id]; a legacy contentful table reads its stored
      # column. The query layer's one seam onto the shape difference.
      def fts_passage_id_expression(fulltext)
        fts_contentless?(fulltext) ? Sequel.lit("rowid").as(:passage_id) : Sequel[:passage_id]
      end

      # == The retired v1 lemma shape (class note)
      #
      # A v1 passage_lemmas still stores each row's passage urn and keys
      # its passage lookups on a urn B-tree; every consumer used to probe
      # the shape and branch. The coming from-scratch rebuild mints v2
      # everywhere, so the branches are gone — and a v1 file that is still
      # live must not fall into the v2 path either (a passage_id filter
      # there scans 56M rows; a v2-shaped insert fails its NOT NULL urn).
      # Every entry point that once branched calls this guard instead: one
      # clear, actionable error, never a silent wrong path.
      class LegacyLemmaShape < Nabu::Error; end
      LEGACY_LEMMA_MESSAGE = "this index predates the v2 lemma shape (passage_lemmas still carries the " \
                             "v1 urn column) — run a full rebuild (`nabu rebuild`) to mint the " \
                             "passage-keyed table"

      # Raise LegacyLemmaShape on a v1 lemma table; nil otherwise (an absent
      # table is not this guard's business — callers keep their own
      # table_exists? degrade). One column read (SELECT * LIMIT 0).
      def require_v2_lemmas!(fulltext)
        return nil unless fulltext.table_exists?(LEMMA_TABLE)
        raise LegacyLemmaShape, LEGACY_LEMMA_MESSAGE if fulltext[LEMMA_TABLE].columns.include?(:urn)

        nil
      end

      # The lemma rows of a set of passages (catalog ids), through the
      # passage_id B-tree. Unsliced — callers batch.
      def lemma_rows_of_passages(fulltext, ids:)
        require_v2_lemmas!(fulltext)
        fulltext[LEMMA_TABLE].where(passage_id: ids.to_a)
      end

      # One streaming pass feeding the FTS and lemma tables (shared by
      # rebuild! and refresh_source!). Returns [passage count, lemma-row
      # count]. The fts row shape is detected ONCE from the live table
      # (CREATE_TABLE note): a pre-P42-3 table takes language-less rows, a
      # pre-P81-3 one source-less rows. +slugs+ maps source_id → slug (the
      # source_slugs map) for the source token; nil suppresses the column
      # even against a source-bearing table (no caller does today).
      # P105-5d: the loop ticks per FULL batch — cbeta's slice
      # walked 8.75M passages for ~55 minutes reading as a hang (openiti
      # ~2h); a silent pass is a defect, not a style choice. Partial
      # (final) batches deliberately do not tick: a small corpus stays
      # silent (the non-tty one-close-line contract), and the sync
      # fallthrough into this full rebuild would otherwise stamp passage
      # counts onto the still-open parse+load stage.
      # +fts: false+ (the shadow path, SHADOW_TABLE note) skips each batch's
      # passages_fts half — the swapped-in shadow already holds those rows.
      def insert_passage_batches(fulltext, dataset, tiers, slugs = nil, progress: nil, fts: true, ledger: nil)
        with_language = fts_language_column?(fulltext)
        with_source = slugs && fts_source_column?(fulltext) ? slugs : nil
        contentless = fts_contentless?(fulltext)
        require_v2_lemmas!(fulltext)
        count = 0
        lemma_count = 0
        chars = Hash.new(0)
        governor = (fts_governor(fulltext, TABLE, progress: progress, ledger: ledger) if fts)
        with_shas = contentless && fulltext.table_exists?(ROW_SHAS_TABLE)
        dataset.each_slice(BATCH_SIZE) do |batch|
          if fts
            fulltext[TABLE].multi_insert(
              batch.map do |row|
                fts_row(row, language: with_language, source_slugs: with_source,
                             contentless: contentless)
              end
            )
          end
          rows = batch.flat_map { |row| lemma_rows(row, tiers: tiers, slugs: slugs) }
          fulltext[LEMMA_TABLE].multi_insert(rows)
          # LAST statement of the batch — the ROW_SHAS_TABLE invariant.
          write_row_shas(fulltext, batch) if with_shas
          batch.each { |row| accumulate_char_postings(chars, row) }
          count += batch.size
          lemma_count += rows.size
          progress&.load_tick(count, 0) if batch.size == BATCH_SIZE
          governor&.tick!
        end
        [count, lemma_count, chars]
      end

      # One passage's contribution to the char postings: each DISTINCT
      # non-ASCII character counts one doc under (source, char, language).
      # Plain-ASCII passages cost one fast regex check.
      def accumulate_char_postings(chars, row)
        text = row.fetch(:text_normalized).to_s
        return unless text.match?(POSTED)

        text.scan(POSTED).uniq.each do |char|
          chars[[row.fetch(:source_id), char, row[:language]]] += 1
        end
      end

      # ALL of the source's passage ids and urns — withdrawn included: rows
      # indexed while live must be deletable after their withdrawal, and the
      # catalog never hard-deletes, so this set covers every indexed row the
      # source ever contributed. Returns [Set of ids, Array of urns].
      # Split note: shared by the slice plan, the trigram delta and the census — kept in the core file.
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

      # Chunked where-in over catalog passage ids: one IN list per
      # BATCH_SIZE ids keeps every statement inside SQLite's bound-variable
      # budget, streamed as one Enumerator so the insert pass consumes it
      # like any dataset.
      # Split note: a shared batching helper (refresh, char postings, signs) — kept in the core file.
      def ids_scoped(dataset, ids)
        Enumerator.new do |y|
          ids.to_a.each_slice(BATCH_SIZE) do |batch|
            dataset.where(Sequel[:passages][:id] => batch).each { |row| y << row }
          end
        end
      end

      # Rowid-keyed delete in bound-variable-sized slices (the coverage
      # tables' delta swap).
      # Split note: shared by the slice refresh and the row-sha sidecar — kept in the core file.
      def delete_rowid_slices(fulltext, table, ids)
        ids.to_a.each_slice(BATCH_SIZE) { |batch| fulltext[table].where(rowid: batch).delete }
      end

      # The lemma table (see class note) — the narrow, passage-keyed shape.
      # Plain Sequel DSL — no raw DDL. Created
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
          String :language, null: false
          String :surface_forms, null: false
          # The per-row lemma tier (P26-0, class note): "gold" | "silver".
          # No index — tier is always a residual filter AFTER an indexed
          # lemma_folded/passage_id/language equality.
          String :tier, null: false
        end
      end

      # Build the lemma table's three deferred secondary indexes (P36-2) over
      # the now-populated table, in one sorted pass each:
      # - lemma_folded: the primary lemma-search key.
      # - passage_id: the passage key (P15-1 introduced it as a urn index) —
      #   the lemma-aware second signals (parallels' rare-lemma co-occurrence,
      #   cognate-in-parallel, design §6), the sync slice delete, the
      #   frequency snapshots and the silver coverage guard look a passage's
      #   lemmas up by it.
      # - language (P18-4 follow-up): `nabu language CODE` counts a language's
      #   gold rows; without it the card scans 2.85M rows (owner-measured 11.6 s
      #   per card). All rebuilt with the table (never migrated — the fulltext
      #   db is derived-of-derived; class note).
      def create_lemma_indexes(fulltext)
        fulltext.add_index(LEMMA_TABLE, :lemma_folded)
        fulltext.add_index(LEMMA_TABLE, :passage_id)
        fulltext.add_index(LEMMA_TABLE, :language)
      end

      # P87-2: the bulk-apply window — drop the three lemma indexes, run
      # the block's bulk inserts against the bare table, rebuild each index
      # in one sorted pass (the P36-2 trick at command grain). The ensure
      # arm means an interrupted apply still leaves the table indexed.
      def cycle_lemma_indexes(fulltext)
        require_v2_lemmas!(fulltext)
        drop_lemma_indexes(fulltext)
        yield
      ensure
        create_lemma_indexes(fulltext)
      end

      def drop_lemma_indexes(fulltext)
        %i[lemma_folded passage_id language].each do |column|
          fulltext.drop_index(LEMMA_TABLE, column)
        rescue Sequel::DatabaseError
          nil # a prior interrupted cycle may have left this one missing
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
            Sequel[:passages][:text_search].as(:text_normalized),
            Sequel[:passages][:urn],
            Sequel[:passages][:id].as(:passage_id),
            Sequel[:passages][:language],
            Sequel[:passages][:annotations_json],
            # The catalog sha the fts_row_shas sidecar records (ROW_SHAS_TABLE).
            Sequel[:passages][:content_sha256],
            # source_id rides along for the lemma tier only (P26-0): the
            # per-source tier resolves through the small source_tiers map, not
            # a third join on the 2.6M-row streaming pass.
            Sequel[:documents][:source_id].as(:source_id)
          )
      end

      # { source_id => slug } for the P81-3 source token (fts_row) — a
      # handful of rows, resolved once per rebuild/refresh, exactly the
      # source_tiers pattern.
      def source_slugs(catalog)
        catalog[:sources].select_map(%i[id slug]).to_h
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
            Sequel[:passages][:text_search].as(:text_normalized),
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

      # The passages_fts row: the text plus — when the live table carries
      # them — the P42-3 language sentinel token and the P81-3 source one
      # (+source_slugs+ is the source_id → slug map, or nil against a
      # pre-P81-3 table). The bare branches keep incremental syncs into a
      # pre-rebuild file unchanged. +contentless:+ (P93-1) mints the fresh
      # shape's row: rowid = the catalog passage id, no payload columns —
      # the text feeds the tokenizer at INSERT and is never stored.
      def fts_row(row, language:, source_slugs: nil, contentless: false)
        base = if contentless
                 { rowid: row.fetch(:passage_id), text_normalized: row.fetch(:text_normalized) }
               else
                 index_row(row)
               end
        base = base.merge(language: language_token(row.fetch(:language))) if language
        base = base.merge(source: source_token(source_slugs.fetch(row.fetch(:source_id)))) if source_slugs
        base
      end

      # The passage's lemma-index rows: one per distinct FOLDED lemma its
      # stored annotations attest, with the distinct surface forms aggregated
      # (class note). The cheap substring probe skips the JSON parse for the
      # vast non-treebank majority (annotations_json defaults to "{}"); a
      # false positive just parses and finds no token lemmas. annotations_json
      # is our own canonical_json output, so a parse failure is real corruption
      # and honestly raises.
      # +slugs+ (source_id → slug) selects the source's LemmaKeys spec
      # (P118-R4 S1): bhsa/dss read their own lexeme keys, everyone else
      # "lemma". Absent map (a caller predating the registry) = default.
      def lemma_rows(row, tiers: {}, slugs: nil)
        tier = tiers.fetch(row[:source_id], GOLD_TIER)
        return equivalence_rows(row) if tier == EQUIVALENCE_TIER

        annotation_rows(row, tier: tier, slugs: slugs)
      end

      # The annotation-keyed rows (every tier but equivalence).
      def annotation_rows(row, tier:, slugs:)
        spec = LemmaKeys.spec_for(slugs&.[](row[:source_id]))
        json = row.fetch(:annotations_json)
        return [] if json.nil? || !LemmaKeys.probe?(json, spec)

        tokens = JSON.parse(json)["tokens"]
        return [] unless tokens.is_a?(Array)

        group_lemmas(tokens, language: row.fetch(:language), spec: spec).map do |folded, entry|
          {
            lemma_folded: folded, lemma_raw: entry[:raw],
            passage_id: row.fetch(:passage_id),
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

        group_lemmas(tokens, language: EQUIVALENCE_LANGUAGE, spec: EQUIVALENCE_SPEC)
          .map do |folded, entry|
            {
              lemma_folded: folded, lemma_raw: entry[:raw],
              passage_id: row.fetch(:passage_id),
              language: EQUIVALENCE_LANGUAGE, surface_forms: entry[:forms].join(", "),
              tier: EQUIVALENCE_TIER
            }
          end
      end

      # { folded lemma => { raw:, forms: [] } } over the passage's tokens.
      # forms stays empty for a lemma attested only by form-less tokens
      # (PROIEL empty tokens carry no lemma in practice, but stay tolerated).
      # +spec+ (a LemmaKeys::Spec) names the token field(s) the dictionary
      # form is read from — "lemma" for the treebank families, a source's
      # registered lexeme keys (P118-R4 S1), EQUIVALENCE_KEY for the
      # equivalence tier. A token minting two keys that fold alike counts once.
      def group_lemmas(tokens, language:, spec: LemmaKeys::DEFAULT)
        tokens.each_with_object({}) do |token, grouped|
          LemmaKeys.lemmas(token, spec).each do |lemma|
            folded = Normalize.search_form(lemma, language: language)
            entry = grouped[folded] ||= { raw: lemma, forms: [] }
            form = token["form"]
            entry[:forms] << form if form && !form.empty? && !entry[:forms].include?(form)
          end
        end
      end
    end
  end
end

require_relative "indexer/refresh"
require_relative "indexer/shadow"
require_relative "indexer/lanes"
require_relative "indexer/census"
require_relative "indexer/bulk_slice"
require_relative "indexer/governor"
require_relative "indexer/row_shas"
require_relative "indexer/char_postings"
require_relative "indexer/signs"
require_relative "indexer/stage_stamps"
require_relative "indexer/clarify"
require_relative "indexer/write_path"
