# frozen_string_literal: true

require "test_helper"

# Nabu::AedTextHeaders: the one reader of the per-text AED stand-off
# headers (canonical/aed/files/<TLA-text-id>_hiero.xml) — title, the
# ruler/dynasty-anchored origDate with its numeric bounds, and the
# origPlace with its TLA thesaurus ref. Fixtures: the seven real header
# files of the AES fixture texts (test/fixtures/aes/aed/files, README).
class AedTextHeadersTest < Minitest::Test
  AED_ROOT = File.join(Nabu::TestSupport::FIXTURES_ROOT, "aes", "aed")

  def header(text_id)
    Nabu::AedTextHeaders.new(aed_dir: AED_ROOT).header(text_id)
  end

  def test_a_reign_dated_text_carries_title_bounds_and_site
    h = header("26BP5JT5RZEDHDDU2R5TMUBD24")
    assert_equal "pBerlin P 21002 verso (99 E)", h.title
    assert_equal(-2421, h.not_before)
    assert_equal(-2384, h.not_after)
    assert_equal "Djedkare Asosi", h.date_raw
    assert_equal "reign", h.precision
    assert_equal "Abusir", h.place_name
    assert_equal "ths:O5AYJCUXENDODEGUIMCH2YWXWM", h.place_ref
  end

  def test_dynasty_and_period_labels_get_their_own_grain
    dyn = header("3F5KUVWQG5EPBM7GMQ6ZFVO5OQ")
    assert_equal ["18. Dyn.", "dynasty", -1550, -1293], [dyn.date_raw, dyn.precision, dyn.not_before, dyn.not_after]
    ptol = header("5YVC3WZOGZHSBGXTIEM7ZUG2UA")
    assert_equal ["Makedonen, Ptolemäer", "period", -332, -31],
                 [ptol.date_raw, ptol.precision, ptol.not_before, ptol.not_after],
                 "zero-padded signed years read base-10, never octal"
  end

  def test_differing_earliest_and_latest_labels_join_and_take_the_coarser_grain
    h = header("2PD2OKCZCRELBGQD6NCAMOFEWA")
    assert_equal "19. Dyn. – 20. Dyn.", h.date_raw
    assert_equal "dynasty", h.precision
    assert_equal [-1292, -1071], [h.not_before, h.not_after]
    assert_equal "westliches Ufer", h.place_name, "a sub-site locality keeps its disambiguating ref"
    assert_equal "ths:VHGZGISIMJG6NBSUYALIZI4TIQ", h.place_ref
  end

  def test_placeholders_are_dropped_never_ingested
    h = header("IMLY3YQIZFHHNJUGOZXVPOJTGU")
    assert_nil h.title, "the editorial 〈TEXT〉 placeholder is not a title"
    assert_nil h.not_before, "the 0001/0001 placeholder bounds are not a dating"
    assert_nil h.not_after
    assert_nil h.date_raw
    assert_nil h.place_name, "the thesaurus root '3 = Fundstellen' is not a place"
    assert_nil h.place_ref
  end

  def test_bracketed_editorial_titles_stay_verbatim_nfc
    assert_equal "〈Stele des Nebanch (aus Abydos)〉", header("YSJ3UHIOBJEILCD7KFQIGVOCLY").title,
                 "U+2329/U+232A fold to U+3008/U+3009 at the boundary"
    assert_nil header("NS6BAIQRENELJM2A2LDNHIYK6E").title
  end

  def test_precision_classifier_over_the_censused_label_shapes
    classify = ->(label) { Nabu::AedTextHeaders.precision_of(label) }
    assert_equal "reign", classify.call("Pepi II.")
    assert_equal "reign", classify.call("Mentuhotep II. Nebhepetre (vor der Reichseinigung)")
    assert_equal "reign", classify.call("Thutmosis III. (Gesamtzeitraum)")
    assert_equal "dynasty", classify.call("13. / 14. Dynastie")
    assert_equal "dynasty", classify.call("11. Dyn. (Gesamtzeitraum)")
    assert_equal "period", classify.call("Altes Reich")
    assert_equal "period", classify.call("Zweite Zwischenzeit")
    assert_equal "period", classify.call("Herakleopolitenzeit (Gesamtzeitraum)")
    assert_equal "period", classify.call("römische Zeit")
    assert_equal "century", classify.call("1. Viertel 3. Jhdt. v.Chr.")
  end

  def test_absent_file_or_tree_is_nil
    assert_nil header("P4RDC6F54VCP3LYTR43CBQ6CMA")
    assert_nil Nabu::AedTextHeaders.new(aed_dir: File.join(Dir.tmpdir, "no-such-aed")).header("X")
  end
end
