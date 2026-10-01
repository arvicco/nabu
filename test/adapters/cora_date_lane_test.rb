# frozen_string_literal: true

require "test_helper"

# CoraDateLane: the CorA header dating grammar shared by the ReM (comma
# grid) and ReN (slash grid) sibling zips. Values are verbatim upstream
# header strings from the 2026-10-01 censuses.
class CoraDateLaneTest < Minitest::Test
  LANE = Nabu::Adapters::CoraDateLane

  def test_clean_dates_set_the_bounds
    assert_equal [1329, 1329], LANE.date_bounds("1329")
    assert_equal [1452, 1500], LANE.date_bounds("1452-1500")
    assert_equal [1057, 1065], LANE.date_bounds("1057/65")
    assert_nil LANE.date_bounds("41609"), "a five-digit value is no year"
    assert_nil LANE.date_bounds("um 1140/50 (?)")
  end

  def test_both_grid_spellings
    assert_equal [1200, 1250], LANE.grid_bounds("13,1", separator: ",")
    assert_equal [1150, 1250], LANE.grid_bounds("12,2-13,1", separator: ",")
    assert_equal [1100, 1200], LANE.grid_bounds("12", separator: ",")
    assert_equal [1300, 1350], LANE.grid_bounds("14/1", separator: "/")
    assert_equal [1400, 1500], LANE.grid_bounds("15/1-15/2", separator: "/")
    assert_nil LANE.grid_bounds("14/1", separator: ","), "the spelling is the source's own"
  end

  def test_envelope_raw_names_both_claims_only_on_fallback
    assert_equal({ "not_before" => 1172, "not_after" => 1172, "raw" => "1172" },
                 LANE.envelope("1172", "12,2", separator: ","))
    assert_equal({ "not_before" => 1000, "not_after" => 1100, "raw" => "11 (time 11)" },
                 LANE.envelope("11", "11", separator: ","))
    assert_equal({ "raw" => "(time 12,2; um 1200)" }, LANE.envelope(nil, "12,2; um 1200", separator: ","))
    assert_nil LANE.envelope(nil, nil, separator: ",")
  end
end
