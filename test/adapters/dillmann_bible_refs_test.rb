# frozen_string_literal: true

require "test_helper"

# The Dillmann → Bible crosswalk (P123-1), pinned on the real fixture
# entries: ሞተ (mori, n=1472 — 51 scripture references) and ዐፅም (os).
class DillmannBibleRefsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("dillmann")
  MOTA = File.join(FIXTURES, "1", "L2d417be91261494990015aae6b9b5d81.xml")
  ASM = File.join(FIXTURES, "1", "L3c8821a46d56420283fc3bdedc1c341a.xml")

  def citations(path)
    entry = Nokogiri::XML(File.read(path)).at_xpath("//*[local-name()='entry']")
    Nabu::Adapters::DillmannBibleRefs.citations(entry)
  end

  def by_label(path)
    citations(path).to_h { |c| [c.label, [c.cts_work, c.citation]] }
  end

  def test_held_geez_book_resolves_chapter_verse
    assert_equal ["urn:nabu:betamasaheft-works:LIT2709Matthew", "9.24"], by_label(MOTA)["Matth. 9,24"]
    assert_equal ["urn:nabu:betamasaheft-works:LIT2229RuthBo", "1.8"], by_label(MOTA)["Ruth 1,8"]
  end

  def test_nt_book_not_held_in_geez_resolves_onto_the_hub_sblgnt_column
    assert_equal ["urn:nabu:sblgnt:rom", "6.2"], by_label(MOTA)["Rom. 6,2"]
  end

  def test_single_chapter_book_cites_its_verse_in_chapter_one
    assert_equal ["urn:nabu:sblgnt:jude", "1.12"], by_label(MOTA)["Judae 12."]
  end

  def test_versification_divergent_books_resolve_only_to_the_book
    assert_equal ["urn:nabu:betamasaheft-works:LIT1688Job", nil], by_label(MOTA)["Job 2,9"]
    assert_equal ["urn:nabu:betamasaheft-works:LIT1685Bookof", nil], by_label(ASM)["Jer. 23,9"]
  end

  def test_chapter_only_reference_is_document_grain
    assert_equal ["urn:nabu:betamasaheft-works:LIT1697Jubilees", nil], by_label(MOTA)["Kuf. 2"]
  end

  def test_unheld_and_refuted_sigla_carry_verbatim
    by = by_label(MOTA)
    assert_equal [nil, nil], by["4 Esr. 7,12"], "the held Apocalypse of Ezra was refuted by the census"
    assert_equal [nil, nil], by["Kedr f. 73."]
    assert_equal [nil, nil], by["Cor. 15,54"], "a split '1 <ref>Cor.' siglum is not guessed"
  end

  def test_labels_collapse_whitespace_and_every_reference_mints_a_row
    all = citations(MOTA)
    labels = all.map(&:label)
    assert_includes labels, "Luc. 23,15", "upstream 'Luc.  23,15' collapses"
    assert_equal 51, all.size
    assert(all.all? { |c| c.urn_raw == c.label })
  end
end
