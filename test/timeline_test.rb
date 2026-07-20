# frozen_string_literal: true

require "test_helper"

# The date model (P15-2). These pin the fable-reviewed arithmetic: signed
# HISTORICAL years (no year 0), the era-boundary century math, and the reviewer's
# boundary table (101 BCE / 100 BCE / 1 BCE / 1 CE / 100 CE / 101 CE).
class TimelineTest < Minitest::Test
  # -- parse_year: base-10, sign-aware, rejects year 0 ----------------------

  def test_parses_bce_when_attribute_verbatim
    # HGV when="-0113" is labelled "113 v.Chr." — historical, no astronomical
    # shift, so it is exactly -113.
    assert_equal(-113, Nabu::Timeline.parse_year("-0113-08-26"))
    assert_equal(-88, Nabu::Timeline.parse_year("-0088-01-02"))
  end

  def test_parses_zero_padded_ce_year_as_base_ten_not_octal
    # Integer("0700") is OCTAL 448 in Ruby; the model must read decimal 700.
    assert_equal 700, Nabu::Timeline.parse_year("0700")
    assert_equal 90, Nabu::Timeline.parse_year("0090") # Integer("0090") would raise
    assert_equal 602, Nabu::Timeline.parse_year("0602")
  end

  def test_returns_nil_for_unparseable_or_blank
    assert_nil Nabu::Timeline.parse_year(nil)
    assert_nil Nabu::Timeline.parse_year("unbekannt")
    assert_nil Nabu::Timeline.parse_year("")
  end

  def test_rejects_literal_year_zero
    assert_raises(Nabu::Timeline::InvalidYear) { Nabu::Timeline.parse_year("0000") }
    assert_raises(Nabu::Timeline::InvalidYear) { Nabu::Timeline.parse_year("-0000") }
  end

  # -- century_index: the reviewed boundary table ---------------------------

  def test_century_index_boundary_table
    {
      -101 => -2, # 2nd c. BCE (200–101)
      -100 => -1, # 1st c. BCE (100–1)
      -1 => -1,   # 1st c. BCE
      1 => 1,     # 1st c. CE (1–100)
      100 => 1,   # 1st c. CE
      101 => 2,   # 2nd c. CE
      -113 => -2, # 113 BCE → 2nd c. BCE
      501 => 6,   # 6th c. CE
      602 => 7    # 601–700 is the 7th c. CE
    }.each do |year, index|
      assert_equal index, Nabu::Timeline.century_index(year), "#{year} → #{index}"
    end
  end

  def test_century_index_rejects_year_zero
    assert_raises(Nabu::Timeline::InvalidYear) { Nabu::Timeline.century_index(0) }
  end

  def test_century_index_ascending_is_chronological
    years = [-113, -30, 14, 501, 602]
    indices = years.map { |y| Nabu::Timeline.century_index(y) }
    assert_equal indices, indices.sort, "signed century index sorts chronologically"
    assert_equal [-2, -1, 1, 6, 7], indices
  end

  # -- labels, bounds, spans ------------------------------------------------

  def test_century_label
    assert_equal "2nd c. BCE", Nabu::Timeline.century_label(-2)
    assert_equal "1st c. BCE", Nabu::Timeline.century_label(-1)
    assert_equal "1st c. CE", Nabu::Timeline.century_label(1)
    assert_equal "21st c. CE", Nabu::Timeline.century_label(21)
  end

  def test_century_bounds_round_trips_with_index
    assert_equal [501, 600], Nabu::Timeline.century_bounds(6)
    assert_equal [-200, -101], Nabu::Timeline.century_bounds(-2)
    assert_equal [1, 100], Nabu::Timeline.century_bounds(1)
    assert_equal [-100, -1], Nabu::Timeline.century_bounds(-1)
    # Every year in a century's bounds maps back to that century.
    [-2, -1, 1, 6].each do |idx|
      from, to = Nabu::Timeline.century_bounds(idx)
      assert_equal idx, Nabu::Timeline.century_index(from)
      assert_equal idx, Nabu::Timeline.century_index(to)
    end
  end

  # -- am_to_ce: Byzantine anno mundi → CE span (P16-3, chronicle annals) ----

  def test_am_to_ce_spans_the_year_style_ambiguity
    # AM 6360 = 851/852 CE: a September-style AM year runs 1 Sep (AM−5509) –
    # 31 Aug (AM−5508), so a bare annal year is honestly a two-year span,
    # never a picked point.
    assert_equal [851, 852], Nabu::Timeline.am_to_ce(6360)
    assert_equal [1015, 1016], Nabu::Timeline.am_to_ce(6524)
  end

  def test_am_to_ce_envelopes_a_range_of_annal_years
    # A chronicle div titled "6369–6370" covers both AM years.
    assert_equal [860, 862], Nabu::Timeline.am_to_ce(6369, 6370)
  end

  def test_am_to_ce_never_emits_year_zero
    # The epoch years cross the 1 BCE / 1 CE boundary: AM 5509 spans them
    # (historical numbering, no year 0 — the P15-2 invariant holds here too).
    assert_equal [-1, 1], Nabu::Timeline.am_to_ce(5509)
    assert_equal [-2, -1], Nabu::Timeline.am_to_ce(5508)
    assert_equal [1, 2], Nabu::Timeline.am_to_ce(5510)
  end

  def test_format_span
    assert_equal "113 BCE", Nabu::Timeline.format_span(-113, -113)
    assert_equal "501–700 CE", Nabu::Timeline.format_span(501, 700)
    assert_equal "200–101 BCE", Nabu::Timeline.format_span(-200, -101)
    assert_equal "30 BCE – 14 CE", Nabu::Timeline.format_span(-30, 14)
    assert_equal "≤ 257 BCE", Nabu::Timeline.format_span(nil, -257)
    assert_equal "≥ 501 CE", Nabu::Timeline.format_span(501, nil)
    assert_nil Nabu::Timeline.format_span(nil, nil)
  end
end
