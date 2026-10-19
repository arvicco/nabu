# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::OpenmghCharterDate: the Diplomata dating line → year
# bounds + issuing place. Every input below is a REAL dating line from
# the held openMGH volumes (canonical/openmgh, census 2026-10-19 — 2,037
# dated charters: 1,915 bounded, 122 verbatim-only), one per shape the
# census shows.
class OpenmghCharterDateTest < Minitest::Test
  def read(raw) = Nabu::Adapters::OpenmghCharterDate.parse(raw)

  def assert_reads(raw, not_before, not_after, place)
    result = read(raw)
    refute_nil result, raw
    assert_equal [not_before, not_after, place], [result.not_before, result.not_after, result.place], raw
  end

  # -- date-first (DD Merov., DD F I., DD H VI., DD W.) ----------------------

  def test_the_editors_inferred_year_and_the_place_after_the_date
    assert_reads "(498) Dezember 29, Reims", 498, 498, "Reims"
    assert_reads "<645> Mai 11, Weißenburg", 645, 645, "Weißenburg"
    assert_reads "1162 Juli 24, Parma.", 1162, 1162, "Parma"
  end

  def test_a_bracketed_range_is_the_envelope
    assert_reads "[481 – 511 November 27], Ferrières", 481, 511, "Ferrières"
    assert_reads "[662 Oktober 18 -- 675 September 11], --", 662, 675, nil
    assert_reads "(1031 Ende – 1032 September 6).", 1031, 1032, nil
  end

  def test_split_years_bound_both
    assert_reads "(692/93) November 1, Luzarches", 692, 693, "Luzarches"
    assert_reads "703/4 Oktober 20, --", 703, 704, nil
  end

  def test_the_unknown_place_filler_claims_no_place
    assert_reads "[630, vor April 8], --", 630, 630, nil
    assert_reads "1252 Januar 25, –.", 1252, 1252, nil
  end

  def test_the_place_text_is_verbatim_past_the_last_date_segment
    assert_reads "1248 April 29, Kaiserswerth, im Lager.", 1248, 1248, "Kaiserswerth, im Lager"
    assert_reads "1159 (Ende Januar–Anfang Februar), im Gebiet von Vercelli.", 1159, 1159,
                 "im Gebiet von Vercelli"
    assert_reads "1248 (November 10 – Dezember 23) Kaiserswerth, im Lager.", 1248, 1248,
                 "Kaiserswerth, im Lager"
  end

  def test_an_inferred_place_loses_only_its_parentheses
    assert_reads "1162 April 29, (Pavia).", 1162, 1162, "Pavia"
    assert_reads "1161 (Juni, Lodi).", 1161, 1161, "Lodi"
    assert_reads "(1246 August 13, Frankfurt).", 1246, 1246, "Frankfurt"
    assert_reads "1189 Mai 28, Preßburg (Bratislava)", 1189, 1189, "Preßburg (Bratislava)"
  end

  # -- place-first (DD Lo I./Lo II., DD Arn, DD Rudolf., DD Ko. II.) ----------

  def test_place_first_lines
    assert_reads "Aachen 833 Dezember 9.", 833, 833, "Aachen"
    assert_reads "curte Aureola 822 Dezember 18.", 822, 822, "curte Aureola"
    assert_reads "Mattighofen <885> November 20.", 885, 885, "Mattighofen"
    assert_reads "Regensburg 890 — —.", 890, 890, "Regensburg"
    assert_reads "Pavia — 834 Juni 25.", 834, 834, "Pavia"
    assert_reads "Aix(-les-Bains) 1011 April 24.", 1011, 1011, "Aix(-les-Bains)"
  end

  def test_place_comma_lines
    assert_reads "Palermo, 1196 Januar", 1196, 1196, "Palermo"
    assert_reads "(Messina, 1212 vor Mitte März)", 1212, 1212, "Messina"
    assert_reads "–, 1205 März", 1205, 1205, nil
  end

  def test_a_line_naming_two_places_claims_neither
    assert_reads "Gray – 1178 September 13, Besançon.", 1178, 1178, nil
  end

  def test_a_date_word_prefix_is_not_a_place
    assert_reads "(nicht lange vor 1176 September 4).", nil, 1176, nil
  end

  # -- the envelope rules ------------------------------------------------------

  def test_alternatives_envelope_and_the_flagged_error_drops
    assert_reads "(1163 Februar oder 1165 Mai–Juni), Würzburg.", 1163, 1165, "Würzburg"
    assert_reads "1186 (irrig 1185), Oktober 5, Colmar.", 1186, 1186, "Colmar"
  end

  def test_a_lone_year_after_vor_or_nach_is_an_open_bound
    assert_reads "(vor 1162 August 1).", nil, 1162, nil
    assert_reads "(nach 1165 Mai 23).", 1165, nil, nil
    assert_reads "[nach 567 November 17 -- 584], --", 567, 584, nil
  end

  # -- verbatim-only (bounds never invented) -----------------------------------

  def test_hedged_lines_stay_verbatim_only
    ["(um 979).", "(wohl 852)", "Lausanne 896 (?) August 5.", "Vevey 1028 (1026?) April 16.",
     "1169 (etwa Oktober), Donauwörth.", "(1170 Juli 25 oder bald danach).",
     "(1174–1186 September, wahrscheinlich vor 1184)."].each do |raw|
      assert_nil read(raw), raw
    end
  end

  def test_implausible_or_garbled_years_stay_verbatim_only
    ["Messina, 119 (8 Januar)", "Aix(-les-Bains) 985186.", "(100911010).",
     "(zu Beginn des zweiten Italienzuges).", "", "Regensburg – –"].each do |raw|
      assert_nil read(raw), raw.inspect
    end
  end
end
