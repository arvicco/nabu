# frozen_string_literal: true

require "test_helper"

# FreisingTeiParser tests (P13-11): the eZISS TEI P4 family. The fixture
# facts pinned here are the upstream quirks the fixtures document: the
# ZRCola charDesc glyph map (bs.xml), the mon→page→line skeleton shared by
# every layer, corr-over-sic / expan-over-abbr in the critical layer, scribal
# add/del kept in the diplomatic layer, dropped end-notes, the skipped empty
# line 36, and per-line @lang (the Latin tail of BS I).
class FreisingTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("freising")
  MASTER = File.join(FIXTURES, "tei", "bs.xml")

  def glyph_map
    @glyph_map ||= Nabu::Adapters::FreisingTeiParser.glyph_map(MASTER)
  end

  def parser
    Nabu::Adapters::FreisingTeiParser.new(glyph_map: glyph_map)
  end

  def monuments(layer)
    parser.monuments(File.join(FIXTURES, "tei", "#{layer}.xml"))
  end

  # --- the charDesc glyph map -------------------------------------------------

  def test_glyph_map_reads_standard_mappings_from_the_master_chardesc
    assert_equal "d", glyph_map.fetch("zrcolaE148"), "LATIN SMALL LETTER D ROTUNDA -> d (lossy)"
    assert_equal "ą̇", glyph_map.fetch("zrcolaE31B"),
                 "A WITH OGONEK AND DOT ABOVE -> base + combining (exact)"
    assert_equal "r̄", glyph_map.fetch("zrcolaEB07"), "R WITH MACRON -> r + combining macron"
    assert_equal 25, glyph_map.size, "the trimmed fixture charDesc carries 25 glyphs"
  end

  # --- skeleton: mon -> page -> line -------------------------------------------

  def test_critical_layer_yields_three_monuments_with_folio_and_line_numbers
    mons = monuments("bsCT")
    assert_equal [1, 2, 3], mons.map(&:n)
    first = mons[0].lines.first
    assert_equal 1, first.n
    assert_equal "78r", first.folio
    assert_equal "bsCT.1.001", first.tei_id
    assert_equal "GLAGOLITE PO NAZ REDKA ZLOUEZA:", first.text
  end

  def test_line_numbering_is_continuous_across_pages_and_skips_the_empty_line
    lines = monuments("bsCT")[0].lines
    assert_equal (1..39).to_a - [36], lines.map(&:n),
                 "BS I runs 78r (1-24) into 78v (25-39); the empty <line n=36/> yields no passage"
    assert_equal "78v", lines.find { |l| l.n == 25 }.folio
  end

  # --- editorial choices: the critical reading text ------------------------------

  def test_corr_is_preferred_over_sic
    line4 = monuments("bsCT")[0].lines.find { |l| l.n == 4 }
    assert_includes line4.text, "uzem crilatcem bosiem", "the editor's corr is the critical reading"
    refute_includes line4.text, "uuizem", "the sic form stays in canonical, not in the passage"
  end

  def test_expan_is_preferred_over_abbr
    line6 = monuments("bsCT")[0].lines.find { |l| l.n == 6 }
    assert line6.text.end_with?("devuam praudnim, i uzem"), "got: #{line6.text.inspect}"
    refute_includes line6.text, "Iúʒē", "the contraction stays in canonical"
  end

  def test_a_standalone_corr_is_kept
    line20 = monuments("bsCT")[0].lines.find { |l| l.n == 20 }
    assert_includes line20.text, "caco mi ie iega", "editorial insertion with no sic sibling"
  end

  def test_milestones_and_end_notes_leave_no_residue
    line2 = monuments("bsTR-slv")[0].lines.find { |l| l.n == 3 }
    refute_match(/Pod vplivom/, line2.text, "the end-note body is dropped")
  end

  # --- per-line language: the Latin tail of BS I ---------------------------------

  def test_line_lang_is_surfaced
    lines = monuments("bsCT")[0].lines
    assert_nil lines.find { |l| l.n == 1 }.lang
    latin = lines.find { |l| l.n == 37 }
    assert_equal "lat", latin.lang
    assert latin.text.start_with?("Confitentibus tibi Domine")
  end

  def test_abbr_with_glyph_content_resolves_via_the_expan
    line39 = monuments("bsCT")[0].lines.find { |l| l.n == 39 }
    assert_equal "reconciliationis tuæ gratia consolentur. Per.", line39.text
  end

  # --- glyph substitution + NFC (the encoding regression fixture) ----------------

  def test_diplomatic_glyph_refs_resolve_to_standard_unicode
    line = monuments("bsDT")[1].lines.first
    assert_equal "Eccȩ bi detd naſ neze", line.text,
                 "zrcolaE148 -> d in place; long ſ kept (canonical means canonical)"
    assert line.text.unicode_normalized?(:nfc), "parser output is NFC at the boundary"
  end

  def test_phonetic_layer_keeps_upstream_boundary_pipes_and_is_nfc
    line = monuments("bsPT")[0].lines.first
    assert_equal "głagɔlì:tɛ pɔ nás ræ:tká " \
                 "słɔwɛsá: ||", line.text
    assert line.text.unicode_normalized?(:nfc)
  end

  # The scribe's own corrections flatten to his FINAL state: <del> (erased
  # ink) dropped, <add> (superscript/inline correction) kept. Keeping both
  # would mint readings the parchment never carried ("potrae"); the erased
  # matter stays recoverable in canonical.
  def test_scribal_del_is_dropped_and_add_is_kept_in_the_diplomatic_witness
    line20 = monuments("bsDT")[0].lines.find { |l| l.n == 20 }
    assert_includes line20.text, "potre", "del a + add e -> the corrected potre(ba)"
    refute_includes line20.text, "potra"
    line9 = monuments("bsDT")[0].lines.find { |l| l.n == 9 }
    assert_includes line9.text, "naʒodni den", "erasure ne dropped, superscript ni kept"
  end

  # --- damage -------------------------------------------------------------------

  def test_an_unmapped_glyph_is_a_parse_error
    empty = Nabu::Adapters::FreisingTeiParser.new(glyph_map: {})
    error = assert_raises(Nabu::ParseError) do
      empty.monuments(File.join(FIXTURES, "tei", "bsDT.xml"))
    end
    assert_match(/zrcola/, error.message, "names the unmapped glyph id")
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.xml")
      File.write(path, "<div><line n='1'")
      assert_raises(Nabu::ParseError) { parser.monuments(path) }
    end
  end
end
