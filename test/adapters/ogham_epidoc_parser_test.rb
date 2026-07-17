# frozen_string_literal: true

require "test_helper"

# OghamEpidocParser (P25-1): layer-grain extraction of one OG(H)AM record —
# real Ogham codepoints byte-pinned NFC, charDecl glyph resolution,
# corr-over-sic in either order, the whole-layer :text fallback, the layer
# script-honesty language rule. All against real fixture records
# (test/fixtures/ogham/README.md).
class OghamEpidocParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ogham")
  CHARDECL = File.join(FIXTURES, "XML", "charDecl.xml")

  def parse(region, id, layer:, urn:, primary: false)
    Nabu::Adapters::OghamEpidocParser.new.parse(
      File.join(FIXTURES, "XML", region, "#{id}.xml"),
      urn: urn, layer: layer, glyphs: glyphs, primary: primary
    )
  end

  def glyphs
    @glyphs ||= Nabu::Adapters::OghamEpidocParser.glyph_map(CHARDECL)
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_mismatch_including_a_wrong_layer_suffix_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      parse("I-MAY", "I-MAY-010", layer: "transliteration", urn: "urn:nabu:ogham:i-may-010")
    end
    assert_match(/urn mismatch/, error.message)
    assert_match(/i-may-010-translit/, error.message)
  end

  # --- the base case: real Ogham codepoints, byte-pinned NFC ------------------

  def test_i_may_010_ogham_layer_byte_pinned_nfc
    document = parse("I-MAY", "I-MAY-010", layer: "ogham", urn: "urn:nabu:ogham:i-may-010", primary: true)
    assert_equal "pgl", document.language, "the edition div's own tag, verbatim"
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:ogham:i-may-010:1", passage.urn
    assert_equal "ᚇᚑᚈᚐᚌᚅᚔ", passage.text,
                 "ᚇᚑᚈᚐᚌᚅᚔ — the Ogham codepoints verbatim"
    assert passage.text.unicode_normalized?(:nfc)
    assert_equal [{ "form" => "ᚇᚑᚈᚐᚌᚅᚔ", "nymRef" => "dotagnas?" }], passage.annotations["words"]
  end

  def test_i_may_010_transliteration_layer_aligns_by_suffix
    document = parse("I-MAY", "I-MAY-010", layer: "transliteration",
                                           urn: "urn:nabu:ogham:i-may-010-translit")
    assert_equal 1, document.size
    assert_equal "urn:nabu:ogham:i-may-010-translit:1", document.first.urn
    assert_equal "DOTAGNI", document.first.text
    assert_equal "Cill na nGarbhán | Kilgarvan — transliteration", document.title,
                 "sibling titles name the layer"
  end

  # --- glyph resolution (S-SHE-001, Pictish) ----------------------------------

  def test_s_she_001_ogham_layer_resolves_glyph_refs_to_ogham_mappings
    document = parse("S-SHE", "S-SHE-001", layer: "ogham", urn: "urn:nabu:ogham:s-she-001", primary: true)
    assert_equal "xpi-Ogam", document.language, "Pictish, upstream's honest tag kept"
    line1 = document.find { |p| p.urn == "urn:nabu:ogham:s-she-001:1" }
    assert_equal "ᚉᚏᚏᚑᚄᚉᚉ᛬ ᚅᚐᚆᚆᚈᚃᚃᚇᚇᚐᚇᚇᚄ᛬ ᚇᚐᚈᚈᚏᚏ᛬ ᚐᚅᚅ", line1.text,
                 "angled_*/rabbit-eared_* variants resolve to their Ogham letters, ᛬ punctuation kept"
    line2 = document.find { |p| p.urn == "urn:nabu:ogham:s-she-001:2" }
    assert_includes line2.text, "ᚖ", "forfid_OI resolves to its forfid codepoint"
    assert_includes line2.text, "ᚏ‍ᚏ", "crosshatched_R's ZWJ-joined mapping survives NFC"
  end

  def test_s_she_001_transliteration_layer_uses_diplomatic_and_type_override
    document = parse("S-SHE", "S-SHE-001", layer: "transliteration",
                                           urn: "urn:nabu:ogham:s-she-001-translit")
    line2 = document.find { |p| p.urn == "urn:nabu:ogham:s-she-001-translit:2" }
    assert_includes line2.text, "ℝ", "crosshatched_R's diplomatic mapping"
    assert_includes line2.text, "OA", "g @type=interpretation_O overrides the diplomatic Oᴵ"
    refute_includes line2.text, "Oᴵ"
  end

  def test_s_she_001_derived_summary_ab_is_dropped
    document = parse("S-SHE", "S-SHE-001", layer: "transliteration",
                                           urn: "urn:nabu:ogham:s-she-001-translit")
    assert_equal 2, document.size, "the <ab type=\"list\"> one-line summary mints no passage"
  end

  def test_unknown_glyph_ref_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::OghamEpidocParser.new.parse(
        File.join(FIXTURES, "XML", "S-SHE", "S-SHE-001.xml"),
        urn: "urn:nabu:ogham:s-she-001", layer: "ogham", glyphs: {}
      )
    end
    assert_match(/has no charDecl glyph/, error.message)
  end

  # --- choice, repeated divs, inline languages (E-DEV-001) --------------------

  def test_e_dev_001_choice_keeps_corr_over_sic
    document = parse("E-DEV", "E-DEV-001", layer: "ogham", urn: "urn:nabu:ogham:e-dev-001", primary: true)
    line1 = document.find { |p| p.urn == "urn:nabu:ogham:e-dev-001:1:1" }
    assert_equal "ᚄᚃᚐᚅᚅᚒᚉᚔ", line1.text, "corr ᚅᚅ kept, sic ᚊᚊ dropped (corr listed first here)"
  end

  def test_e_dev_001_two_roman_divs_are_one_layer_document_with_textpart_paths
    document = parse("E-DEV", "E-DEV-001", layer: "roman", urn: "urn:nabu:ogham:e-dev-001-roman")
    assert_equal "lat", document.language, "xml:lang=la maps to 639-3"
    assert_equal %w[
      urn:nabu:ogham:e-dev-001-roman:2:1 urn:nabu:ogham:e-dev-001-roman:2:2
      urn:nabu:ogham:e-dev-001-roman:3:1
    ], document.map(&:urn)
    line = document.find { |p| p.urn == "urn:nabu:ogham:e-dev-001-roman:2:2" }
    assert_equal "maqui Rini", line.text
    assert_equal ["pgl"], line.annotations["languages"], "the pgl-tagged formula word inside the Latin edition"
  end

  def test_e_dev_001_transliteration_sheds_the_false_ogam_subtag
    document = parse("E-DEV", "E-DEV-001", layer: "transliteration",
                                           urn: "urn:nabu:ogham:e-dev-001-translit")
    assert_equal "pgl", document.language,
                 "upstream tags the Latin-capital layer pgl-Ogam; repeating the false script claim would lie"
    assert_equal "SVAQQUCI", document.first.text
  end

  # --- roman-only X record with textparts (E-CON-X03) -------------------------

  def test_e_con_x03_roman_only_record_with_per_textpart_line_restarts
    document = parse("E-CON", "E-CON-X03", layer: "roman", urn: "urn:nabu:ogham:e-con-x03-roman",
                                           primary: true)
    assert_equal "lat-Latn", document.language
    assert_equal %w[urn:nabu:ogham:e-con-x03-roman:1:1 urn:nabu:ogham:e-con-x03-roman:2:1],
                 document.map(&:urn), "textpart path keeps the repeated lb n=1 apart"
    assert_equal "VITALI FILI TORRICI", document.first.text
    words = document.first.annotations["words"]
    assert_equal(%w[VITALI FILI TORRICI], words.map { |w| w["form"] })
    assert_equal "vitalius", words.first["nymRef"]
  end

  # --- the whole-layer :text fallback (I-WAT-042) -----------------------------

  def test_i_wat_042_ogham_layer_without_lb_falls_back_to_one_text_passage
    document = parse("I-WAT", "I-WAT-042", layer: "ogham", urn: "urn:nabu:ogham:i-wat-042", primary: true)
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:ogham:i-wat-042:text", passage.urn
    assert_equal "ᚉᚒᚅᚐᚅᚓᚈᚐᚄ ᚋᚐᚊᚔ ᚋᚒᚉᚑᚔ ᚅᚓᚈᚐᚄᚓᚌᚐᚋᚑᚅᚐᚄ", passage.text
    assert_equal 3, passage.annotations.dig("leiden", "supplied_chars"), "ᚐ + ᚑᚔ read through, counted"
  end

  # --- primary metadata (I-MAY-010) -------------------------------------------

  def test_i_may_010_primary_metadata_place_dil_and_translation
    metadata = parse("I-MAY", "I-MAY-010", layer: "ogham", urn: "urn:nabu:ogham:i-may-010",
                                           primary: true).metadata
    assert_equal "ogham", metadata["layer"]
    assert_equal %w[https://dil.ie/12667 https://dil.ie/18492], metadata["related"],
                 "the commentary's word-level eDIL links, normalized into dil.ie's stable id space"
    assert_equal "Co. Mayo", metadata.dig("place", "county")
    assert_equal ["https://www.logainm.ie/ga/34677"], metadata.dig("place", "logainm")
    assert_equal "54.089953, -9.027587", metadata.dig("place", "geo")
    assert_equal "KILGA/1", metadata["cisp"]
    assert_match(/of Dothán/, metadata["translation_en"])
    assert_equal "Pillar", metadata.dig("facets", "object_type", "value")
    assert_equal "Commemorative", metadata.dig("facets", "genre", "value")
  end

  def test_sibling_layer_metadata_stays_lean
    metadata = parse("I-MAY", "I-MAY-010", layer: "transliteration",
                                           urn: "urn:nabu:ogham:i-may-010-translit").metadata
    assert_equal({ "layer" => "transliteration" }, metadata)
  end

  # --- layer census (P25-3 hotfix: discovery shares the parser's extraction) --

  def census(region, id, glyph_table: glyphs)
    Nabu::Adapters::OghamEpidocParser.new.layer_census(
      File.join(FIXTURES, "XML", region, "#{id}.xml"), glyphs: glyph_table
    )
  end

  def test_layer_census_separates_citable_from_declared_but_empty_layers
    sts = census("E-STS", "E-STS-001")
    assert_empty sts.citable, "both declared layers carry only <ab><lb n=\"1\"/></ab> — no citable text"
    assert_equal %w[ogham transliteration], sts.empty
    assert_empty sts.unknown

    may = census("I-MAY", "I-MAY-010")
    assert_equal %w[ogham transliteration], may.citable, "first-appearance order"
    assert_empty may.empty
  end

  def test_layer_census_does_not_see_commented_out_edition_divs
    x01 = census("E-CON", "E-CON-X01")
    assert_empty x01.citable
    assert_empty x01.empty, "E-CON-X01's edition divs live inside <!-- --> — not declared at all"
    assert_empty x01.unknown
  end

  # A structurally broken layer (unresolvable glyph here; the W-PEM lb
  # defects upstream) stays CITABLE in the census: the ref must mint so the
  # parse can quarantine it honestly — only clean emptiness skips.
  def test_layer_census_keeps_structurally_broken_layers_citable
    she = census("S-SHE", "S-SHE-001", glyph_table: {})
    assert_equal %w[ogham transliteration], she.citable,
                 "glyph refs cannot resolve without charDecl — broken, not empty; mint and quarantine"
  end

  # --- metadata-only stones (P25-3 hotfix) ------------------------------------

  def test_parse_metadata_only_mints_a_zero_passage_stone_document
    document = Nabu::Adapters::OghamEpidocParser.new.parse_metadata_only(
      File.join(FIXTURES, "XML", "E-CON", "E-CON-X01.xml"), urn: "urn:nabu:ogham:e-con-x01"
    )
    assert_predicate document, :empty?
    assert_equal "none", document.metadata["text_layer"]
    assert_equal "und", document.language
    assert_equal "Lewannick 3", document.title
    assert_equal "Cornwall", document.metadata.dig("place", "county")
    assert_nil document.metadata["layer"], "no layer minted — the stone grain, not a layer document"
  end

  def test_parse_metadata_only_urn_mismatch_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::OghamEpidocParser.new.parse_metadata_only(
        File.join(FIXTURES, "XML", "E-CON", "E-CON-X01.xml"), urn: "urn:nabu:ogham:wrong"
      )
    end
    assert_match(/urn mismatch/, error.message)
  end
end
