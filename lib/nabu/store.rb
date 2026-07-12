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
      DocumentAxis: :document_axes
    }.freeze

    module_function

    # Open a Sequel database for +url+ (e.g. "sqlite::memory:" or a file path).
    # SQLite enforces foreign keys per-connection; Sequel's SQLite adapter
    # turns the pragma on by default, and we assert it explicitly here.
    # +readonly+ opens the file with SQLITE_OPEN_READONLY (P8-1: the MCP
    # surface must be POSITIVELY unable to write — the engine refuses, not
    # just our code declining to).
    def connect(url, readonly: false)
      db = Sequel.connect(sqlite_url(url), readonly: readonly)
      db.run("PRAGMA foreign_keys = ON") if db.database_type == :sqlite
      db
    end

    # Open the fulltext index database (architecture §2: a SEPARATE SQLite file
    # from the catalog). Same scheme-less-path handling as #connect so callers
    # can pass config.fulltext_path directly. No foreign_keys pragma: the index
    # is a standalone FTS5 table with no relational integrity to enforce (its
    # only link to the catalog is the UNINDEXED passage_id column).
    def connect_fulltext(url, readonly: false)
      Sequel.connect(sqlite_url(url), readonly: readonly)
    end

    # A bare filesystem path (no "scheme:" prefix) is taken as a SQLite file so
    # callers can hand us config.catalog_path directly; real connection strings
    # ("sqlite::memory:", "postgres://…") pass through untouched.
    def sqlite_url(url)
      url.match?(/\A[a-z][a-z0-9+.-]*:/i) ? url : "sqlite://#{url}"
    end

    # Apply all pending migrations from db/migrate to +db+. Returns +db+.
    def migrate!(db)
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, MIGRATIONS_DIR)
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
        @models_loaded = true
      end
      db
    end
  end
end

require_relative "store/ledger"
require_relative "store/loader"
require_relative "store/dictionary_loader"
require_relative "store/run_recorder"
require_relative "store/indexer"
require_relative "store/alignment_indexer"
require_relative "store/axis_builder"
