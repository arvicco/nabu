# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::StatutesRealmDating: the act title's reign + session label
# (BHO's "Charles II, 1664 & 1665: …" heading) → a typed CE envelope, and
# the Rot. Parl. regnal citation vol. 7's titles carry ("[Chapter VI. Rot.
# Parl. 12 § 13 Gul. III. …]") → its own regnal-year envelope, the two
# combined. Every title string below is a real BHO TOC title (census
# 2026-11-05 over all 723 TOC rows of vols 5–7).
class StatutesRealmDatingTest < Minitest::Test
  D = Nabu::Adapters::StatutesRealmDating

  # --- the heading ----------------------------------------------------------

  def test_heading_splits_reign_session_and_title
    heading = D.heading("Charles II, 1664 & 1665: An Act for the returning of able and sufficient Jurors.")
    assert_equal "Charles II", heading.reign
    assert_equal "1664 & 1665", heading.session
    assert_equal "An Act for the returning of able and sufficient Jurors.", heading.rest
  end

  def test_heading_reads_every_reign_spelling_upstream_uses
    {
      "Charles I, 1625: An Acte for punishing of divers abuses" => ["Charles I", "1625"],
      "James the Second, 1685: An Act to Attaint James Duke of Monmouth" => ["James the Second", "1685"],
      "William and Mary, 1688: An Act declareing the Rights and Liberties" => ["William and Mary", "1688"],
      "William III, 1695-6: An Act for remedying the Ill State of the Coin" => ["William III", "1695-6"],
      # the colon upstream dropped on one vol. 7 row, and the one with no space after it
      "William III, 1700 & 1701 An Act for granting to His Majesty several Duties" => ["William III", "1700 & 1701"],
      "William III, 1698-9:An Act to repeale an Act" => ["William III", "1698-9"]
    }.each do |title, (reign, session)|
      heading = D.heading(title)
      refute_nil heading, title
      assert_equal [reign, session], [heading.reign, heading.session], title
    end
  end

  def test_non_act_titles_have_no_heading
    ["Index: A", "Preface", "Engraving: Petition of Right, 3 Charles I",
     "Chronological table of the titles of all the acts of parliament passed in the reign of King William III"]
      .each { |title| assert_nil D.heading(title), title }
  end

  # --- the session label ----------------------------------------------------

  def test_session_years_expand_every_label_shape
    assert_equal [1625, 1625], D.session_years("1625")
    assert_equal [1664, 1665], D.session_years("1664 & 1665")
    assert_equal [1695, 1696], D.session_years("1695-6")
    assert_equal [1698, 1699], D.session_years("1698-9")
    assert_equal [1700, 1701], D.session_years("1700 & 1701")
  end

  def test_a_single_year_label_straddles_the_old_style_legal_year
    # 3 Car. I: the session opened 17 March 1627/8 (Old Style 1627) and the
    # Petition of Right passed in June 1628 — the label names the legal year.
    assert_equal [1627, 1628], D.label_envelope(reign: "Charles I", session: "1627")
    assert_equal [1661, 1662], D.label_envelope(reign: "Charles II", session: "1661")
  end

  def test_a_paired_label_already_names_both_calendar_years
    assert_equal [1664, 1665], D.label_envelope(reign: "Charles II", session: "1664 & 1665")
    assert_equal [1695, 1696], D.label_envelope(reign: "William III", session: "1695-6")
  end

  def test_the_long_parliament_session_runs_into_its_third_year
    # 16 Car. I: one session from 3 November 1640; royal assents ran into 1642.
    assert_equal [1640, 1642], D.label_envelope(reign: "Charles I", session: "1640")
  end

  def test_no_session_precedes_the_accession
    # 1 W. & M.: the Convention of February 1689 (Old Style 1688).
    assert_equal [1689, 1689], D.label_envelope(reign: "William and Mary", session: "1688")
  end

  def test_a_label_outside_the_reign_is_an_error
    assert_raises(ArgumentError) { D.label_envelope(reign: "James the Second", session: "1695") }
    assert_raises(ArgumentError) { D.label_envelope(reign: "Charles I", session: "1660") }
  end

  def test_an_unknown_reign_is_an_error
    assert_raises(ArgumentError) { D.label_envelope(reign: "Anne", session: "1705") }
  end

  # --- the regnal citation ----------------------------------------------------

  def test_regnal_citations_read_through_the_rekeying_slips
    {
      "[Chapter I. Rot. Parl. 7 & 8 Gul. III. p. 1. n.1.]" => [7, 8],
      "[Chapter III. Rot. Parl. 7&8 Gul. III. pt. 1.nu.3.]" => [7, 8],
      "[Chapter XI. Rot. Parl. 11 Gul. III. p. 3. n. 11. 2.]" => [11, 11],
      "[Chapter V. Rot. Parl. 12 § 13 Gul. III. p. 1. n. 5.]" => [12, 13],
      "[Chapter XI. Rot. Parl. 12 £ 13 Gul. III. p. 3. n. I.]" => [12, 13],
      "[Chapter XI. Rot. Parl. 8c9 Gul.III.p.2.nu.5.]" => [8, 9]
    }.each do |title, years|
      regnal = D.regnal("William III, 1700 & 1701: An Act #{title}")
      assert_equal years, regnal["years"], title
    end
  end

  def test_regnal_years_of_william_iii_open_each_thirteenth_of_february
    # Regnal year N = 13 Feb (1688+N) – 12 Feb (1689+N); a session opened in
    # year N may give assent through the following year.
    regnal = D.regnal("William III, 1695-6: An Act … [Chapter I. Rot. Parl. 7 & 8 Gul. III. p. 1. n.1.]")
    assert_equal "7 & 8 Gul. III", regnal["citation"]
    assert_equal 1695, regnal["not_before"]
    assert_equal 1698, regnal["not_after"]
  end

  def test_titles_without_a_regnal_citation_carry_none
    assert_nil D.regnal("James the Second, 1685: An Act for setleing the Revenue [Chapter I. Rot. Parl. nu. 1.]")
    assert_nil D.regnal("Charles I, 1625: An Acte for punishing of divers abuses")
  end

  # --- the combined date --------------------------------------------------------

  def test_date_is_the_label_envelope_when_no_citation_rides
    date = D.date("Charles I, 1625: An Acte for punishing of divers abuses co[m]mitted on the Lords day called Sunday.")
    assert_equal({ "not_before" => 1625, "not_after" => 1626, "raw" => "Charles I, 1625" }, date)
  end

  def test_a_consistent_citation_keeps_the_label_envelope
    date = D.date("William III, 1700 & 1701: An Act for continuing the Acts therein mentioned for preventing " \
                  "Theft and Rapine upon the Northern Borders of England " \
                  "[Chapter VI. Rot. Parl. 12 § 13 Gul. III. p. 1. n. 6.]")
    assert_equal 1700, date["not_before"]
    assert_equal 1701, date["not_after"]
    assert_equal "William III, 1700 & 1701 · Rot. Parl. 12 § 13 Gul. III", date["raw"]
    refute date.key?("conflict")
  end

  def test_a_label_the_citation_contradicts_widens_to_both_claims
    # BHO heads 11 Will. III's session (16 Nov 1699 – 11 Apr 1700) "1698-9";
    # the roll citation says regnal year 11 (opened 13 Feb 1699). Neither
    # claim is picked: the envelope spans both, flagged.
    date = D.date("William III, 1698-9: An Act to repeale an Act...intituled An Act for rendring the Laws more " \
                  "effectuall [Chapter XI. Rot. Parl. 11 Gul. III. p. 3. n. 11. 2.]")
    assert_equal 1698, date["not_before"]
    assert_equal 1701, date["not_after"]
    assert_equal true, date["conflict"]
  end

  def test_the_misheaded_1698_9_label_reads_the_span_of_both_claims
    # 20 of the label's 25 rows cite 11 Gul. III (1699–1700); the uncited
    # rows (the private-acts schedule) keep BHO's claim AND the session's.
    assert_equal [1698, 1700], D.label_envelope(reign: "William III", session: "1698-9")
    date = D.date("William III, 1698-9: The Private Acts")
    assert_equal [1698, 1700], [date["not_before"], date["not_after"]]
  end

  def test_a_non_act_title_has_no_date
    assert_nil D.date("Index: A")
  end
end
