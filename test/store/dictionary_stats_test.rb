# frozen_string_literal: true

require "test_helper"

module Store
  # Store::DictionaryStats (P106-1 — №R-69 generalization 2): the
  # dictionary-group census — one precompiled row per dictionary carrying
  # its shipped language code, its resolved lect node (through the
  # nabu-lects codemap, per-source overrides included; NULL = the registry
  # knows no such node — the censused-UNRESOLVED posture, honest and never
  # silent) and its live entry count. Cards and `define`'s header read
  # these few hundred rows instead of scanning millions of entries (the
  # desk-commands law); drop-and-reproject wholesale at rebuild, per
  # source after a dictionary-bearing sync.
  class DictionaryStatsTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
    LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")

    def setup
      @catalog = Nabu::Store.connect("sqlite::memory:")
      Nabu::Store.migrate!(@catalog)
      @lexica = @catalog[:sources].insert(slug: "lexica", name: "L", adapter_class: "X",
                                          license_class: "open")
      @derom = @catalog[:sources].insert(slug: "derom", name: "D", adapter_class: "X",
                                         license_class: "nc")
      @ls = dictionary(@lexica, slug: "ls", language: "la-med", entries: 3)
      @vul = dictionary(@derom, slug: "derom-vul", language: "la-vul", entries: 2)
      @oracc = dictionary(@lexica, slug: "oracc-mb", language: "akk-x-mbperi", entries: 1)
    end

    def teardown
      @catalog.disconnect
    end

    def registry
      Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH)
    end

    def dictionary(source_id, slug:, language:, entries:)
      id = @catalog[:dictionaries].insert(source_id: source_id, slug: slug,
                                          title: slug.upcase, language: language)
      entries.times do |n|
        @catalog[:dictionary_entries].insert(
          dictionary_id: id, urn: "urn:nabu:#{slug}:e#{n}", entry_id: "e#{n}",
          key_raw: "k#{n}", headword: "h#{n}", headword_folded: "h#{n}",
          body: "b", content_sha256: "x"
        )
      end
      id
    end

    def stats
      @catalog[:dictionary_stats].order(:slug).all
    end

    def test_rebuild_writes_one_row_per_dictionary_with_resolved_lect_and_count
      count = Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      assert_equal 3, count
      by_slug = stats.to_h { |row| [row[:slug], row] }
      # codemap: la-med -> lat:med
      assert_equal "lat:med", by_slug["ls"][:lect]
      assert_equal "la-med", by_slug["ls"][:language]
      assert_equal 3, by_slug["ls"][:entries]
      # per-source override: derom's la-vul -> roa:pro
      assert_equal "roa:pro", by_slug["derom-vul"][:lect]
      # no codemap row AND no registry node: censused NULL, never invented
      assert_nil by_slug["oracc-mb"][:lect]
      assert_equal 1, by_slug["oracc-mb"][:entries]
    end

    def test_rebuild_counts_only_live_entries
      @catalog[:dictionary_entries].where(dictionary_id: @ls, entry_id: "e0").update(withdrawn: true)
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      assert_equal 2, stats.find { |row| row[:slug] == "ls" }[:entries]
    end

    def test_rebuild_is_idempotent
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      first = stats
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      assert_equal first, stats
    end

    def test_rebuild_without_a_registry_leaves_every_lect_null
      count = Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: nil)
      assert_equal 3, count
      assert_equal [nil], stats.map { |row| row[:lect] }.uniq
    end

    def test_refresh_source_touches_only_that_sources_rows
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      @catalog[:dictionary_entries].where(dictionary_id: @vul, entry_id: "e0").update(withdrawn: true)
      Nabu::Store::DictionaryStats.refresh_source!(catalog: @catalog, lects: registry, slug: "derom")
      by_slug = stats.to_h { |row| [row[:slug], row] }
      assert_equal 1, by_slug["derom-vul"][:entries]
      assert_equal 3, by_slug["ls"][:entries], "other sources untouched"
    end

    def test_refresh_source_for_an_unknown_slug_is_a_no_op
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      assert_equal 0, Nabu::Store::DictionaryStats.refresh_source!(catalog: @catalog,
                                                                   lects: registry, slug: "nope")
      assert_equal 3, stats.size
    end

    def test_zero_entry_dictionaries_still_carry_a_row
      empty = @catalog[:dictionaries].insert(source_id: @lexica, slug: "empty",
                                             title: "E", language: "lat")
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      row = stats.find { |r| r[:dictionary_id] == empty }
      assert_equal 0, row[:entries]
      # identity resolution to a KNOWN anchor is a real node, not NULL
      assert_equal "lat", row[:lect]
    end
  end
end
