# frozen_string_literal: true

require "test_helper"

# The calfa-etymology parser family: Calfa's working document of Ačaṙean's
# Hayerēn armatakan baṙaran (1926) — etymology/etymology01.xml, a flat
# <dictionary> of <entry> elements whose children are, in document order,
# <headword>, <content> (meaning + attestations), <egal> (the "= …"
# etymology), <indent_content> (earlier explanations), <ԳՒՌ> (dialect
# forms) and <ՓՈԽ> (loans from Armenian), with empty <other_pox/> and
# <indent/> page-break marks. The etymologies are PROSE (AI-processed,
# upstream says): no typed etymon relation exists to map onto the reflex
# store, so none is minted. Pins run on the real trimmed fixture.
class CalfaEtymologyParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("calfa-lexicon")
  PATH = File.join(FIXTURES, "etymology", "etymology01.xml")

  def entries
    @entries ||= Nabu::Adapters::CalfaEtymologyParser.new
                                                     .entries(File.read(PATH, encoding: "UTF-8"),
                                                              language: "xcl", label: "etymology01.xml")
  end

  def by_id = entries.to_h { |entry| [entry.entry_id, entry] }

  def test_every_entry_element_is_one_entry_in_document_order
    assert_equal ["ԱԲ", "*ԱԲԲԱ_կամ_ԱԲԲԱՅ", "ԱԳՈՒՌ", "ԱԿՈՒԹ", "ԱՃԱՌ", "ԱՃԱՌ:2", "+ԱՅՐ", "+ԱՐՈՒ",
                  "*ԳԱՒԱՌ", "ԵՂԱՆԱԿ", "*ԹԱՐԽԱՆԱՅ"], entries.map(&:entry_id),
                 "headword ids (spaces as underscores); the duplicate ԱՃԱՌ takes the occurrence suffix"
  end

  def test_the_body_keeps_every_section_in_order_and_the_gloss_is_the_first_guillemet_meaning
    ab = by_id.fetch("ԱԲ")
    assert_equal "ԱԲ", ab.key_raw
    assert_equal "ԱԲ", ab.headword, "Ačaṙean's capitals stay on display"
    assert_equal Nabu::Normalize.search_form("ԱԲ", language: "xcl"), ab.headword_folded
    assert_equal "հրէական տոմարի 11-րդ ամիսը", ab.gloss
    lines = ab.body.lines.map(&:chomp)
    assert_equal "ԱԲ", lines[0]
    assert lines[1].start_with?("«հրէական տոմարի"), "content"
    assert lines[2].start_with?("= ասոր."), "the egal etymology, its own '=' sign verbatim"
    assert lines[3].start_with?("Ուղիղ մեկնեց Müller"), "the earlier-explanations section"
    assert_includes ab.body, "[hebrew word]", "upstream's AI-processing placeholders stay verbatim"
  end

  def test_dialect_and_loan_sections_ride_the_body_with_their_own_labels
    akut = by_id.fetch("ԱԿՈՒԹ")
    assert_match(/^ԳՒՌ\.-Ջղ\. աքութ/, akut.body)
    assert_match(/^ՓՈԽ\.-Վրաց\. ակութա/, akut.body)
  end

  def test_variant_headwords_fold_on_the_first_form_and_point_at_the_others
    abba = by_id.fetch("*ԱԲԲԱ_կամ_ԱԲԲԱՅ")
    assert_equal "*ԱԲԲԱ կամ ԱԲԲԱՅ", abba.headword
    assert_equal Nabu::Normalize.search_form("ԱԲԲԱ", language: "xcl"), abba.headword_folded,
                 "the mark strips and the first form is the lookup key"
    refs = abba.crossrefs.map { |ref| [ref.kind, ref.label, ref.target, ref.target_folded] }
    assert_equal [["variant", "ԱԲԲԱՅ", "ԱԲԲԱՅ", Nabu::Normalize.search_form("ԱԲԲԱՅ", language: "xcl")]], refs
    assert_equal "հայր, Երկ-նաւոր Հայր", abba.gloss, "upstream's OCR line-break hyphen stays"
    assert_equal({ "headword_mark" => "*" }, abba.annotations)
  end

  def test_the_plus_mark_is_recorded_verbatim_not_interpreted
    ayr = by_id.fetch("+ԱՅՐ")
    assert_equal({ "headword_mark" => "+" }, ayr.annotations)
    assert_equal Nabu::Normalize.search_form("ԱՅՐ", language: "xcl"), ayr.headword_folded
    assert_equal "արու մարդ", ayr.gloss
  end

  def test_no_typed_etymon_relation_exists_so_no_reflex_rows_mint
    entries.each { |entry| assert_empty entry.reflexes, entry.entry_id }
  end

  def test_contentless_and_headword_only_entries_are_honest
    aru = by_id.fetch("+ԱՐՈՒ")
    assert_nil aru.gloss, "no <content>, no guillemet meaning"
    assert_equal 4, aru.body.lines.size, "headword + egal + the two page-split indent_content halves"
    stub = by_id.fetch("ԵՂԱՆԱԿ")
    assert_equal "ԵՂԱՆԱԿ", stub.body, "upstream's headword-only entry keeps its place"
    assert_nil stub.gloss
  end

  def test_empty_page_break_marks_leave_no_trace
    gawar = by_id.fetch("*ԳԱՒԱՌ")
    assert_equal 6, gawar.body.lines.size, "headword, content, egal, indent_content ×2, ՓՈԽ — <other_pox/> is empty"
    assert_equal 4, by_id.fetch("*ԹԱՐԽԱՆԱՅ").body.lines.size, "<indent/> is empty"
  end

  def test_the_combining_macrons_compose_at_the_boundary
    refute File.read(PATH, encoding: "UTF-8").unicode_normalized?(:nfc),
           "the fixture carries upstream's a + U+0304 bytes"
    entries.each do |entry|
      assert entry.body.unicode_normalized?(:nfc), entry.entry_id
      assert entry.headword.unicode_normalized?(:nfc), entry.entry_id
    end
    assert_includes by_id.fetch("ԱԲ").body, "āb-māh"
  end

  def test_malformed_xml_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CalfaEtymologyParser.new.entries("<dictionary><entry><headword>Ա</entry>",
                                                       language: "xcl", label: "bad.xml")
    end
  end

  def test_an_entry_without_a_headword_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CalfaEtymologyParser.new.entries("<dictionary><entry><content>x</content></entry></dictionary>",
                                                       language: "xcl", label: "bad.xml")
    end
  end
end
