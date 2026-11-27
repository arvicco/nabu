# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Corpus Coranicum manuscript-record parser: the msDesc header as plain
# fields, and the rasm transcription as verses of words in manuscript order —
# supplied / unclear / add / mod read through, del in ⟦…⟧, the extant form
# beside, line-split fragments joined, markers on the verse they follow,
# sura headings as verse 0. Fixtures: three whole transcribed records
# (manuscript-00017, -00504, -01362), the metadata-only manuscript-02504 and
# the places.xml trim (test/fixtures/corpus-coranicum/README.md).
class CorpusCoranicumManuscriptParserTest < Minitest::Test
  PARSER = Nabu::Adapters::CorpusCoranicumManuscriptParser
  DIR = File.join(Nabu::TestSupport.fixtures("corpus-coranicum"), "data", "quran_manuscripts")

  def record(name) = (@records ||= {})[name] ||= PARSER.new.parse(File.join(DIR, "#{name}.xml"))

  def verse(name, sura, number) = record(name).verses.find { |v| v.sura == sura && v.verse == number }

  def test_the_header_fields
    header = record("manuscript-00017").header
    assert_equal "Chicago, Institute for the Study of Ancient Cultures, A 6990", header["title"]
    assert_equal "A 6990", header["shelfmark"]
    assert_equal "5", header["repository_key"]
    assert_equal "parchment", header["material"]
    assert_equal "kūfī B.Ia", header["script"]
    assert_equal "650-750", header["orig_date_text"]
    assert_equal "al-Fusṭāṭ", header["provenance"]
    assert_equal "6", header["written_lines"]
    assert_includes header["record_history"], "transliteration: Salome Beridze"
    assert_equal ["Image credits: Courtesy of Oriental Institute of the University of Chicago."],
                 header["image_credits"]
  end

  def test_verses_in_manuscript_order_with_the_heading_as_verse_zero
    verses = record("manuscript-00017").verses
    assert_equal 17, verses.size
    assert_equal [97, 4], [verses.first.sura, verses.first.verse]
    headings = verses.select { |v| v.verse.zero? }.map { |v| [v.sura, v.verse] }
    assert_equal [[98, 0], [100, 0]], headings
  end

  def test_supplied_letters_read_through_and_the_extant_form_marks_them
    word = verse("manuscript-00017", 97, 4).words.first
    assert_equal "097-004-001", word.key
    assert_equal "لٮله", word.form
    assert_equal "[…]", word.extant
    assert_equal 4, word.supplied
    assert_equal "[…]در […]", verse("manuscript-00017", 97, 4).extant
  end

  # 097-005-003 ends line 1 and repeats its key on line 2 (upstream:
  # "Continued from last line") — one word, two parts, both lines.
  def test_a_line_split_word_joins_into_one
    verse = verse("manuscript-00017", 97, 5)
    word = verse.words.find { |w| w.key == "097-005-003" }
    assert_equal 2, word.parts
    assert_equal "والروحالروح", word.form, "upstream supplies the whole word on line 1 AND its continuation"
    assert_equal "[…]روح", word.extant, "adjacent supplied stretches collapse"
    assert_equal %w[1r.1 1r.2], verse.lines
  end

  def test_markers_follow_their_verse_and_line_notes_ride_the_lines
    assert_equal ["۝٣"], verse("manuscript-00017", 97, 4).markers
    assert_equal({ "1v.2" => "مِثۡقَالَ" }, verse("manuscript-00017", 99, 6).line_notes)
  end

  def test_del_renders_in_double_brackets_and_add_and_mod_are_counted
    word = verse("manuscript-01362", 38, 79).words.first
    assert_equal "⟦و⟧>ٯال", word.form, "the stray > is upstream's, verbatim"
    assert word.cancelled
    assert_equal 2, verse("manuscript-01362", 39, 3).words.find { |w| w.key == "039-003-021" }.added
    assert_equal 5, verse("manuscript-01362", 39, 0).words.first.modified
    assert(verse("manuscript-01362", 39, 0).words.any?(&:unclear_word))
  end

  # Real bytes: the archaic dotless letters of the rasm (ٯ U+066F in لٯد,
  # ٮ U+066E) survive, and NFC leaves the transcription byte-identical
  # (0 of the clone's 411,803 words change, census 2026-11-27).
  def test_the_archaic_letters_survive_and_nfc_changes_nothing
    text = verse("manuscript-00504", 48, 27).text
    assert text.start_with?("لٯد صدٯ")
    assert_includes text.codepoints, 0x066F
    assert_includes text.codepoints, 0x066E
    assert_equal text, text.unicode_normalize(:nfc)
  end

  def test_a_metadata_only_record_has_no_verses
    manuscript = record("manuscript-02504")
    assert_empty manuscript.verses
    assert_equal "96D17", manuscript.header["shelfmark"]
    refute PARSER.transcribed?(File.read(File.join(DIR, "manuscript-02504.xml"), encoding: "utf-8"))
    assert PARSER.transcribed?(File.read(File.join(DIR, "manuscript-00017.xml"), encoding: "utf-8"))
  end

  # A verse whose words come back after another verse intervened merges, its
  # runs counted (the CntrMesParser precedent).
  def test_a_verse_resumed_after_another_merges_and_counts_its_stretches
    xml = File.read(File.join(DIR, "manuscript-00017.xml"), encoding: "utf-8")
    with_record(xml.sub('<w n="097-005-004">', '<w n="097-004-007">')) do |path|
      manuscript = PARSER.new.parse(path)
      merged = manuscript.verses.find { |v| v.sura == 97 && v.verse == 4 }
      assert_equal 2, merged.stretches
      assert_equal "097-004-007", merged.words.last.key
      assert_equal 0, merged.repeated_words
    end
  end

  def test_unkeyed_and_empty_words_are_counted_not_carried
    xml = File.read(File.join(DIR, "manuscript-00017.xml"), encoding: "utf-8")
    xml = xml.sub('<w n="097-005-004">ڡٮها</w>', "<w>ڡٮها</w>")
             .sub('<w n="097-005-005">ٮاذں</w>', '<w n="097-005-005"/>')
    with_record(xml) do |path|
      manuscript = PARSER.new.parse(path)
      assert_equal 1, manuscript.unkeyed
      assert_equal 1, manuscript.empty_words
      refute(manuscript.verses.flat_map(&:words).any? { |w| w.key == "097-005-005" })
    end
  end

  def test_a_key_of_no_known_shape_and_an_unknown_element_are_parse_errors
    xml = File.read(File.join(DIR, "manuscript-00017.xml"), encoding: "utf-8")
    with_record(xml.sub('<w n="097-005-004">', '<w n="97-5-4">')) do |path|
      assert_includes assert_raises(Nabu::ParseError) { PARSER.new.parse(path) }.message, "97-5-4"
    end
    with_record(xml.sub('<w n="097-005-004">ڡٮها</w>', '<w n="097-005-004"><gap/>ڡٮها</w>')) do |path|
      assert_includes assert_raises(Nabu::ParseError) { PARSER.new.parse(path) }.message, "<gap>"
    end
  end

  def test_the_repository_authority
    repositories = PARSER.new.repositories(File.join(DIR, "places.xml"))
    assert_equal %w[113 3 5 84], repositories.keys.sort
    assert_equal({ "name" => "Bibliothèque nationale de France", "settlement" => "Paris", "country" => "FR",
                   "geonames" => "6452876" }, repositories.fetch("3"))
    refute repositories.fetch("84").key?("geonames"), "a blank geoname_ key is no id"
  end

  private

  def with_record(xml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "manuscript-00017.xml")
      File.write(path, xml)
      yield path
    end
  end
end
