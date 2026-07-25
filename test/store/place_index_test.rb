# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "zlib"
require "stringio"

module Store
  # Nabu::Store::PlaceIndex (P45-6): the derived place index — the Pleiades
  # gazetteer dump projected into catalog tables at LOAD time (sync/rebuild)
  # so the read surfaces (`nabu place`, the show findspot line, nabu_place)
  # stop paying the ~3 s / ~3.9 GB per-invocation JSON load. Same contract
  # as source_stats (P42-0): derived wholesale, rebuildable, idempotent.
  #
  # The resolver MUST preserve Nabu::Pleiades' pinned matching semantics
  # exactly: id lookup by string/integer; titled() exact case-insensitive on
  # the whole title OR any "/"-separated variant segment (P44-3) — never
  # fuzzy. Both paths share the same Ruby case-fold key functions, so the
  # SQLite path is Unicode-honest where SQLite's own lower() is ASCII-only.
  class PlaceIndexTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("pleiades")
    DUMP = File.join(FIXTURES, "dump.json")

    SEGESTA_ENTRIES = [
      { "id" => "462487", "title" => "Segesta/Egesta", "reprPoint" => [12.83, 37.94] },
      { "id" => "383775", "title" => "Segesta Tigulliorum" },
      { "id" => "963441586", "title" => "Doric temple of Segesta" }
    ].freeze

    def setup
      @db = store_test_db
    end

    def derive_fixture!(db = @db)
      Nabu::Store::PlaceIndex.derive!(db, places: Nabu::Pleiades.load(DUMP).each_place)
    end

    def derive_entries!(entries, db = @db)
      Nabu::Store::PlaceIndex.derive!(db, places: Nabu::Pleiades.from_entries(entries).each_place)
    end

    def resolver
      Nabu::Store::PlaceIndex.resolver(@db)
    end

    # -- feature detection -----------------------------------------------------

    def test_fresh_catalog_has_the_tables_but_no_resolver_until_derived
      assert Nabu::Store::PlaceIndex.available?(@db), "migration 021 creates the tables"
      refute Nabu::Store::PlaceIndex.populated?(@db)
      assert_nil resolver, "an underived index must not shadow the dump fallback"
    end

    def test_available_is_false_without_a_db
      refute Nabu::Store::PlaceIndex.available?(nil)
    end

    # -- derive + resolver round-trip ------------------------------------------

    def test_derive_populates_and_the_resolver_round_trips_both_fixture_places
      derive_fixture!
      refute_nil resolver
      assert_equal 2, resolver.size

      sparta = resolver.place("570685")
      assert_equal "570685", sparta.id
      assert_equal "Sparta", sparta.title
      assert_in_delta 37.0817, sparta.lat, 0.001, "lat is reprPoint[1] (GeoJSON [lon, lat])"
      assert_in_delta 22.4246, sparta.lon, 0.001
      assert_equal %w[settlement temple temple-2 archaeological-site], sparta.place_types
      assert_includes sparta.time_periods, "roman"
      assert_includes sparta.time_periods, "hellenistic-republican"

      sicilia = resolver.place(462_492)
      refute_nil sicilia, "integer ids are accepted, the dump-path contract"
      assert_equal "Sicilia (island)", sicilia.title
      assert_equal ["island"], sicilia.place_types
    end

    def test_unknown_id_resolves_to_nil
      derive_fixture!
      assert_nil resolver.place(999_999)
    end

    # -- titled: the pinned exact + "/"-segment semantics ----------------------

    def test_titled_matches_exact_titles_case_insensitively
      derive_fixture!
      assert_equal ["570685"], resolver.titled("sparta").map(&:id)
      assert_equal ["Sicilia (island)"], resolver.titled("SICILIA (ISLAND)").map(&:title)
    end

    def test_titled_is_exact_never_fuzzy
      derive_fixture!
      assert_empty resolver.titled("Sicilia"), "a title prefix is not an exact match — no fuzzy, by design"
      assert_empty resolver.titled("Spart")
    end

    def test_titled_matches_slash_separated_variant_segments_exactly
      derive_entries!(SEGESTA_ENTRIES)
      assert_equal ["462487"], resolver.titled("segesta").map(&:id),
                   "the variant segment matches; the multi-word and prose titles do not"
      assert_equal ["462487"], resolver.titled("EGESTA").map(&:id)
      assert_equal ["383775"], resolver.titled("Segesta Tigulliorum").map(&:id), "whole-title still matches"
      assert_empty resolver.titled("Tigulliorum"), "a space-separated word is not a variant name"
    end

    def test_titled_folds_unicode_case_like_the_dump_path
      derive_entries!([{ "id" => "579885", "title" => "Ἀθῆναι" }])
      assert_equal ["579885"], resolver.titled("ἀθῆναι").map(&:id),
                   "Ruby fold keys, not SQLite's ASCII lower() — Greek titlecase must match"
    end

    def test_titled_preserves_dump_order_for_homonyms
      derive_entries!(
        [
          { "id" => "2", "title" => "Same" },
          { "id" => "1", "title" => "same" }
        ]
      )
      assert_equal %w[2 1], resolver.titled("Same").map(&:id), "homonym titles return every bearer, dump order"
    end

    # -- idempotency + supersession --------------------------------------------

    def test_deriving_twice_yields_identical_rows
      derive_fixture!
      before = index_rows
      derive_fixture!
      assert_equal before, index_rows, "re-deriving the same dump must be a row-identical no-op"
    end

    def test_derive_supersedes_prior_rows_wholesale
      derive_fixture!
      derive_entries!(SEGESTA_ENTRIES)
      assert_equal 3, resolver.size
      assert_nil resolver.place("570685"), "a re-derive replaces the whole index, never accretes"
    end

    # -- the producer (the sync/rebuild seam) ----------------------------------

    def test_producer_derives_from_the_canonical_dump_and_reports_the_census
      Dir.mktmpdir do |workdir|
        FileUtils.cp(DUMP, File.join(workdir, "pleiades-places.json"))
        census = producer.run("pleiades", workdir: workdir)
        assert_equal 2, census.places
        assert_kind_of Numeric, census.seconds
        assert_equal 2, resolver.size
      end
    end

    def test_producer_reads_the_gzipped_dump_filename_the_fetch_lands
      Dir.mktmpdir do |workdir|
        File.binwrite(File.join(workdir, "pleiades-places.json.gz"), gzip(File.read(DUMP)))
        census = producer.run("pleiades", workdir: workdir)
        assert_equal 2, census.places
        assert_equal "Sparta", resolver.place("570685").title
      end
    end

    def test_producer_is_an_honest_no_op_without_a_dump_on_disk
      Dir.mktmpdir do |workdir|
        assert_nil producer.run("pleiades", workdir: workdir),
                   "no dump synced yet (the parse-only-before-first-fetch case) — derive nothing"
      end
      refute Nabu::Store::PlaceIndex.populated?(@db)
    end

    private

    def producer
      Nabu::Store::PlaceIndex::Producer.new(catalog: @db)
    end

    # Every derived row, fully materialized — the tables are deliberately
    # surrogate-key-free so two derivations of the same dump are literally
    # row-identical.
    def index_rows
      [@db[:place_index].order(:position).all, @db[:place_index_names].order(:pleiades_id, :name_key).all]
    end

    def gzip(text)
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.write(text)
      gz.close
      io.string
    end
  end
end
