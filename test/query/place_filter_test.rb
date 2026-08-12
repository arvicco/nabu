# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::PlaceFilter (P75 C-1): one --place term resolves to its
  # identity claims — a namespaced mint directly, a NAME through the place
  # index and the registry's decisions (fold-both-sides), every seed
  # expanded one crosswalk hop. An unresolvable term stays the honest
  # name-LIKE fallback; a resolved name KEEPS its LIKE pattern so
  # name-only documents never fall out (recall composes, never shrinks).
  class PlaceFilterTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
    end

    def resolve(term, places: nil)
      Nabu::Query::PlaceFilter.resolve(term, catalog: @catalog, places: places)
    end

    def test_a_mint_term_is_the_identity_lane_with_no_name_pattern
      resolution = resolve("tm:2810")
      assert_equal [%w[tm 2810]], resolution.identities
      assert_nil resolution.pattern, "an explicit identity never rides the name-LIKE lane"
    end

    def test_an_unknown_mint_namespace_falls_back_to_the_name_lane
      resolution = resolve("riig:153")
      assert_empty resolution.identities
      assert_equal "riig:153", resolution.pattern
    end

    def test_a_like_pattern_stays_the_like_lane_untouched
      resolution = resolve("oxyrhynch%")
      assert_empty resolution.identities
      assert_equal "oxyrhynch%", resolution.pattern
    end

    def test_a_name_resolves_through_the_place_index_case_folded
      derive_cigs_girsu
      resolution = resolve("girsu")
      assert_equal [%w[cigs GIR]], resolution.identities
      assert_equal "girsu", resolution.pattern, "the name-LIKE lane rides along for name terms"
    end

    def test_a_name_resolves_through_registry_decisions
      places = Nabu::Places.new(
        "cdli" => { "Girsu" => { "status" => "matched", "refs" => ["cigs:GIR", "pleiades:912985"] } }
      )
      resolution = resolve("girsu", places: places)
      assert_equal [%w[cigs GIR], %w[pleiades 912985]], resolution.identities.sort
    end

    def test_non_matched_decisions_contribute_nothing
      places = Nabu::Places.new(
        "cdli" => { "Nowhere" => { "status" => "unlocatable", "refs" => [] } }
      )
      resolution = resolve("Nowhere", places: places)
      assert_empty resolution.identities
      assert_equal "Nowhere", resolution.pattern
    end

    def test_identities_expand_one_crosswalk_hop_both_directions
      @catalog[:place_crosswalk].insert(source: "t", gazetteer_a: "cigs", id_a: "GIR",
                                        gazetteer_b: "tm", id_b: "2810")
      @catalog[:place_crosswalk].insert(source: "t", gazetteer_a: "pleiades", id_a: "912985",
                                        gazetteer_b: "cigs", id_b: "GIR")
      resolution = resolve("cigs:GIR")
      assert_equal [%w[cigs GIR], %w[pleiades 912985], %w[tm 2810]], resolution.identities.sort
    end

    def test_an_unresolved_name_is_the_honest_like_fallback
      resolution = resolve("Atlantis")
      assert_empty resolution.identities
      assert_equal "Atlantis", resolution.pattern
    end

    private

    def derive_cigs_girsu
      place = Nabu::Pleiades::Place.new(id: "GIR", title: "Girsu", lat: 31.56, lon: 46.18,
                                        place_types: [], time_periods: [])
      Nabu::Store::PlaceIndex.derive!(@catalog, places: [place], gazetteer: "cigs")
    end
  end
end
