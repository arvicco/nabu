# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

# Nabu::TmPleiadesCrosswalk — the Trismegistos-place → Pleiades crosswalk
# derived from two held files: EDH's own geography sidecar (CC BY-SA 4.0)
# and the Pleiades dump's Trismegistos backlinks (CC BY 3.0). Trimmed-real
# fixtures: test/fixtures/edh/geography/ (17 real features, seven TM ids,
# one per rule branch) and test/fixtures/pleiades/tm-backlinks/ (eight real
# place entries, key-trimmed — see each fixture README).
class TmPleiadesCrosswalkTest < Minitest::Test
  include StoreTestDB

  GEOGRAPHY = File.join(Nabu::TestSupport.fixtures("edh"), "geography", "edhGeographicData.json")
  DUMP = File.join(Nabu::TestSupport.fixtures("pleiades"), "tm-backlinks", "pleiades-places.json")

  def edh_claims = Nabu::TmPleiadesCrosswalk.edh_claims(GEOGRAPHY)

  def pleiades_claims
    Nabu::TmPleiadesCrosswalk.pleiades_claims(JSON.parse(File.read(DUMP))["@graph"])
  end

  def derivation
    Nabu::TmPleiadesCrosswalk.derive(edh: edh_claims, pleiades: pleiades_claims)
  end

  def pair_map(derived = derivation)
    derived.pairs.to_h { |pair| [pair.tm, [pair.pleiades, pair.source]] }
  end

  # A canonical root shaped like canonical/: edh/geography + pleiades/ dump.
  def with_canonical_root(edh: true, pleiades: true)
    Dir.mktmpdir do |root|
      if edh
        FileUtils.mkdir_p(File.join(root, "edh", "geography"))
        FileUtils.cp(GEOGRAPHY, File.join(root, "edh", "geography"))
      end
      if pleiades
        FileUtils.mkdir_p(File.join(root, "pleiades"))
        FileUtils.cp(DUMP, File.join(root, "pleiades"))
      end
      FileUtils.mkdir_p(File.join(root, "edh"))
      FileUtils.mkdir_p(File.join(root, "pleiades"))
      yield root
    end
  end

  def crosswalk_rows(catalog)
    catalog[:place_crosswalk].where(gazetteer_a: "tm", gazetteer_b: "pleiades")
                             .order(:id_a).select_map(%i[source id_a id_b])
  end

  # --- the two claim readers -------------------------------------------------

  def test_edh_claims_keep_every_feature_vote_and_skip_tm_without_pleiades
    claims = edh_claims
    assert_equal ["540639"], claims["15743"], "Anthedon: one feature, one pair"
    assert_equal %w[530835 530834 530835].sort, claims["15798"].sort,
                 "Corcyra: per-feature votes are kept, multiplicity intact"
    refute claims.key?("1851"), "Lebadea carries a TM uri but no pleiades uri — no claim"
  end

  def test_pleiades_claims_read_the_dumps_trismegistos_place_backlinks
    claims = pleiades_claims
    assert_equal ["540639"], claims["15743"]
    assert_equal ["570685"], claims["2181"], "Sparta cites TM place 2181"
    assert_equal %w[29492 569131178], claims["5181"].sort,
                 "two Pleiades places cite the one TM place (Assyria kingdom/region)"
  end

  # --- the merge rule ----------------------------------------------------------

  def test_agreement_mints_one_edh_row
    assert_equal %w[540639 edh], pair_map["15743"]
  end

  def test_edh_plurality_settles_its_own_split_features
    assert_equal %w[530835 edh], pair_map["15798"], "2 Corcyra votes beat 1 Paleopolis"
  end

  def test_edh_tie_is_broken_by_the_dumps_corroborating_claim
    assert_equal %w[786123 edh], pair_map["2207"], "Syene/Elephantina tie: the dump names Syene"
  end

  def test_uncorroborated_edh_tie_falls_through_to_the_dumps_single_claim
    assert_equal %w[265963 pleiades], pair_map["26184"],
                 "EDH ties two other places; the dump's own single claim stands"
  end

  def test_disagreement_is_won_by_edh
    assert_equal %w[321678 edh], pair_map["1327"], "EDH 321678 ×3 vs the dump's 570467"
    assert_equal 1, derivation.disagreements
  end

  def test_ambiguous_claims_are_withheld_never_guessed
    map = pair_map
    refute map.key?("26453"), "an EDH tie with no dump claim asserts nothing"
    refute map.key?("5181"), "a TM place two Pleiades places cite is ambiguous"
    assert_equal %w[26453 5181].sort, derivation.withheld.sort
  end

  def test_dump_only_claims_fill_the_gaps
    assert_equal %w[570685 pleiades], pair_map["2181"]
    assert_equal %w[265876 pleiades], pair_map["27183"]
  end

  def test_full_fixture_derivation_census
    derived = derivation
    assert_equal 7, derived.pairs.size
    assert_equal(4, derived.pairs.count { |pair| pair.source == "edh" })
    assert_equal(3, derived.pairs.count { |pair| pair.source == "pleiades" })
    assert_equal 2, derived.agreements, "Anthedon + the corroborated Syene tie"
    assert_equal derived.pairs.map(&:tm).sort, derived.pairs.map(&:tm).uniq.sort, "one row per TM place"
  end

  def test_one_side_alone_still_derives
    only_dump = Nabu::TmPleiadesCrosswalk.derive(edh: {}, pleiades: pleiades_claims)
    assert_equal(%w[1327 15743 2181 2207 26184 27183], only_dump.pairs.map(&:tm).sort)
    assert(only_dump.pairs.all? { |pair| pair.source == "pleiades" })
  end

  # --- the catalog write + producers --------------------------------------------

  def test_edh_producer_writes_the_two_provenance_slices
    catalog = store_test_db
    with_canonical_root do |root|
      census = Nabu::TmPleiadesCrosswalk::Producer.new(catalog: catalog)
                                                  .run("edh", workdir: File.join(root, "edh"))
      assert_equal 7, census.crosswalk_pairs
      assert_nil census.places, "the edh side derives no place-index slice"
    end
    rows = crosswalk_rows(catalog)
    assert_equal 7, rows.size
    assert_includes rows, %w[edh 1327 321678]
    assert_includes rows, %w[pleiades 2181 570685]
  end

  def test_rerun_supersedes_its_own_slices_and_leaves_others
    catalog = store_test_db
    catalog[:place_crosswalk].insert(source: "wikidata", gazetteer_a: "tm", id_a: "1", gazetteer_b: "pleiades",
                                     id_b: "2")
    catalog[:place_crosswalk].insert(source: "cigs", gazetteer_a: "cigs", id_a: "GIR", gazetteer_b: "pleiades",
                                     id_b: "912910")
    with_canonical_root do |root|
      producer = Nabu::TmPleiadesCrosswalk::Producer.new(catalog: catalog)
      2.times { producer.run("edh", workdir: File.join(root, "edh")) }
    end
    assert_equal 7, catalog[:place_crosswalk].where(source: %w[edh pleiades]).count, "idempotent"
    assert_equal 1, catalog[:place_crosswalk].where(source: "wikidata").count, "another source's slice survives"
    assert_equal 1, catalog[:place_crosswalk].where(source: "cigs").count
  end

  def test_producer_without_either_file_is_an_honest_no_op
    catalog = store_test_db
    catalog[:place_crosswalk].insert(source: "edh", gazetteer_a: "tm", id_a: "9", gazetteer_b: "pleiades",
                                     id_b: "9")
    with_canonical_root(edh: false, pleiades: false) do |root|
      assert_nil Nabu::TmPleiadesCrosswalk::Producer.new(catalog: catalog).run("edh", workdir: File.join(root, "edh"))
    end
    assert_equal 1, catalog[:place_crosswalk].count, "nothing on disk supersedes nothing"
  end

  def test_pleiades_producer_derives_the_index_and_the_crosswalk_from_one_dump_load
    catalog = store_test_db
    with_canonical_root do |root|
      census = Nabu::TmPleiadesCrosswalk::PleiadesProducer.new(catalog: catalog)
                                                          .run("pleiades", workdir: File.join(root, "pleiades"))
      assert_equal 8, census.places, "the place index derives as before"
      assert_equal 7, census.crosswalk_pairs
    end
    assert_equal 8, catalog[:place_index].where(gazetteer: "pleiades").count
    assert_equal 7, crosswalk_rows(catalog).size
  end

  def test_pleiades_producer_without_the_edh_sidecar_derives_the_dump_half
    catalog = store_test_db
    with_canonical_root(edh: false) do |root|
      census = Nabu::TmPleiadesCrosswalk::PleiadesProducer.new(catalog: catalog)
                                                          .run("pleiades", workdir: File.join(root, "pleiades"))
      assert_equal 6, census.crosswalk_pairs
    end
    assert(crosswalk_rows(catalog).all? { |source, _, _| source == "pleiades" })
  end

  def test_adapters_wire_the_producers
    assert Nabu::Adapters::Edh.place_index_producer?
    assert_instance_of Nabu::TmPleiadesCrosswalk::Producer,
                       Nabu::Adapters::Edh.place_index_producer(catalog: nil)
    assert_instance_of Nabu::TmPleiadesCrosswalk::PleiadesProducer,
                       Nabu::Adapters::Pleiades.place_index_producer(catalog: nil)
  end
end
