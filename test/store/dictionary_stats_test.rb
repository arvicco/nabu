# frozen_string_literal: true

require "test_helper"

module Store
  # Store::DictionaryStats (P106-1 — owner ruling, generalization 2): the
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
      @oracc = dictionary(@lexica, slug: "oracc-mb", language: "akk-x-unruled", entries: 1)
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

    # -- the shelf-grain date-band staging (Nabu::LectShelfDates) -------------

    def leme_shelf_dates
      Nabu::LectShelfDates.new(rules: [
                                 Nabu::LectShelfDates::Rule.new(id: "leme-lexicon-year", sources: %w[leme],
                                                                codes: %w[en], field: "lexicon_year", note: nil)
                               ])
    end

    def leme_shelf(slug, year:, entries: 2)
      @leme ||= @catalog[:sources].insert(slug: "leme", name: "LEME", adapter_class: "X",
                                          license_class: "attribution")
      id = @catalog[:dictionaries].insert(source_id: @leme, slug: slug, title: slug, language: "en")
      entries.times do |n|
        annotations = year ? JSON.generate("lexicon_year" => year) : nil
        @catalog[:dictionary_entries].insert(
          dictionary_id: id, urn: "urn:nabu:dict:#{slug}:e#{n}", entry_id: "e#{n}", key_raw: "k",
          headword: "h", headword_folded: "h", body: "b", content_sha256: "x", annotations_json: annotations
        )
      end
      id
    end

    def test_a_dated_shelf_carries_its_staged_lect_and_the_provenance_stamp
      leme_shelf("leme-cawdrey", year: "1604")
      leme_shelf("leme-johnson", year: "1755")
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry, shelf_dates: leme_shelf_dates)
      by_slug = stats.to_h { |row| [row[:slug], row] }
      assert_equal "en:early", by_slug["leme-cawdrey"][:lect]
      assert_equal "rule:date-band", by_slug["leme-cawdrey"][:lect_basis]
      assert_equal "dated 1604..1604 (lexicon_year)", by_slug["leme-cawdrey"][:lect_note]
      assert_equal "en", by_slug["leme-cawdrey"][:language], "the shipped code is untouched"
      assert_equal "en:late", by_slug["leme-johnson"][:lect]
      # shelves no rule covers keep the plain ladder, unstamped
      assert_equal "lat:med", by_slug["ls"][:lect]
      assert_nil by_slug["ls"][:lect_basis]
      assert_nil by_slug["ls"][:lect_note]
    end

    def test_a_covered_shelf_that_cannot_stage_keeps_the_bare_code_and_declares_why
      leme_shelf("leme-undated", year: nil)
      leme_shelf("leme-1477", year: "1477")
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry, shelf_dates: leme_shelf_dates)
      by_slug = stats.to_h { |row| [row[:slug], row] }
      assert_equal "en", by_slug["leme-undated"][:lect]
      assert_nil by_slug["leme-undated"][:lect_basis]
      assert_equal "bare: undated", by_slug["leme-undated"][:lect_note]
      assert_equal "en", by_slug["leme-1477"][:lect]
      assert_equal "bare: outside bands — dated 1477..1477 (lexicon_year)", by_slug["leme-1477"][:lect_note]
    end

    def test_staged_rebuild_is_idempotent_and_refresh_source_restages
      leme_shelf("leme-cawdrey", year: "1604")
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry, shelf_dates: leme_shelf_dates)
      first = stats
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry, shelf_dates: leme_shelf_dates)
      assert_equal first, stats
      Nabu::Store::DictionaryStats.refresh_source!(catalog: @catalog, lects: registry, slug: "leme",
                                                   shelf_dates: leme_shelf_dates)
      assert_equal first, stats
    end

    def test_without_shelf_dates_a_dated_shelf_stays_on_the_ladder
      leme_shelf("leme-cawdrey", year: "1604")
      Nabu::Store::DictionaryStats.rebuild!(catalog: @catalog, lects: registry)
      row = stats.find { |r| r[:slug] == "leme-cawdrey" }
      assert_equal "en", row[:lect]
      assert_nil row[:lect_basis]
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
