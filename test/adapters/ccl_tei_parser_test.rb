# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The ccl-tei parser family (P28-3): the Comprehensive Coptic Lexicon v1.2
# TEI — namespaced TEI P5 against the project's own Coptic_Lemma_Schema (NOT
# the P4/PersDict shape LexiconTeiParser reads: <entry xml:id="C…"> under
# <body>, some nested in id-less <superEntry> groups, no @key, dialect
# labels in usg[@type="geo"], senses as <cit type="translation"> with
# de/en/fr quotes, print-dictionary <bibl> strings). Streams with
# Nokogiri::XML::Reader (the full file is 11.77 MB — the no-DOM-over-5MB
# rule) and DOM-parses one entry at a time.
class CclTeiParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("ccl"),
                      "lexicon", "Comprehensive_Coptic_Lexicon-v1.2-2020.xml")

  def entries(etymologies: {})
    Nabu::Adapters::CclTeiParser.new.entries(FIXTURE, etymologies: etymologies)
  end

  def test_yields_every_entry_flat_whether_body_level_or_super_entry_nested
    ids = entries.map(&:entry_id)
    assert_equal ids.uniq, ids, "C-ids are unique"
    assert_equal 17, ids.size
    assert_includes ids, "C1", "superEntry-nested entries yield"
    assert_includes ids, "C16", "body-level entries yield"
    assert_includes ids, "C1494"
  end

  def test_headword_is_the_lemma_form_orth
    kah = entries.find { |entry| entry.entry_id == "C1494" }
    assert_equal "ⲕⲁϩ", kah.headword
    assert_equal "ⲕⲁϩ", kah.headword_folded
    assert_equal "C1494", kah.key_raw, "no upstream @key exists; the xml:id is the stable key"
    assert_equal "cop", kah.language
  end

  def test_headword_folded_strips_morph_hyphen_and_pronominal_double_hyphen
    prefix = entries.find { |entry| entry.entry_id == "C2" }
    assert_equal "ⲁ-", prefix.headword, "the display headword keeps upstream's hyphen"
    assert_equal "ⲁ", prefix.headword_folded,
                 "the lookup key drops the stem hyphen (the LexiconTeiParser fold contract)"
    assert_includes prefix.body, "ⲁ⸗", "status-pronominalis forms (U+2E17) read in the body"
  end

  def test_the_one_lemma_less_entry_falls_back_to_its_first_orth
    entry = entries.find { |e| e.entry_id == "C11273" }
    assert_equal "ⲃⲁⲕ-", entry.headword,
                 "C11273 is the corpus's one form[@type=lemma]-less entry (censused 2026-07-18)"
    assert_equal "ⲃⲁⲕ", entry.headword_folded
  end

  def test_gloss_prefers_the_english_quote
    kah = entries.find { |entry| entry.entry_id == "C1494" }
    assert_equal "earth, soil", kah.gloss
  end

  def test_body_carries_dialects_all_three_gloss_languages_and_print_bibls
    kah = entries.find { |entry| entry.entry_id == "C1494" }
    assert_includes kah.body, "S ⲕⲁϩ", "dialect sigla label the forms"
    assert_includes kah.body, "Subst."
    assert_includes kah.body, "Erde, Boden"
    assert_includes kah.body, "earth, soil"
    assert_includes kah.body, "terre"
    assert_includes kah.body, "CD 131ab; KoptHWb 73; ChLCS 20a",
                    "print-dictionary bibl strings stay as body text (no CTS urns -> no citation rows)"
  end

  def test_foreign_entries_keep_their_etymology_note_in_the_body
    loan = entries.find { |entry| entry.entry_id == "C16" }
    assert_includes loan.body, "persisches Lehnwort"
  end

  def test_entries_mint_no_citations_without_a_crosswalk
    assert(entries.all? { |entry| entry.citations.empty? })
  end

  def test_crosswalk_rows_mint_ancestor_citations
    etymologies = { "C1494" => %w[159410 6439], "C9" => [nil, "928"], "C74" => ["39210", "-1427"] }
    by_id = entries(etymologies: etymologies).to_h { |entry| [entry.entry_id, entry] }

    kah = by_id.fetch("C1494").citations
    assert_equal %w[urn:nabu:dict:aed:159410 urn:nabu:dict:tla-demotic:6439], kah.map(&:urn_raw)
    assert_equal "TLA 159410 (hieroglyphic; ORAEC crosswalk)", kah.first.label
    assert_equal "TLA demotic 6439 (ORAEC crosswalk)", kah.last.label
    assert kah.all? { |citation| citation.cts_work.nil? && citation.citation.nil? },
           "ancestor ids resolve through the links journal, never the CTS citation path"

    assert_equal ["urn:nabu:dict:tla-demotic:928"], by_id.fetch("C9").citations.map(&:urn_raw)
    assert_equal %w[urn:nabu:dict:aed:39210 urn:nabu:dict:tla-demotic:-1427],
                 by_id.fetch("C74").citations.map(&:urn_raw),
                 "negative demotic word ids ride verbatim (220 in the full crosswalk)"
    assert by_id.fetch("C1").citations.empty?, "entries without a crosswalk row mint none"
  end

  def test_output_is_nfc
    entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.xml")
      File.write(path, "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><text><body><entry")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::CclTeiParser.new.entries(path) }
    end
  end

  def test_entry_without_xml_id_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "anon.xml")
      File.write(path, <<~XML)
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
          <entry><form type="lemma"><orth>ⲁ</orth></form></entry>
        </body></text></TEI>
      XML
      assert_raises(Nabu::ParseError) { Nabu::Adapters::CclTeiParser.new.entries(path) }
    end
  end
end
