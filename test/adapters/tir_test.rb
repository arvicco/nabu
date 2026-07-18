# frozen_string_literal: true

require "test_helper"

# The TIR adapter (P29-3): the Raetic (xrr) corpus of record, Vienna-wiki
# family. Fixtures = real api.php page envelopes retrieved 2026-07-18.
class TirTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("tir")

  def conformance_adapter
    Nabu::Adapters::Tir.new(delay: 0)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "tir"
  end

  def conformance_metadata_only?(document)
    document.metadata["text_layer"] == "none"
  end

  def adapter = conformance_adapter

  def parse_urn(urn)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_quotes_the_terms_of_use_and_holds_nc
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/scientific use only/, manifest.license)
    assert_match(/Creative Commons Attribution-ShareAlike 3\.0/, manifest.license)
    assert_match(/rightsinfo footer grant is empty/, manifest.license)
    assert_equal "wiki-template", manifest.parser_family
  end

  # --- discovery + parse ----------------------------------------------------

  def test_discover_yields_one_ref_per_inscription_page
    assert_equal %w[urn:nabu:tir:ak-1.1 urn:nabu:tir:ak-1.12 urn:nabu:tir:bz-10.1],
                 adapter.discover(FIXTURES).map(&:id)
  end

  def test_ak_1_1_renders_the_marked_scholarly_transliteration
    document = parse_urn("urn:nabu:tir:ak-1.1")
    assert_equal "xrr", document.language, "language=Raetic maps to xrr"
    assert_equal 1, document.count
    expected = "?]ṇuale ri?ienalṣẹ".unicode_normalize(:nfc)
    assert_equal expected, document.first.text
    assert_equal [")nuale", "ri?ienalse"], document.first.annotations["words"],
                 "both tokens' Word-page link forms ride the annotations (TIR's " \
                 "Word category holds fragment titles like ')armatan' — ')nuale' is real)"
  end

  def test_bz_10_1_parses_two_lines_with_line_grain_urns
    document = parse_urn("urn:nabu:tir:bz-10.1")
    assert_equal ["urn:nabu:tir:bz-10.1:1", "urn:nabu:tir:bz-10.1:2"], document.map(&:urn)
    assert_equal ["tnake p̣iθamu".unicode_normalize(:nfc), "laþe?"], document.map(&:text)
    assert_equal [0, 1], document.map(&:sequence)
  end

  def test_ak_1_12_keeps_the_single_illegible_marker_as_its_reading
    document = parse_urn("urn:nabu:tir:ak-1.12")
    assert_equal ["?"], document.map(&:text)
    assert_nil document.first.annotations["words"], "a letterless marker is notation, not a word link"
  end

  # --- metadata: join honesty, concordances ---------------------------------

  def test_trismegistos_sigla_become_tm_related_keys
    metadata = parse_urn("urn:nabu:tir:ak-1.1").metadata
    assert_equal ["tm:653493"], metadata["related"]
    assert_equal "prob. votive", metadata["facets"]["genre"]["value"]
  end

  def test_withheld_coordinates_stay_absent
    metadata = parse_urn("urn:nabu:tir:ak-1.1").metadata
    assert_equal "Achenkirch", metadata["place"]["site"]
    assert_equal "Austria", metadata["place"]["country"]
    assert_equal "47.526944", metadata["place"]["coordinate_n"],
                 "AK-1 rock carries no coordinates (withheld by request) — the site's stand in"
  end

  def test_bz_10_1_joins_through_the_slash_bearing_site_title
    metadata = parse_urn("urn:nabu:tir:bz-10.1").metadata
    assert_equal "Pfatten / Vadena", metadata["place"]["site"]
    assert_equal "Bozen / Bolzano", metadata["place"]["province"]
    assert_equal({ "value" => "slab", "raw" => "slab" }, metadata["facets"]["object_type"])
    assert_equal({ "value" => "porphyry", "raw" => "porphyry" }, metadata["facets"]["material"])
  end

  def test_reading_original_rides_as_metadata
    metadata = parse_urn("urn:nabu:tir:ak-1.1").metadata
    assert_includes metadata["reading_original"], "{{c|E}}"
    assert_equal "sinistroverse", metadata["direction"]
    assert_equal "Magrè alphabet", metadata["alphabet"]
  end
end
