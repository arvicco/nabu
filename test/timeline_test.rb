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

  # -- normalize_interval: the reversed-bounds repair ladder (P59-0) --------
  # Every case below is a REAL censused row from the 2026-08-04 reversed-
  # interval audit (82 document_axes rows across six sources). The ladder:
  # a coherent interval passes through; a reversed one is repaired by
  # era-signal-guarded negation (unsigned BCE bounds are the commonest
  # upstream defect) or, failing that, by order-normalization (swap) —
  # never returned reversed, never guessed beyond upstream's own claim.

  def norm(before, after, raw: nil, bce_default: false)
    Nabu::Timeline.normalize_interval(before, after, raw: raw, bce_default: bce_default)
  end

  def test_normalize_interval_passes_coherent_and_partial_bounds_through
    assert_equal [-500, -475], norm(-500, -475)
    assert_equal [300, 700], norm(300, 700, raw: "300 CE - 700 CE")
    assert_equal [nil, 450], norm(nil, 450)
    assert_equal [-27, nil], norm(-27, nil)
    assert_equal [nil, nil], norm(nil, nil)
    assert_equal [-27, -27], norm(-27, -27), "a point date is coherent"
  end

  def test_normalize_interval_negates_unsigned_bce_bounds_on_a_bce_signal
    # iip masa0797 "27-26 BCE" (notBefore="0027" notAfter="0026")
    assert_equal [-27, -26], norm(27, 26, raw: "27-26 BCE")
    # iip mare0095 "Fifth century BCE to second century BCE" ("0400"/"0100")
    assert_equal [-400, -100], norm(400, 100, raw: "Fifth century BCE to second century BCE")
    # isicily ISic001206 "3rd century BCE?" (custom "0301"/"0200")
    assert_equal [-301, -200], norm(301, 200, raw: "3rd century BCE?")
    # elephantine 307713 "499-475 v. Chr."
    assert_equal [-499, -475], norm(499, 475, raw: "499-475 v. Chr.")
  end

  def test_normalize_interval_negates_only_the_unsigned_bound_when_half_signed
    # elephantine 100467: nested notBefore="664" notAfter="-332" — the Late
    # Period (664-332 BCE) with the sign dropped on one bound upstream.
    assert_equal [-664, -332], norm(664, -332, raw: nil, bce_default: true)
    # elephantine 307271: "227"/"-227" — a point year, half-signed.
    assert_equal [-227, -227], norm(227, -227, raw: nil, bce_default: true)
  end

  def test_normalize_interval_bce_default_covers_signal_less_raws
    # elephantine 311616-311630 (custom "550"/"399", raw "scholarly
    # deduction") and 100772-ff (nested "525"/"475", empty raw): the corpus
    # prior says unsigned-descending reads BCE.
    assert_equal [-550, -399], norm(550, 399, raw: "scholarly deduction", bce_default: true)
    assert_equal [-525, -475], norm(525, 475, raw: nil, bce_default: true)
  end

  def test_normalize_interval_bce_default_yields_to_an_explicit_ce_signal
    # A CE-signalled raw must never be negated even under the BCE prior.
    assert_equal [901, 1100], norm(1100, 901, raw: "between 901 and 1100 C.E.", bce_default: true)
  end

  def test_normalize_interval_swaps_signed_but_reversed_bounds
    # edr aEDR074026 "-79 BC - -81 BC"; edr "70 AD - -31 AD"
    assert_equal [-81, -79], norm(-79, -81, raw: "-79 BC - -81 BC")
    assert_equal [-31, 70], norm(70, -31, raw: "70 AD - -31 AD")
    # iip idum0488 "August 1, 357 BCE" (-0357/-0358): both signed — the BCE
    # signal never re-negates a signed bound; order-normalize only.
    assert_equal [-358, -357], norm(-357, -358, raw: "August 1, 357 BCE")
    # iip odob0033 "Early Roman" (-0063/-0132)
    assert_equal [-132, -63], norm(-63, -132, raw: "Early Roman")
  end

  def test_normalize_interval_swaps_unsigned_ce_reversals
    # iip zoor0395 "354/355 CE" ("0355"/"0354")
    assert_equal [354, 355], norm(355, 354, raw: "354/355 CE")
    # coptic-scriptorium "between 951 and 1050" (no era signal, no BCE prior)
    assert_equal [951, 1050], norm(1050, 951, raw: "between 951 and 1050")
    # bfm "entre 1170 et 1267 et même après 1190 et av. 1204" — the bare
    # French "av." is NOT a BCE signal (that would be "av. J.-C.").
    assert_equal [1197, 1204], norm(1204, 1197, raw: "entre 1170 et 1267 et même après 1190 et av. 1204")
  end

  def test_normalize_interval_orders_after_negation_if_still_reversed
    assert_equal [-200, -100], norm(100, -200, raw: nil, bce_default: true)
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
