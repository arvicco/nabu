# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # The live-connection profile + page-size generation door (P112-3).
  # Measured problem: live connections ran SQLite's defaults — 2 MB page
  # cache, no mmap — against a 124 GB catalog; and both files were created
  # at page_size 4096. The profile applies on every connect; 8192 takes
  # effect only on a FRESH file (one-way door per file generation).
  class ConnectionProfileTest < Minitest::Test
    def pragma(db, name) = db.fetch("PRAGMA #{name}").single_value

    def test_connect_applies_the_live_profile
      db = Nabu::Store.connect("sqlite::memory:")

      assert_equal Nabu::Store::LIVE_CACHE_KIB, pragma(db, "cache_size")
    ensure
      db&.disconnect
    end

    def test_fresh_files_are_minted_at_the_new_page_size
      Dir.mktmpdir do |dir|
        path = File.join(dir, "fresh.sqlite3")
        db = Nabu::Store.connect_fulltext(path)
        begin
          db.create_table(:t) { Integer :x }

          assert_equal Nabu::Store::PAGE_SIZE, pragma(db, "page_size")
          # The engine clamps the request to its compile-time max; granted
          # and nonzero is the contract.
          assert_operator pragma(db, "mmap_size"), :>, 0
        ensure
          db.disconnect
        end
      end
    end

    def test_existing_files_keep_their_page_size
      Dir.mktmpdir do |dir|
        path = File.join(dir, "legacy.sqlite3")
        legacy = Sequel.connect("sqlite://#{path}")
        legacy.run("PRAGMA page_size = 4096")
        legacy.create_table(:t) { Integer :x }
        legacy.disconnect

        db = Nabu::Store.connect(path)
        begin
          assert_equal 4096, pragma(db, "page_size"),
                       "the pragma is a documented no-op on an existing database"
        ensure
          db.disconnect
        end
      end
    end

    # The catalog's own page size: a fresh catalog file comes up at
    # CATALOG_PAGE_SIZE through the catalog seam, while every other file
    # (ledger, journals, vectors — the generic connect) stays at PAGE_SIZE.
    def test_a_fresh_catalog_file_is_minted_at_the_catalog_page_size
      Dir.mktmpdir do |dir|
        catalog = Nabu::Store.connect_catalog(File.join(dir, "catalog.sqlite3"))
        other = Nabu::Store.connect(File.join(dir, "history.sqlite3"))
        begin
          [catalog, other].each { |db| db.create_table(:t) { Integer :x } }

          assert_equal 32_768, Nabu::Store::CATALOG_PAGE_SIZE
          assert_equal Nabu::Store::CATALOG_PAGE_SIZE, pragma(catalog, "page_size")
          assert_equal Nabu::Store::PAGE_SIZE, pragma(other, "page_size"), "non-catalog files keep 8192"
          assert_equal "wal", pragma(catalog, "journal_mode"), "the page size landed before WAL engaged"
        ensure
          catalog.disconnect
          other.disconnect
        end
      end
    end

    # The bare-clone path: a first sync creates the catalog through the
    # CLI's open_or_create_catalog — the other from-scratch generation.
    def test_the_first_sync_opener_mints_the_catalog_at_the_catalog_page_size
      require "nabu/cli"
      Dir.mktmpdir do |dir|
        config = Nabu::Config.new(canonical_dir: File.join(dir, "canonical"), db_dir: File.join(dir, "db"),
                                  sources_path: File.join(dir, "sources.yml"),
                                  config_path: File.join(dir, "config", "nabu.yml"))
        db = Nabu::CLI.new.open_or_create_catalog(config)
        begin
          assert_equal Nabu::Store::CATALOG_PAGE_SIZE, pragma(db, "page_size")
        ensure
          db.disconnect
        end
      end
    end

    # The one-way door: an existing catalog generation keeps its page size
    # through the catalog seam (the pragma is a no-op once the file has
    # content and WAL is on) and keeps reading and writing normally.
    def test_an_existing_catalog_keeps_its_page_size_and_keeps_working
      Dir.mktmpdir do |dir|
        path = File.join(dir, "catalog.sqlite3")
        old = Nabu::Store.connect(path)
        old.create_table(:t) { Integer :x }
        old[:t].insert(x: 1)
        old.disconnect

        db = Nabu::Store.connect_catalog(path)
        begin
          assert_equal Nabu::Store::PAGE_SIZE, pragma(db, "page_size")
          db[:t].insert(x: 2)

          assert_equal [1, 2], db[:t].order(:x).select_map(:x)
          assert_equal "ok", pragma(db, "integrity_check")
        ensure
          db.disconnect
        end
      end
    end

    # db:snapshot goes through Store.vacuum_into!: the copy must keep the
    # SOURCE's page size, never silently convert either generation.
    def test_vacuum_into_keeps_the_source_page_size
      Dir.mktmpdir do |dir|
        { "catalog" => :connect_catalog, "history" => :connect }.each do |name, seam|
          source = File.join(dir, "#{name}.sqlite3")
          db = Nabu::Store.public_send(seam, source)
          db.create_table(:t) { Integer :x }
          db[:t].import([:x], (1..2000).map { |i| [i] })
          expected = pragma(db, "page_size")
          db.disconnect

          target = File.join(dir, "#{name}-snapshot.sqlite3")
          Nabu::Store.vacuum_into!(source, target)
          copy = Sequel.connect("sqlite://#{target}", readonly: true)
          begin
            assert_equal expected, pragma(copy, "page_size"), "#{name}: the snapshot keeps the source page size"
            assert_equal 2000, copy[:t].count
          ensure
            copy.disconnect
          end
        end
      end
    end

    def test_readonly_connects_still_get_the_read_path_knobs
      Dir.mktmpdir do |dir|
        path = File.join(dir, "ro.sqlite3")
        rw = Nabu::Store.connect(path)
        rw.create_table(:t) { Integer :x }
        rw.disconnect

        db = Nabu::Store.connect(path, readonly: true)
        begin
          assert_equal Nabu::Store::LIVE_CACHE_KIB, pragma(db, "cache_size")
          assert_operator pragma(db, "mmap_size"), :>, 0
        ensure
          db.disconnect
        end
      end
    end

    # The fulltext is derived-of-derived and re-runnable: read-write
    # connects PIN synchronous=NORMAL under WAL (no fsync per commit),
    # whatever the build's WAL default. The catalog connect sets nothing —
    # its posture stays the engine's own (Store.connect_fulltext note).
    def test_fulltext_writers_pin_synchronous_normal
      Dir.mktmpdir do |dir|
        fulltext = Nabu::Store.connect_fulltext(File.join(dir, "ft.sqlite3"))
        begin
          assert_equal 1, pragma(fulltext, "synchronous"), "NORMAL on a read-write fulltext connect"
        ensure
          fulltext.disconnect
        end
      end
    end

    def test_the_catalog_connect_keeps_the_engine_synchronous
      Dir.mktmpdir do |dir|
        path = File.join(dir, "cat.sqlite3")
        catalog = Nabu::Store.connect(path, rebuild: false)
        catalog.create_table(:t) { Integer :x }
        raw = Sequel.connect("sqlite://#{path}")
        begin
          assert_equal pragma(raw, "synchronous"), pragma(catalog, "synchronous"),
                       "the catalog connect leaves the engine's own durability posture alone"
        ensure
          raw.disconnect
          catalog.disconnect
        end
      end
    end

    def test_readonly_fulltext_connects_keep_the_live_profile_only
      Dir.mktmpdir do |dir|
        path = File.join(dir, "ft.sqlite3")
        rw = Nabu::Store.connect_fulltext(path)
        rw.create_table(:t) { Integer :x }
        rw.disconnect

        db = Nabu::Store.connect_fulltext(path, readonly: true, writer_profile: :index)
        begin
          assert_equal Nabu::Store::LIVE_CACHE_KIB, pragma(db, "cache_size"),
                       "a read-only connect never takes the writer cache"
        ensure
          db.disconnect
        end
      end
    end

    def test_index_writer_profile_raises_the_cache_on_top_of_the_live_profile
      Dir.mktmpdir do |dir|
        path = File.join(dir, "ft.sqlite3")
        writer = Nabu::Store.connect_fulltext(path, writer_profile: :index)
        casual = Nabu::Store.connect_fulltext(path)
        begin
          assert_equal Nabu::Store::INDEX_WRITER_CACHE_KIB, pragma(writer, "cache_size")
          assert_equal 1, pragma(writer, "synchronous")
          assert_operator pragma(writer, "mmap_size"), :>, 0, "the live mmap half still applies"
          assert_equal Nabu::Store::LIVE_CACHE_KIB, pragma(casual, "cache_size"),
                       "a casual read-write connect keeps the 64 MiB live cache"
        ensure
          writer.disconnect
          casual.disconnect
        end
      end
    end

    def test_rebuild_profile_keeps_its_larger_cache
      db = Nabu::Store.connect("sqlite::memory:", rebuild: true)

      assert_equal Nabu::Store::REBUILD_CACHE_KIB, pragma(db, "cache_size"),
                   "the rebuild cache overrides the live profile, never the reverse"
    ensure
      db&.disconnect
    end
  end
end
