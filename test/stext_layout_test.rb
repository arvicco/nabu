# frozen_string_literal: true

require "test_helper"
require "zlib"
require "nabu/stext_layout"

# Nabu::StextLayout — mutool's structured-text XML read back as positioned,
# styled visual lines (the layout half of the Wilkens segmentation lane),
# pinned against the RECORDED stext of the real five-page fixture trim.
class StextLayoutTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("wilkens-oui")

  def pages
    @pages ||= Nabu::StextLayout.pages(Zlib.gunzip(File.binread(File.join(FIXTURES, "wilkens-sample.stext.xml.gz"))))
  end

  def line_starting(page, prefix)
    page.lines.find { |l| l.text.start_with?(prefix) } ||
      flunk("no line starting #{prefix.inspect} on folio #{page.folio}")
  end

  def test_every_page_comes_back_with_its_printed_folio
    assert_equal [1, 44, 45, 182, 441], pages.map(&:folio)
  end

  def test_lines_are_assigned_to_the_left_or_right_column
    p44 = pages[1]
    assert_equal :left, line_starting(p44, "amraklug").column
    assert_equal :right, line_starting(p44, "amranmak köŋül").column
  end

  def test_justified_word_fragments_merge_into_one_visual_line
    # mutool emits "amramaksız", "ohne", "Zuneigung", "||", "sevgi" as five
    # stext lines on one baseline; the reader rebuilds the printed line.
    assert_equal "amramaksız ohne Zuneigung || sevgi", line_starting(pages[1], "amramaksız").text.strip
  end

  def test_the_folio_line_is_not_part_of_the_text_flow
    refute(pages[1].lines.any? { |l| l.text.strip == "44" })
  end

  def test_lines_flow_left_column_top_to_bottom_then_right_column
    columns = pages[1].lines.map(&:column)
    assert_equal columns.sort_by { |c| c == :left ? 0 : 1 }, columns
    lefts = pages[1].lines.select { |l| l.column == :left }.map(&:y)
    assert_equal lefts.sort, lefts
  end

  def test_glyphs_carry_synthetic_bold_italic_and_subscript_size
    head = line_starting(pages[1], "amraklug")
    assert(head.glyphs.first(8).all?(&:bold), "Word's fill+stroke bold marks the headword")
    refute head.glyphs.last.bold
    sub = line_starting(pages[1], "amramak erinčkämäk")
    assert sub.glyphs.first.italic, "sub-entry phrases are set in Gentium-Italic"
    pair = line_starting(pages[1], "amrančıg ogšančıg")
    assert(pair.glyphs.any?(&:small), "the word-pair subscript (anmutig₂) is a small glyph")
  end

  def test_x0_records_the_indent_geometry
    p44 = pages[1]
    assert_in_delta 47.1, line_starting(p44, "amraklug").x0, 0.5
    assert_in_delta 58.8, line_starting(p44, "amramak erinčkämäk").x0, 0.5
  end
end
