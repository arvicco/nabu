# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# CorpusCoranicumCairoParser: the arabic_text div of the Corpus Coranicum
# cairoquran.xml (the Cairo 1924 text) read into suras → verses → words,
# each verse on the facsimile page whose range covers it. The fixture is a
# verbatim line cut of suras 1, 111 and 112 with three facsimile surfaces
# (test/fixtures/corpus-coranicum/README.md).
class CorpusCoranicumCairoParserTest < Minitest::Test
  PARSER = Nabu::Adapters::CorpusCoranicumCairoParser
  CAIRO = File.join(Nabu::TestSupport.fixtures("corpus-coranicum"), "data", "cairo_quran", "cairoquran.xml")

  def suras(path = CAIRO) = PARSER.new.suras(path)

  def test_reads_the_arabic_text_suras_only
    parsed = suras
    assert_equal [1, 111, 112], parsed.keys
    assert_equal [7, 5, 4], parsed.values.map(&:size)
    assert_equal([29, 23, 15], parsed.values.map { |verses| verses.sum { |verse| verse.words.size } })
  end

  def test_words_keep_their_ids_and_vocalized_forms
    verse = suras.fetch(112).first
    assert_equal 1, verse.number
    assert_equal %w[w-112-001-001 w-112-001-002 w-112-001-003 w-112-001-004], verse.words.map(&:id)
    assert_equal "قُلۡ هُوَ ٱللَّهُ أَحَدٌ", verse.text
    assert_equal [1, 2, 3, 4], verse.words.map(&:number)
  end

  def test_each_verse_lands_on_the_facsimile_page_whose_range_covers_it
    parsed = suras
    assert_equal ["2"], parsed.fetch(1).map(&:page).uniq
    assert_equal %w[825 825 826 826 826], parsed.fetch(111).map(&:page), "page 826 opens at Q 111:3"
    assert_equal ["826"], parsed.fetch(112).map(&:page).uniq, "a page carries across the sura boundary"
  end

  def test_a_verse_no_surface_covers_carries_no_page
    with_cairo(->(xml) { xml.sub(%r{ +<surface n="2, Q 1:1- Q 1:7".*?</surface>\n}m, "") }) do |path|
      assert_equal [nil], suras(path).fetch(1).map(&:page).uniq
    end
  end

  def test_a_word_id_outside_its_verse_is_a_parse_error
    with_cairo(->(xml) { xml.sub('xml:id="w-112-001-002"', 'xml:id="w-112-002-002"') }) do |path|
      error = assert_raises(Nabu::ParseError) { suras(path) }
      assert_includes error.message, "w-112-002-002"
    end
  end

  def test_a_gap_in_the_word_numbering_is_a_parse_error
    with_cairo(->(xml) { xml.sub('xml:id="w-112-001-002"', 'xml:id="w-112-001-009"') }) do |path|
      assert_raises(Nabu::ParseError) { suras(path) }
    end
  end

  def test_an_unknown_element_in_the_arabic_text_is_a_parse_error
    with_cairo(->(xml) { xml.sub('<w xml:id="w-112-001-001">', '<note>x</note><w xml:id="w-112-001-001">') }) do |path|
      error = assert_raises(Nabu::ParseError) { suras(path) }
      assert_includes error.message, "note"
    end
  end

  def test_malformed_xml_is_a_parse_error
    with_cairo(->(xml) { xml.sub("</TEI>", "") }) do |path|
      assert_raises(Nabu::ParseError) { suras(path) }
    end
  end

  private

  def with_cairo(edit)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cairoquran.xml")
      File.write(path, edit.call(File.read(CAIRO, encoding: "utf-8")))
      yield path
    end
  end
end
