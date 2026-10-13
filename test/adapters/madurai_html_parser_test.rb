# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::MaduraiHtmlParser (P122-3) — the madurai-html family:
# Project Madurai's hand-made Unicode HTML e-texts and its works list.
# Runs against the real local fixtures (local/fixtures/madurai — see
# test/adapters/madurai_test.rb for why they are not public).
class MaduraiHtmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.local_fixtures("madurai")
  PARSER = Nabu::Adapters::MaduraiHtmlParser

  def require_fixtures!
    skip "local/fixtures/madurai absent (Project Madurai bytes stay out of the public repo)" unless
      Nabu::TestSupport.local_fixtures?("madurai")
  end

  def etext_bytes(stem)
    require_fixtures!
    File.binread(File.join(FIXTURES, "pm_etexts", "utf8", "#{stem}.html"))
  end

  def etext(stem) = PARSER.etext(etext_bytes(stem), path: "#{stem}.html")

  def test_the_header_page_is_cut_off_and_kept_verbatim
    text = etext("pmuni0047")
    assert_match(/You are welcome to freely distribute this file, provided this header page is kept intact\./,
                 text.header, "the license condition travels with the document")
    assert_match(/Project Madurai/, text.header)
    refute(text.lines.any? { |line| line.text.include?("Project Madurai") }, "no header line leaks into the work")
  end

  def test_the_footer_after_the_last_rule_is_cut_when_it_holds_no_tamil
    text = etext("pmuni0047")
    assert_match(/last revised on 3 August 2021/, text.footer)
    assert_equal "நான்மணிக்கடிகை முற்றிற்று.", text.lines.last.text
  end

  def test_physical_lines_are_the_grain_with_headings_marked
    text = etext("pmuni0047")
    assert_equal 431, text.lines.size
    first = text.lines.first
    assert_equal "விளம்பிநாகனாரின் நான்மணிக்கடிகை", first.text
    assert first.heading, "keyed inside <h3>"
    assert_equal "மதிமன்னு மாயவன் வாள்முகம் ஒக்கும்", text.lines[2].text
    refute text.lines[2].heading
    assert_equal "வீவிலா வீடாய் விடும். 106", text.lines[-2].text, "trailing verse numbers stay verbatim"
  end

  def test_the_html_title_rides
    assert_equal "nAnmaNikkaTikai of viLampi nAkanAr (in tamil script, unicode format)",
                 etext("pmuni0047").html_title
  end

  def test_a_file_without_the_distribution_sentence_is_a_parse_error
    bytes = etext_bytes("pmuni0047").force_encoding(Encoding::UTF_8)
                                    .sub("provided this header page is kept intact", "")
    error = assert_raises(Nabu::ParseError) { PARSER.etext(bytes, path: "pmuni0047.html") }
    assert_match(/no Project Madurai header page/, error.message)
  end

  def test_invalid_utf8_is_a_parse_error
    assert_raises(Nabu::ParseError) { PARSER.etext("\xFF\xFE<html>".b, path: "x.html") }
  end

  def test_lines_without_tamil_script_are_counted_not_kept
    html = "<html><body>header. You are welcome to freely distribute this file, provided this " \
           "header page is kept intact.<hr>அகர முதல<br>An English note<br>12345<br>" \
           "<hr>last revised 2021</body></html>"
    text = PARSER.etext(html.b, path: "x.html")
    assert_equal ["அகர முதல"], text.lines.map(&:text)
    assert_equal 1, text.non_tamil_lines, "digit-only lines are no letters; the English note is counted"
    assert_equal "last revised 2021", text.footer
  end

  def test_an_internal_rule_followed_by_tamil_never_cuts_text
    html = "<body>x. You are welcome to freely distribute this file, provided this header page " \
           "is kept intact.<hr>முதல் பகுதி<hr>இரண்டாம் பகுதி</body>"
    text = PARSER.etext(html.b, path: "x.html")
    assert_equal ["முதல் பகுதி", "இரண்டாம் பகுதி"], text.lines.map(&:text)
    assert_equal "", text.footer
  end

  def test_the_catalog_groups_rows_by_unicode_file
    require_fixtures!
    entries = PARSER.catalog(File.binread(File.join(FIXTURES, "pmworks.html"))).to_h { |e| [e.file, e] }
    auvaiyar = entries.fetch("pmuni0002.html")
    assert_equal %w[2], auvaiyar.work_numbers
    assert_equal ["ஆத்திசூடி", "கொன்றை வேந்தன்", "நல்வழி", "மூதுரை"], auvaiyar.titles
    assert_equal ["ஒளவையார்"], auvaiyar.authors
    assert_equal ["நீதிநெறி நூல்கள்"], auvaiyar.genres
    tiruvacakam = entries.fetch("pmuni0003_02.html")
    assert_equal ["திருவாசகம் - 1 (1-10)", "திருவாசகம் - 2 (11-51)"], tiruvacakam.titles,
                 "a multi-part work lists every row on every part (upstream's own linking)"
    dirt = entries.fetch("pmuni0660.html")
    assert_equal %w[660 662], dirt.work_numbers, "upstream's catalog links work 662's row to 0660's file"
    assert_equal ["பிரபந்தம் - தூது", "கவிதைகள்"], dirt.genres
  end
end
