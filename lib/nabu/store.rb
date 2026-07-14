# frozen_string_literal: true

require "sequel"

module Nabu
  # Persistence boundary for the derived catalog (architecture §5). Owns the
  # DB connection, the migration runner, and the Sequel model classes.
  #
  # Model/DB binding: Sequel model classes bind to a database at
  # class-definition time, but the suite needs a fresh migrated in-memory DB
  # per store test while production uses a file DB. The standard Sequel
  # solution is used here: models are defined against Sequel::Model.db and
  # rebound with #set_dataset. Store.setup!(db) sets Sequel::Model.db, loads
  # the model files once, and on every (idempotent) call rebinds each model's
  # dataset to the given handle — so any db handle works and tests can swap in
  # a fresh in-memory database between runs.
  #
  # == Lock tolerance (P17-7): journal_mode=WAL + explicit busy_timeout
  #
  # Owner defect 2026-07-13: `nabu rebuild` died mid-papyri with
  # SQLite3::BusyException — a concurrent READER (an agent's `sqlite3
  # -readonly` session) held a SHARED lock while the loader committed. In
  # rollback-journal mode (SQLite's default) a COMMIT needs the EXCLUSIVE
  # lock, so ONE leisurely reader kills the writer once the busy wait runs
  # out — and no timeout fixes an unbounded reader.
  #
  # THE WAL VERDICT: WAL wins, timeout alone loses. journal_mode=WAL lets N
  # readers and 1 writer run concurrently — readers get a stable snapshot,
  # the writer appends to the -wal and never waits for them. That is exactly
  # this corpus's usage pattern: MCP/agent/CLI reads during owner syncs,
  # rebuilds, and batch producers. Costs, weighed honestly:
  # - `-wal`/`-shm` sidecar files appear next to each db while connections
  #   are open (the last connection checkpoints and removes the -wal on
  #   close). `nabu backup` copies live sidecars with each db and prunes
  #   stale ones at the target (Nabu::Backup, ops.md §9) — a main file
  #   restored next to an outdated -wal would replay old frames over it.
  # - Readonly opens of a WAL db work (sqlite ≥ 3.22 read-only WAL; db/ is
  #   local and writable, so the -shm poses no problem), and `sqlite3
  #   -readonly` sessions no longer endanger a writer — that is the point.
  # - WAL does not work across network filesystems; db/ is local APFS.
  # - PRAGMA journal_mode=WAL PERSISTS in the file. It is set here on every
  #   read-write connect — idempotent and self-healing, so existing dbs flip
  #   on their first open by this code and no migration is needed. Readonly
  #   connects never set it (the pragma would attempt a write); they inherit
  #   whatever the file already says.
  #
  # BUSY_TIMEOUT_MS still matters under WAL: it covers writer-vs-writer
  # overlap (a batch producer committing while a sync runs) and readers of a
  # db still in rollback mode (first readonly open before any writer flipped
  # it). Value: the longest LEGITIMATE lock holder is seconds-scale — MCP
  # reads are ms, batch links readbacks and loader/indexer commits are
  # single-digit seconds — so 10 s is that worst case with a comfortable
  # margin, while a genuinely wedged lock still fails inside a human's
  # patience. (Sequel's sqlite default is 5 s — the crash showed "implicit
  # and shorter than the longest reader" is not a policy; this is.) One
  # caveat, deliberately accepted: sqlite3's C-level busy handler blocks the
  # GVL, so two writer THREADS in one process would burn the timeout instead
  # of handing over — nabu's concurrent writers are separate processes
  # (owner CLI, agents, MCP server), where the wait works (tested).
  module Store
    MIGRATIONS_DIR = File.expand_path("../../db/migrate", __dir__)

    # Model constant => backing CATALOG table. Order matters only for
    # readability. Runs, pins, and revisions are LEDGER models — see
    # Store::Ledger (P7-1): they live in db/history.sqlite3, which rebuild
    # never drops, and are bound by Ledger.setup!.
    MODELS = {
      Source: :sources,
      Document: :documents,
      Passage: :passages,
      Provenance: :provenance,
      Enrichment: :enrichments,
      Dictionary: :dictionaries,
      DictionaryEntry: :dictionary_entries,
      DictionaryCitation: :dictionary_citations,
      DictionaryReflex: :dictionary_reflexes,
      DocumentAxis: :document_axes,
      LanguageName: :language_names
    }.freeze

    # How long any connection waits on a locked database before raising
    # (SQLite busy_timeout; Sequel's sqlite adapter takes :timeout in ms).
    # See the class doc: longest legitimate lock holder (seconds) + margin.
    BUSY_TIMEOUT_MS = 10_000

    module_function

    # Open a Sequel database for +url+ (e.g. "sqlite::memory:" or a file path).
    # SQLite enforces foreign keys per-connection; Sequel's SQLite adapter
    # turns the pragma on by default, and we assert it explicitly here.
    # +readonly+ opens the file with SQLITE_OPEN_READONLY (P8-1: the MCP
    # surface must be POSITIVELY unable to write — the engine refuses, not
    # just our code declining to). Readonly connects carry the busy timeout
    # too: a reader waiting on a rollback-mode writer's commit is just as
    # real as the reverse.
    def connect(url, readonly: false)
      db = Sequel.connect(sqlite_url(url), readonly: readonly, timeout: BUSY_TIMEOUT_MS)
      if db.database_type == :sqlite
        db.run("PRAGMA foreign_keys = ON")
        write_ahead_log!(db) unless readonly
      end
      db
    end

    # Open the fulltext index database (architecture §2: a SEPARATE SQLite file
    # from the catalog). Same scheme-less-path handling as #connect so callers
    # can pass config.fulltext_path directly. No foreign_keys pragma: the index
    # is a standalone FTS5 table with no relational integrity to enforce (its
    # only link to the catalog is the UNINDEXED passage_id column).
    def connect_fulltext(url, readonly: false)
      db = Sequel.connect(sqlite_url(url), readonly: readonly, timeout: BUSY_TIMEOUT_MS)
      write_ahead_log!(db) if !readonly && db.database_type == :sqlite
      db
    end

    # Flip +db+ to journal_mode=WAL (P17-7, class doc above): persistent in
    # the file, idempotent on every read-write connect, self-healing for dbs
    # created before WAL landed. The pragma RETURNS the resulting mode (a
    # row, so it goes through a dataset, not #run); ":memory:" databases
    # answer "memory" and are unaffected — they are per-connection and can
    # never contend anyway.
    def write_ahead_log!(db)
      db.fetch("PRAGMA journal_mode = wal").single_value
    end

    # A bare filesystem path (no "scheme:" prefix) is taken as a SQLite file so
    # callers can hand us config.catalog_path directly; real connection strings
    # ("sqlite::memory:", "postgres://…") pass through untouched.
    def sqlite_url(url)
      url.match?(/\A[a-z][a-z0-9+.-]*:/i) ? url : "sqlite://#{url}"
    end

    # Apply all pending migrations from db/migrate to +db+. Returns +db+.
    #
    # allow_missing_migration_files: phase-17 runs parallel packets on
    # reserved migration numbers (009 is another packet's; 010 landed
    # first, P17-3), so the sequence legitimately has a gap until the
    # phase merge closes it. The option only relaxes the contiguity
    # check — application order stays strictly numeric.
    def migrate!(db)
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, MIGRATIONS_DIR, allow_missing_migration_files: true)
      db
    end

    # Bind the store's models to +db+. Idempotent: first call loads the model
    # files (defining Nabu::Store::Source etc.), later calls just rebind their
    # datasets to +db+. Returns +db+.
    #
    # require_valid_table is switched off (globally, deliberately) BEFORE the
    # models load: `Sequel::Model(:dictionaries)` introspects its table at
    # class-definition time, and a LIVE catalog is only migrated on the write
    # paths (sync, rebuild) — the read surfaces (status/search/define, and
    # the MCP server, which opens READONLY and can never migrate) must open a
    # catalog that predates the newest migration without setup! itself
    # raising "no such table" (the P11-4 review blocker: migration 006 added
    # tables, and every CLI command crashed against a pre-006 catalog).
    # Global, not per-model, so the NEXT table-adding migration cannot
    # reintroduce the bug model by model; the cost — no definition-time
    # table-name validation — is covered by the suite's freshly-migrated
    # stores exercising every model. Runtime protection for genuinely absent
    # tables stays where it always was: the callers' table_exists? guards
    # (Query::Define, MCP nabu_define, CLI define).
    def setup!(db)
      Sequel::Model.require_valid_table = false
      Sequel::Model.db = db
      if @models_loaded
        MODELS.each_key { |const| const_get(const).set_dataset(db[MODELS.fetch(const)]) }
      else
        require_relative "store/source"
        require_relative "store/document"
        require_relative "store/passage"
        require_relative "store/provenance"
        require_relative "store/enrichment"
        require_relative "store/dictionary"
        require_relative "store/dictionary_entry"
        require_relative "store/dictionary_citation"
        require_relative "store/dictionary_reflex"
        require_relative "store/document_axis"
        require_relative "store/language_name"
        @models_loaded = true
      end
      db
    end
  end
end

require_relative "store/ledger"
require_relative "store/links_journal"
require_relative "store/loader"
require_relative "store/dictionary_loader"
require_relative "store/run_recorder"
require_relative "store/indexer"
require_relative "store/alignment_indexer"
require_relative "store/axis_builder"
require_relative "store/facet_builder"
require_relative "store/reflex_roots_indexer"
