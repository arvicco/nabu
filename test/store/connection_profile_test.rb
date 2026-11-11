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
