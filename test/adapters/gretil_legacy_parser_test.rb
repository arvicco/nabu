# frozen_string_literal: true

require "test_helper"

# Parser family "gretil-legacy": GRETIL's pre-TEI e-texts (the per-language
# download zips' *.htm files) — a header block (title, edition, input
# credit), GRETIL's standard notice + transliteration legend between two
# <hr>s, then the text as <BR>-broken physical lines. Exercised on the
# trimmed-real fixtures of test/fixtures/gretil-legacy/.
class GretilLegacyParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("gretil-legacy")
  P = Nabu::Adapters::GretilLegacyParser

  def bytes(rel) = File.binread(File.join(FIXTURES, rel))

  def etext(rel) = P.etext(bytes(rel), path: rel)

  def dasaveyu = etext("2_prakrt/2_prakrt/dasaveyu.htm")

  def test_the_title_element_is_read_verbatim
    assert_equal "Dasaveyaliya", dasaveyu.title
    assert_equal "Hala: Sattasai", etext("2_prakrt/2_prakrt/halsatsu.htm").title
  end

  def test_the_header_block_rides_as_tag_stripped_lines
    assert_equal ["Dasaveyaliya", "Input by Yumi Ousaka and Moriichi Yamazaki"], dasaveyu.header
  end

  def test_the_gretil_notice_is_recorded_verbatim
    assert_equal ["THIS GRETIL TEXT FILE IS FOR REFERENCE PURPOSES ONLY!",
                  "COPYRIGHT AND TERMS OF USAGE AS FOR SOURCE FILE."], dasaveyu.notice
  end

  def test_the_body_opens_after_the_notice_block_and_keeps_physical_lines
    lines = dasaveyu.lines
    assert_equal "1 prathamamadhyayanam (dumapupphiyā.) /", lines[0]
    assert_equal "dhammo maṅgalamukkaṭhaṃ | ahiṃsā saṃjamo tavo /", lines[1]
    assert_equal "devā vi taṃ namaṃsanti | jassa dhamme sayā maṇo ||1||", lines[2]
    refute(lines.any? { |line| line.include?("retroflex") }, "the transliteration legend is GRETIL's, not the work")
    refute(lines.any? { |line| line.include?("REFERENCE PURPOSES") })
  end

  def test_lines_are_whitespace_collapsed_nfc
    line = dasaveyu.lines.find { |l| l.start_with?("samāe pehāe") }
    assert_equal "samāe pehāe parivvayanto | siyā maṇo nissaraī bahiddhā, /", line,
                 "the leading indentation is layout, collapsed"
    dasaveyu.lines.each { |l| assert l.unicode_normalized?(:nfc) }
  end

  def test_a_line_without_letters_or_digits_is_dropped_and_counted
    kutmir = etext("3_nia/marathi/kutmir_u.htm")
    refute(kutmir.lines.any? { |line| line.match?(/\A[^\p{L}\p{N}]+\z/) })
    assert_operator kutmir.dropped, :>=, 0
  end

  def test_a_file_without_the_gretil_notice_is_a_parse_error
    stripped = bytes("2_prakrt/2_prakrt/dasaveyu.htm").sub("REFERENCE PURPOSES ONLY", "REFERENCE ONLY")
    error = assert_raises(Nabu::ParseError) { P.etext(stripped, path: "dasaveyu.htm") }
    assert_match(/GRETIL notice/, error.message)
  end

  def test_invalid_utf8_is_a_parse_error
    broken = bytes("2_prakrt/2_prakrt/dasaveyu.htm") + "\xFF".b
    assert_raises(Nabu::ParseError) { P.etext(broken, path: "dasaveyu.htm") }
  end

  # The edition statement: the header's "Based on …" line with its
  # continuation lines, stopping at the input credit or a bracketed /
  # capitalized / ruled block.
  def test_edition_joins_the_based_on_continuation_lines
    assert_equal "Based on the edition by Albrecht Weber: Das Saptaçatakam des Hâla, Leipzig : " \
                 "Brockhaus 1881 (Abhandlungen für die Kunde des Morgenlandes ; 7,4).",
                 P.edition(etext("2_prakrt/2_prakrt/halsatsu.htm").header)
    assert_equal "Based on the edition by D.F. Plukker: The Miragaavatii of Kutubana, Avadhii text " \
                 "with critical notes (thesis Amsterdam, 1981)",
                 P.edition(etext("3_nia/marathi/kutmir_u.htm").header)
    assert_nil P.edition(dasaveyu.header), "no edition line, no edition"
  end

  def test_input_credits_are_the_input_lines
    assert_equal ["Input by Yumi Ousaka and Moriichi Yamazaki"], P.input_credits(dasaveyu.header)
  end
end
