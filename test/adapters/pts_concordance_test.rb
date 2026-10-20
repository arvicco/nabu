# frozen_string_literal: true

require "test_helper"

# The PTS page-citation fold for SuttaCentral's reference sidecars. Every
# token below is a real upstream reference string (censused against the held
# bilara-data tree); the expected keys are spelled in the notation CBETA's
# N canon already carries as its per-line "cref" annotation (PTS.S.3.1,
# PTS.Nidd.1.255, PTS.Ap.302 …), so the two corpora meet on identical
# strings.
class PtsConcordanceTest < Minitest::Test
  PC = Nabu::Adapters::PtsConcordance

  def test_book_dirs_map_to_pts_sigla
    assert_equal "S", PC.siglum(%w[sutta sn sn35])
    assert_equal "A", PC.siglum(%w[sutta an an4])
    assert_equal "Khp", PC.siglum(%w[sutta kn kp])
    assert_equal "Th", PC.siglum(%w[sutta kn thag])
    assert_equal "Thī", PC.siglum(%w[sutta kn thig])
    assert_equal "Nidd.1", PC.siglum(%w[sutta kn mnd]), "Mahāniddesa = PTS Nidd I"
    assert_equal "Nidd.2", PC.siglum(%w[sutta kn cnd]), "Cūḷaniddesa = PTS Nidd II"
    assert_equal "Ap", PC.siglum(%w[sutta kn tha-ap])
    assert_equal "Ap", PC.siglum(%w[sutta kn thi-ap])
    assert_equal "Dhs", PC.siglum(%w[abhidhamma ds])
    assert_equal "Vin", PC.siglum(%w[vinaya pli-tv-kd]), "the whole Vinaya is one PTS edition"
    assert_equal "Vin", PC.siglum(["vinaya"]), "a pātimokkha root sits at basket level"
  end

  def test_an_unknown_book_has_no_siglum
    assert_nil PC.siglum(%w[sutta kn xyz])
    assert_nil PC.siglum(%w[sutta sa sa101-200]), "the lzh Āgamas carry no PTS pages"
    assert_nil PC.siglum([])
  end

  def test_volume_page_tokens
    assert_equal "PTS.S.4.16", PC.key("pts-vp-pli4.16", siglum: "S")
    assert_equal "PTS.Ja.1.410", PC.key("pts-vp-pli1.410", siglum: "Ja")
    assert_equal "PTS.Vin.1.334-336", PC.key("pts-vp-pli1.334-336", siglum: "Vin"),
                 "the one censused page range stays a range"
  end

  def test_page_only_tokens_of_single_volume_books
    assert_equal "PTS.Khp.1", PC.key("pts-vp-pli1", siglum: "Khp")
    assert_equal "PTS.Nidd.1.210", PC.key("pts-vp-pli210", siglum: "Nidd.1")
  end

  def test_the_apadana_folds_its_continuously_paginated_volumes
    assert_equal "PTS.Ap.514", PC.key("pts-vp-pli2.514", siglum: "Ap"),
                 "Ap I runs pp. 1–338, Ap II pp. 339–615 (censused) — the page alone is the citation"
  end

  # CBETA N (the Nanden Daizōkyō pagination, 1935–41) follows the FIRST PTS
  # edition of every two-edition book — every second edition postdates it.
  # Checked page-for-page against the held trees: SN 6.12 body → S.1.154
  # and SN 6.14 → S.1.155 (ed2: 332/335); Dhp verses 100/200/300/400/423
  # → pp. 15/30/43/57/60 (ed2: 28/56/84/112/118); Bv and Cp chapter
  # breaks identical to ed1 (Cp pp. 73–103, ed2 pp. 1–37).
  def test_first_edition_tokens_fold_to_the_plain_cbeta_spelling
    assert_equal "PTS.S.1.154", PC.key("pts-vp-pli1ed1.154", siglum: "S")
    assert_equal "PTS.Dhp.51", PC.key("pts-vp-pli1ed51", siglum: "Dhp")
    assert_equal "PTS.Cp.73", PC.key("pts-vp-pli1ed73", siglum: "Cp")
  end

  def test_the_buddhavamsa_volume_number_is_dropped
    assert_equal "PTS.Bv.39", PC.key("pts-vp-pli1ed1.39", siglum: "Bv"),
                 "Bv is one volume in either edition; CBETA writes PTS.Bv.<page>"
    assert_equal "PTS-ed2.Bv.56", PC.key("pts-vp-pli2ed1.56", siglum: "Bv")
  end

  def test_second_edition_tokens_stay_edition_explicit
    assert_equal "PTS-ed2.S.1.69", PC.key("pts-vp-pli2ed1.69", siglum: "S")
    assert_equal "PTS-ed2.Pv.9", PC.key("pts-vp-pli2ed9", siglum: "Pv"),
                 "SuttaCentral carries only ed2 for Vv/Pv; CBETA N follows ed1 — no meeting, no fold"
    assert_equal "PTS-ed2.Dhp.28", PC.key("pts-vp-pli2ed28", siglum: "Dhp")
  end

  def test_non_page_and_unread_shapes_yield_nothing
    assert_nil PC.key("pts-vp-en3.426", siglum: "Vin"), "Horner's English translation, not a Pali page"
    assert_nil PC.key("pts-cs1.1", siglum: "D"), "PTS section numbering, not a page"
    assert_nil PC.key("pts-vp-pli1.1.1", siglum: "A"), "AN's three-part shape is not read (never guessed)"
    assert_nil PC.key("vri26.15", siglum: "S")
    assert_nil PC.key("pts-vp-pli4.16", siglum: nil), "no siglum, no key"
  end

  def test_split_reads_a_reference_string_into_pts_and_vri
    assert_equal({ "pts" => ["PTS.S.4.16"], "vri" => ["vri26.15"] },
                 PC.split("dr18.18, ms13S4_65, msdiv24, pts-vp-pli4.16, sya18.20, vri26.15", siglum: "S"))
    assert_equal({}, PC.split("ms12S1_249, msdiv44", siglum: "S"))
    assert_equal({ "pts" => ["PTS.S.1.33", "PTS-ed2.S.1.69"] },
                 PC.split("cck15.43, ms12S1_250, msdiv45, pts-vp-pli1ed1.33, pts-vp-pli2ed1.69", siglum: "S"))
  end
end
