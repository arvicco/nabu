# frozen_string_literal: true

require "test_helper"

# The editorial/house-mark card (P85): `nabu char ⟦` answers with the mark's
# meaning IN THIS LIBRARY, read from config/editorial_marks.yml — the one card
# no external Unicode tool can supply. These tests pin the table's shape, the
# dispatch routing, and the agreement between the two (a mark added to one but
# not the other turns the suite red).
class EditorialMarksTest < Minitest::Test
  def test_marks_route_to_the_marks_lane
    %w[⟦ ⟧ ⌈ ⌉ ⬚ ⸀ ⸂ ⸃ ⿰ ⿱].each do |mark|
      assert_equal :marks, Nabu::CharDispatch.lane(mark), "#{mark} must route to the marks card"
    end
  end

  def test_a_non_mark_single_char_does_not_route_to_marks
    refute_equal :marks, Nabu::CharDispatch.lane("a")
    refute_equal :marks, Nabu::CharDispatch.lane("棄")
    refute_equal :marks, Nabu::CharDispatch.lane("Ω")
  end

  def test_the_dispatch_set_and_the_config_table_agree
    assert_equal Nabu::EditorialMarks.codepoints, Nabu::CharDispatch::MARKS,
                 "config/editorial_marks.yml and CharDispatch::MARKS must document the same marks — " \
                 "add the code point to both, or neither"
  end

  def test_lookup_returns_the_convention_card
    erasure = Nabu::EditorialMarks.lookup("⟦")
    refute_nil erasure
    assert_equal "U+27E6", erasure.codepoint
    assert_match(/erasure/i, erasure.name)
    assert_match(/kept as content/i, erasure.meaning)
    assert_match(/erasures:unwrap/, erasure.display_rule)
    refute_empty erasure.seen_in
  end

  def test_lookup_of_a_non_mark_is_nil
    assert_nil Nabu::EditorialMarks.lookup("a")
    assert_nil Nabu::EditorialMarks.lookup("棄")
  end

  def test_every_table_row_carries_the_card_fields
    Nabu::EditorialMarks.table.each do |glyph, row|
      %w[codepoint name meaning].each do |field|
        refute_nil row[field], "#{glyph}: editorial_marks.yml row must carry #{field}"
      end
      assert_match(/\AU\+[0-9A-F]{4,6}\z/, row["codepoint"], "#{glyph}: codepoint must be U+XXXX")
    end
  end
end
