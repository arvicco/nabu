# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::CldfSpine (P46-6) — the thin CLDF reference spine: Concepticon
# concept ids and Glottolog languoid ids resolved the way Nabu::Pleiades
# serves place ids and Nabu::Lila serves Latin lemmas. THIN means the
# id-and-name spine plus what the WOLD/CLICS rows need to resolve — never
# the full datasets. Exercised against real trimmed head slices
# (test/fixtures/cldf-spine/README.md).
class CldfSpineTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("cldf-spine")

  def spine
    @spine ||= Nabu::CldfSpine.load(FIXTURES)
  end

  # --- concepts (Concepticon v3.4.0 rows, verbatim) --------------------------

  def test_resolves_a_concept_id_to_gloss_field_and_definition
    concept = spine.concept("965")
    assert_equal "965", concept.id
    assert_equal "WORLD", concept.gloss
    assert_equal "The physical world", concept.semantic_field
    assert_match(/The Earth with all its inhabitants/, concept.definition)
    assert_equal "Person/Thing", concept.category
    assert_nil concept.replacement_id
  end

  def test_a_wold_fixture_rows_concept_id_resolves_through_the_spine
    # test/fixtures/wold/cldf/parameters.csv row 5-92 ("the wine") carries
    # Concepticon_ID 1524 — the cross-fixture resolution pin.
    wine_row = File.readlines(File.join(Nabu::TestSupport.fixtures("wold"),
                                        "cldf", "parameters.csv")).find { |l| l.start_with?("5-92,") }
    concepticon_id = wine_row.split(",").fetch(2)
    assert_equal "WINE", spine.concept(concepticon_id).gloss
  end

  def test_a_clics_fixture_nodes_concept_id_resolves_through_the_spine
    # The CLICS fixture triangle's hub node carries ConcepticonId 1060.
    assert_equal "CHILD-IN-LAW", spine.concept("1060").gloss
    assert_equal "Kinship", spine.concept("2264").semantic_field
  end

  def test_a_retired_concept_carries_its_replacement_id
    # Concepticon 170 FATHER'S SISTER was superseded by 2691 — the spine
    # reports the pointer verbatim and never follows it silently.
    concept = spine.concept("170")
    assert_equal "2691", concept.replacement_id
    assert_equal "FATHER'S SISTER", concept.gloss
  end

  def test_unknown_concept_is_nil
    assert_nil spine.concept("999999")
    assert_nil spine.concept(nil)
  end

  # --- languoids (Glottolog-CLDF v5.3 rows, verbatim) ------------------------

  def test_resolves_a_glottocode_to_name_iso_and_family
    latin = spine.languoid("lati1261")
    assert_equal "Latin", latin.name
    assert_equal "lat", latin.iso
    assert_equal "language", latin.level
    assert_equal "indo1319", latin.family_id
    assert_equal "Indo-European", spine.family(latin.id).name
  end

  def test_a_family_row_has_no_family_of_its_own
    indo = spine.languoid("indo1319")
    assert_equal "family", indo.level
    assert_nil indo.family_id
    assert_nil spine.family("indo1319")
  end

  def test_iso_lookup_reaches_the_same_record
    assert_equal "oldh1241", spine.languoid_by_iso("goh").id
    assert_equal "Old High German (ca. 750-1050)", spine.languoid_by_iso("goh").name
  end

  # THE UPSTREAM-DEFECT PIN (P46-6 scouting find): WOLD v4.2 tags its "Old
  # Norse" donor with glottocode noon1243 — which Glottolog resolves to
  # Noone (Atlantic-Congo, Cameroon); real Old Norse is oldn1244. The spine
  # reports what Glottolog says, verbatim — which is exactly why the WOLD
  # donor map keys on the curated languoid NAME, never the glottocode.
  def test_wolds_old_norse_glottocode_is_noone_in_glottolog
    assert_equal "Noone", spine.languoid("noon1243").name
    assert_equal "atla1278", spine.languoid("noon1243").family_id
    assert_equal "Old Norse", spine.languoid("oldn1244").name
    assert_equal "non", spine.languoid("oldn1244").iso
  end

  def test_unknown_languoid_is_nil
    assert_nil spine.languoid("zzzz9999")
    assert_nil spine.languoid_by_iso("zz")
  end

  # --- loading shapes --------------------------------------------------------

  def test_counts_reflect_the_loaded_slices
    assert_equal 10, spine.concept_count
    assert_equal 11, spine.languoid_count
  end

  def test_a_missing_side_loads_empty_and_stays_honest
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "concepticon"))
      FileUtils.cp(File.join(FIXTURES, "concepticon", "concepticon.tsv"),
                   File.join(dir, "concepticon"))
      partial = Nabu::CldfSpine.load(dir)
      assert_equal 10, partial.concept_count
      assert_equal 0, partial.languoid_count
      assert_nil partial.languoid("lati1261")
    end
  end

  def test_load_default_feature_detects_the_canonical_tree
    Dir.mktmpdir do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"),
                                db_dir: File.join(root, "db"),
                                sources_path: File.join(root, "sources.yml"), config_path: "(test)")
      assert_nil Nabu::CldfSpine.load_default(config: config),
                 "no canonical/cldf-spine tree -> nil (the lila posture)"
      dest = File.join(root, "canonical", "cldf-spine")
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(FIXTURES, "*")], dest)
      spine = Nabu::CldfSpine.load_default(config: config)
      refute_nil spine
      assert_equal "WORLD", spine.concept("965").gloss
    end
  end
end
