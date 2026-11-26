# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The med-headwords-xml parser family (Nabu::Adapters::MedHeadwordsParser):
# the Middle English Dictionary's headword / variant-spelling / entry-id
# list as its editors publish it — one <ENTRY> per MED entry, the form
# section excerpted from the dictionary's own XML (HDORTH/ORTH spellings
# split into display ORIG and search REG, POS with PS expansions, the
# DUB/DEL editorial flags). Runs over the real trimmed list in
# test/fixtures/med-headwords/ (15 entries cut verbatim from the October
# 2023 list; README beside it).
class MedHeadwordsParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("med-headwords")
  PATH = File.join(FIXTURES, "headwords_202310.xml")
  PARSER = Nabu::Adapters::MedHeadwordsParser

  def entries = @entries ||= PARSER.new.entries(PATH)

  def entry(id) = entries.find { |e| e.entry_id == id } || flunk("entry #{id} missing")

  def test_one_entry_per_entry_element_in_file_order
    assert_equal %w[MED1 MED2 MED2.5 MED3 MED28 MED84.5 MED261 MED927 MED979 MED1431 MED1519
                    MED2039 MED5005.5 MED20283 MED54083], entries.map(&:entry_id)
    assert(entries.all? { |e| e.language == "enm" })
  end

  def test_headword_is_the_first_display_spelling_and_folds_from_the_editors_search_form
    assert_equal "ā", entry("MED1").headword, "the NCR &#x0101; decoded"
    assert_equal "a", entry("MED1").headword_folded
    assert_equal "a", entry("MED1").key_raw, "key_raw = the first HDORTH's REG verbatim"
    assert_equal "aknẹ̄(s", entry("MED979").headword, "ORIG verbatim, parenthetical and all"
    assert_equal "akne", entry("MED979").headword_folded, "the REG drops the parenthetical"
    assert_equal "hei-rive", entry("MED20283").headword_folded
  end

  def test_body_renders_the_form_section_as_the_print_dictionary_shows_it
    assert_equal "ā n.(1)", entry("MED1").body.lines.first.chomp
    assert_equal "abandonen, -ǒunen v. Also abaund-, abound-, haboundon, -en.",
                 entry("MED28").body.lines.first.chomp
    assert_equal "a indef. art. Also an. Early forms: as subj., ane, on, o; as obj., ane, on(e, o, " \
                 "& (chiefly masc.) an(n)e, æn(n)e, en(n)e, en; after prep., chiefly ane, on(e, " \
                 "masc. also anne, æn(n)e, fem. also anre, are, hare, ore; gen. anes, æn(n)es, en(n)es.",
                 entry("MED3").body.lines.first.chomp
    assert_equal "acceptāble adj. Also (error, by confusion with excepten v., etc.) exceptable.",
                 entry("MED261").body.lines.first.chomp, "HI runs keep their text"
    assert_equal "amid(de, amiddes adv. & prep. Also omid & imidde(s, emidde(s(t.",
                 entry("MED1431").body.lines.first.chomp, "the maybe comment never reaches the text"
  end

  def test_upstream_irregularities_render_without_loss
    assert_match(/hai-reve, hai-rive\.\z/, entry("MED20283").body.lines.first.chomp,
                 "an ORTH with no ORIG falls back to its first REG")
    assert_match(/Also biwastid, bewastid\./, entry("MED5005.5").body,
                 "an ORTH carrying two ORIGs renders both")
    assert_equal "ananizapta, -us", entry("MED1519").body.lines.first.chomp, "an empty POS stays empty"
  end

  def test_every_entry_cites_its_online_med_entry
    url = "https://quod.lib.umich.edu/m/middle-english-dictionary/dictionary/MED2.5"
    assert_equal 1, entry("MED2.5").citations.size
    citation = entry("MED2.5").citations.first
    assert_equal url, citation.urn_raw
    assert_nil citation.cts_work
    assert_equal "MED2.5", citation.citation
    assert_equal "Middle English Dictionary, MED2.5", citation.label
    assert_equal url, entry("MED2.5").annotations["url"]
    assert_includes entry("MED2.5").body, "MED entry: #{url}"
    assert(entries.all? { |e| e.citations.size == 1 })
  end

  def test_annotations_mine_every_field_of_the_entry
    amid = entry("MED1431").annotations
    assert_equal %w[adverb preposition], amid["pos"], "every PS EXPAN, in order"
    assert_equal "adv. & prep.", amid["pos_label"]
    assert_equal %w[amid(de amiddes], amid["headword_forms"]
    assert_equal %w[omid imidde(s emidde(s(t], amid["variants"]
    assert_equal %w[amid amidde amiddes omid imidde imiddes emidde emiddes emiddest emiddet],
                 amid["search_forms"]
    assert_equal %w[emiddet], amid["doubtful_search_forms"], "the editors' <!-- maybe --> mark"
    assert_equal 1613, amid["seq"]
    refute amid.key?("dubious")
    assert_equal "n.(1)", entry("MED1").annotations["pos_label"]
    assert_equal "lattaj", entry("MED2.5").annotations["resp"]
    refute entry("MED1519").annotations.key?("pos"), "no PS, no pos claim"
  end

  def test_editorial_flags_are_carried_and_stated
    dubious = entry("MED84.5")
    assert dubious.annotations["dubious"]
    assert_includes dubious.body, "[queried (dubious) entry]"
    deprecated = entry("MED2039")
    assert deprecated.annotations["deprecated"]
    assert_includes deprecated.body, "[flagged for deletion in the editors' working copy]"
    refute entry("MED1").annotations.key?("deprecated")
  end

  def test_output_is_nfc_and_glossless
    entries.each do |e|
      assert e.headword.unicode_normalized?(:nfc), e.entry_id
      assert e.body.unicode_normalized?(:nfc), e.entry_id
      assert_nil e.gloss, "the list carries no definitions"
    end
  end

  def test_malformed_xml_and_an_idless_entry_are_parse_errors
    Dir.mktmpdir do |dir|
      broken = File.join(dir, "headwords_202310.xml")
      File.write(broken, "<HEADWORDS><ENTRY ID=\"MED1\"><FORM>")
      assert_raises(Nabu::ParseError) { PARSER.new.entries(broken) }
      File.write(broken, "<HEADWORDS><ENTRY SEQ=\"1\"><FORM><HDORTH><REG>a</REG><ORIG>a</ORIG></HDORTH>" \
                         "</FORM></ENTRY></HEADWORDS>")
      error = assert_raises(Nabu::ParseError) { PARSER.new.entries(broken) }
      assert_match(/no ID/, error.message)
    end
  end
end
