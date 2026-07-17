# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# BilaraJsonParser tests (P26-1): the `bilara-json` family — SuttaCentral's
# bilara-data segment files, one flat ordered JSON map of
# "<segment-id>": "text" per document. Segment ids ARE the upstream citation
# scheme, so the parser's whole job is faithful transfer: citation = the
# segment id minus the redundant "<stem>:" prefix (kept whole, colons
# intact, for RANGE-STEM files whose ids carry per-item prefixes), blank
# segments skipped by rule, edge whitespace stripped, heading block (the
# leading 0.x segments of the first item) minted as the title.
class BilaraJsonParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("suttacentral")

  SN = File.join(FIXTURES, "root/pli/ms/sutta/sn/sn35/sn35.24_root-pli-ms.json")
  DHP = File.join(FIXTURES, "root/pli/ms/sutta/kn/dhp/dhp21-32_root-pli-ms.json")
  PDHP = File.join(FIXTURES, "root/pra/pts/sutta/pdhp/pdhp1-13_root-pra-pts.json")

  def parse(path, stem:, urn: "urn:nabu:suttacentral:#{stem}", language: "pli", **)
    Nabu::Adapters::BilaraJsonParser.new.parse(path, urn: urn, stem: stem, language: language, **)
  end

  # --- citation minting -------------------------------------------------------

  def test_citation_strips_the_redundant_stem_prefix
    document = parse(SN, stem: "sn35.24")
    assert_equal "urn:nabu:suttacentral:sn35.24", document.urn
    assert_equal "urn:nabu:suttacentral:sn35.24:0.1", document.first.urn
    assert_equal %w[0.1 0.2 0.3 1.1 1.2 1.3 1.4 1.6 1.7 1.8 1.9 1.10],
                 document.map { |p| p.urn.delete_prefix("#{document.urn}:") },
                 "upstream's own segment numbering, verbatim (1.5 is the blank skip)"
  end

  def test_range_stem_files_keep_the_full_segment_id_as_citation
    document = parse(DHP, stem: "dhp21-32")
    assert_equal "urn:nabu:suttacentral:dhp21-32:dhp21:0.1", document.first.urn,
                 "segment ids in a range-stem file carry per-verse prefixes that do NOT " \
                 "start with the stem — the full id IS the citation, colons intact"
    assert_equal 63, document.size
  end

  # --- text discipline --------------------------------------------------------

  def test_text_is_nfc_verbatim_with_edge_whitespace_stripped
    document = parse(SN, stem: "sn35.24")
    passage = document.find { |p| p.urn.end_with?(":1.1") }
    assert_equal "“Sabbappahānāya vo, bhikkhave, dhammaṁ desessāmi.", passage.text,
                 "upstream trailing space (a segment-join artifact) stripped; interior verbatim"
    assert passage.text.unicode_normalized?(:nfc)
  end

  def test_blank_segments_are_skipped_by_rule
    document = parse(SN, stem: "sn35.24")
    assert_equal 12, document.size, "13 upstream segments minus the empty sn35.24:1.5"
    assert_nil(document.find { |p| p.urn.end_with?(":1.5") })
  end

  def test_sequence_is_file_order
    document = parse(SN, stem: "sn35.24")
    assert_equal (0..11).to_a, document.map(&:sequence)
  end

  def test_pdhp_inline_unclear_markup_is_kept_verbatim
    document = parse(PDHP, stem: "pdhp1-13", language: "pra")
    passage = document.find { |p| p.urn.end_with?("pdhp2:1") }
    assert_includes passage.text, "<unclear>",
                    "editorial pseudo-markup is upstream text — canonical means canonical"
  end

  # --- the folded lookup pin (the pli axis rides the generic fold) ------------

  def test_pali_search_form_is_the_generic_diacritic_fold
    document = parse(SN, stem: "sn35.24")
    passage = document.find { |p| p.urn.end_with?(":1.1") }
    assert_includes passage.text_normalized, "dhammam",
                    "dhammaṁ folds to dhammam — ṁ falls to the generic mark strip"
    assert_equal "dhamma", Nabu::Normalize.search_form("dhammā", language: "pli"),
                 "the generic fold suffices for pli: dhammā/dhamma unify (no LANGUAGE_FOLDS key)"
  end

  # --- title minting ----------------------------------------------------------

  def test_title_is_the_heading_block_of_the_first_item
    assert_equal "Saṁyutta Nikāya 35.24 — 3. Sabbavagga — Pahānasutta",
                 parse(SN, stem: "sn35.24").title
    assert_equal "Khuddakanikāya — Dhammapada — Appamādavagga — Sāmāvatīvatthu",
                 parse(DHP, stem: "dhp21-32").title
    assert_equal "Patna Dharmapada — 1. Jama — siddhaṁ namaḥ sarvvabuddhadharmmāryyasaṅghebhyaḥ",
                 parse(PDHP, stem: "pdhp1-13", language: "pra").title,
                 "pdhp numbers its heading 0.0/0.1/0.2 — the whole leading 0.x run joins"
  end

  def test_title_falls_back_to_the_stem_when_no_heading_block_exists
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x1_root-pli-ms.json")
      File.write(path, JSON.generate({ "x1:1.1" => "text one", "x1:1.2" => "text two" }))
      assert_equal "x1", parse(path, stem: "x1").title
    end
  end

  # --- passthroughs -----------------------------------------------------------

  def test_license_override_and_metadata_ride_through
    document = parse(SN, stem: "sn35.24", license_override: "attribution",
                         metadata: { "kind" => "translation" })
    assert_equal "attribution", document.license_override
    assert_equal "translation", document.metadata["kind"]
  end

  # --- damage is loud ---------------------------------------------------------

  def test_malformed_json_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad_root-pli-ms.json")
      File.write(path, "{ not json")
      assert_raises(Nabu::ParseError) { parse(path, stem: "bad") }
    end
  end

  def test_non_map_or_non_string_segments_raise_parse_error
    Dir.mktmpdir do |dir|
      array = File.join(dir, "a_root-pli-ms.json")
      File.write(array, "[1, 2]")
      assert_raises(Nabu::ParseError) { parse(array, stem: "a") }

      nested = File.join(dir, "b_root-pli-ms.json")
      File.write(nested, JSON.generate({ "b:1" => { "x" => 1 } }))
      assert_raises(Nabu::ParseError) { parse(nested, stem: "b") }
    end
  end

  def test_all_blank_segments_raise_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "c_root-pli-ms.json")
      File.write(path, JSON.generate({ "c:1" => " ", "c:2" => "" }))
      assert_raises(Nabu::ParseError) { parse(path, stem: "c") }
    end
  end
end
