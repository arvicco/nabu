# frozen_string_literal: true

require "digest"

# Store tests run against a fresh migrated in-memory SQLite (CLAUDE.md).
# Mix this in and call #store_test_db in setup for an isolated database with
# the models bound to it. #ledger_test_db is the same rig for the history
# ledger (P7-1: its own file, migrations, and models in production).
#
# Speed without sharing: running ~50 migrations per test cost ~20 ms, paid
# thousands of times a suite. Instead each schema is migrated ONCE per
# process into a private in-memory template (never handed to a test), and
# every call gets a brand-new connection filled from it through SQLite's
# online-backup API — a page-for-page copy of the freshly migrated file, so
# each test still owns a real, empty, fully migrated database of its own.
# test/support/store_test_db_template_test.rb pins that a clone is
# schema-identical to a fresh migration and that clones share no state.
module StoreTestDB
  # The per-process migrated templates, keyed by schema kind.
  module Templates
    @templates = {}

    class << self
      # A fresh connection holding a copy of the +kind+ template; the
      # template itself is built on first use by +migrate+.
      def clone(kind, connect:, migrate:)
        template = (@templates[kind] ||= migrate.call(connect.call))
        db = connect.call
        copy!(from: template, to: db)
        db
      end

      # A digest of every row of every table in +db+ (sqlite_sequence and
      # rowids included, so the ids a later insert would mint are part of
      # the state). Schema is fixed by the migrations and not hashed.
      def digest(db)
        tables = db.fetch("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").map(:name)
        Digest::SHA256.hexdigest(Marshal.dump(tables.map { |table| [table, table_rows(db, table)] }))
      end

      def table_rows(db, table)
        quoted = db.literal(Sequel.identifier(table))
        db.fetch("SELECT _rowid_ AS __rowid__, * FROM #{quoted} ORDER BY _rowid_").map(&:to_a)
      rescue Sequel::DatabaseError # WITHOUT ROWID: no rowid to order by
        db.fetch("SELECT * FROM #{quoted}").map(&:to_a).sort_by(&:inspect)
      end

      # Page-for-page copy of +from+'s main database into +to+'s.
      def copy!(from:, to:)
        to.synchronize do |dst|
          from.synchronize do |src|
            backup = SQLite3::Backup.new(dst, "main", src, "main")
            backup.step(-1)
            backup.finish
          end
        end
        to
      end
    end
  end

  def store_test_db
    db = Templates.clone(
      :catalog,
      connect: -> { Nabu::Store.connect("sqlite::memory:") },
      migrate: ->(fresh) { Nabu::Store.migrate!(fresh) }
    )
    Nabu::Store.setup!(db)
    db
  end

  # Per-class template catalog: for a test class whose setup replays the
  # same loader over the same fixtures before every test. The FIRST call
  # in the class runs +build+ once against a fresh catalog (models bound
  # to it) and keeps the result as that class's private template; every
  # call — the first included — returns a brand-new in-memory copy of it
  # with the models rebound, so each test still starts from its own real
  # database in exactly the state the replay would have left (row ids and
  # sqlite_sequence included) and writes nothing any other test can see.
  # Re-read model rows the test needs from the returned db (by slug/id):
  # instances created during +build+ belong to the template.
  #
  #   def setup
  #     @catalog = class_template_db { |db| DictionaryLoader.new(db: db, ...).load_from(...) }
  #     @source = Nabu::Store::Source.first(slug: "lexica")
  #   end
  def class_template_db(name = :catalog, &build)
    templates = self.class.instance_variable_get(:@store_test_db_templates) ||
                self.class.instance_variable_set(:@store_test_db_templates, {})
    template = templates[name] ||= store_test_db.tap { |fresh| build.call(fresh) }
    db = Templates.copy!(from: template, to: Nabu::Store.connect("sqlite::memory:"))
    Nabu::Store.setup!(db)
    db
  end

  # Per-class memo of a deterministic MID-TEST load step (a rig like
  # load_recon_fixtures! called from test bodies rather than setup). The
  # step is keyed by +name+ AND a digest of +db+'s full contents at the
  # call (every row of every table, rowids and sqlite_sequence included):
  # the first time a class reaches that exact state + step it replays the
  # step and snapshots the result; any later arrival at the identical
  # state gets the snapshot restored INTO +db+ in place (same connection,
  # same models) — byte-for-byte what the replay would have produced. A
  # test that wrote anything else first has a different digest and simply
  # replays. Use only for steps that write nothing but +db+.
  def class_template_step(name, db:)
    steps = self.class.instance_variable_get(:@store_test_db_steps) ||
            self.class.instance_variable_set(:@store_test_db_steps, {})
    key = [name, Templates.digest(db)]
    if (snapshot = steps[key])
      Templates.copy!(from: snapshot, to: db)
    else
      yield
      steps[key] = Templates.copy!(from: db, to: Nabu::Store.connect("sqlite::memory:"))
    end
    db
  end

  def ledger_test_db
    db = Templates.clone(
      :ledger,
      connect: -> { Nabu::Store::Ledger.connect("sqlite::memory:") },
      migrate: ->(fresh) { Nabu::Store::Ledger.migrate!(fresh) }
    )
    Nabu::Store::Ledger.setup!(db)
    db
  end
end
