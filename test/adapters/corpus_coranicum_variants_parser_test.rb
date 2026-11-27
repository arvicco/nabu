# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Corpus Coranicum variant-readings parser: allvariants.xml streamed into
# reading items (readers, word-keyed transliterations), reader.xml into the
# authority, and the reader's <death> prose read into a CE upper bound.
# Fixtures: the line trim of allvariants.xml to the items of suras 111 and 112
# plus three specimens (a reader-less item, two empty ones), and reader.xml
# trimmed to the readers those items cite (test/fixtures/corpus-coranicum/README.md).
class CorpusCoranicumVariantsParserTest < Minitest::Test
  PARSER = Nabu::Adapters::CorpusCoranicumVariantsParser
  DIR = File.join(Nabu::TestSupport.fixtures("corpus-coranicum"), "data", "quran_variants")
  ITEMS = File.join(DIR, "allvariants.xml")
  READERS = File.join(DIR, "reader.xml")

  def items = @items ||= PARSER.new.items(ITEMS)

  def test_every_item_of_the_trim_in_file_order
    assert_equal 103, items.size
    assert_equal(180, items.sum { |item| item.words.size })
    assert_equal "variant_804", items.first.id
  end

  def test_an_item_carries_its_readers_and_its_word_keyed_reading
    item = items.find { |candidate| candidate.id == "variant_1702" }
    assert_equal ["40"], item.readers
    assert_equal %w[111:001:002 111:001:003 111:001:004], item.words.map(&:key)
    assert_equal %w[yadā ʾabī lahbin], item.words.map(&:form)
    assert_equal [111, 1, 2], [item.words.first.sura, item.words.first.verse, item.words.first.number]
  end

  def test_a_reading_ascribed_to_no_reader_and_the_empty_items
    readerless = items.find { |item| item.id == "variant_2330" }
    assert_empty readerless.readers
    assert_equal ["ʾuṣrī"], readerless.words.map(&:form)
    assert_empty items.find { |item| item.id == "variant_12427" }.words
    assert_equal ["444"], items.find { |item| item.id == "variant_12428" }.readers
  end

  def test_the_inner_arabic_w_is_empty_and_contributes_nothing
    refute(items.flat_map(&:words).any? { |word| word.form.match?(/\p{Arabic}/) })
    refute(items.flat_map(&:words).any? { |word| word.form.match?(/\s{2}|\A\s|\s\z/) })
  end

  def test_an_item_spanning_two_verses_is_a_parse_error
    xml = File.read(ITEMS, encoding: "utf-8").sub(/(variant_1702.*?)<w n="111:001:003">/m, '\1<w n="111:002:003">')
    with_items(xml) do |path|
      error = assert_raises(Nabu::ParseError) { PARSER.new.items(path) }
      assert_includes error.message, "variant_1702"
    end
  end

  def test_an_unknown_element_in_an_item_is_a_parse_error
    with_items(File.read(ITEMS, encoding: "utf-8").sub('<title key="variantsource_"/>', "<note>x</note>")) do |path|
      assert_raises(Nabu::ParseError) { PARSER.new.items(path) }
    end
  end

  def test_the_reader_authority
    readers = PARSER.new.readers(READERS)
    assert_equal 73, readers.size
    kathir = readers.fetch("40")
    assert_equal "Ibn Kaṯīr", kathir.name
    assert_equal "Mekka", kathir.residence
    assert_equal "737-740", kathir.death
    assert_equal "0200", kathir.sigle
    assert_match(/al-Makkī/, kathir.full_name)
    assert_nil readers.fetch("444").death
  end

  # Real <death> values of reader.xml (the census of all 238, 2026-11-27).
  def test_the_death_prose_reads_into_a_ce_upper_bound
    {
      "796" => 796, "758 oder 770" => 770, "914, 915, 916" => 916, "770-773" => 773, "vor 709" => 709,
      "st. 190 (805-6)" => 806, "st. ca. 127  (744-5)" => 745, "168 AH = 784-785" => 785,
      "st. 202 AH = 817/818" => 818, "st. ca. 345/956" => 956, "830/831)" => 831, "st. (765/6)" => 766,
      "(st. ... (762))" => 762, "ca. 2 Jh. (8. Jh.)" => 800, "2./8. Jhdt." => 800, "um 800 n.Chr." => 800,
      "st. 327/8 (938-39)" => 939, "starb 40 AH (661)" => 661
    }.each { |prose, year| assert_equal year, PARSER.death_bound(prose), prose }
  end

  def test_death_prose_naming_no_ce_year_bounds_nothing
    ["st. 65 AH", "80 oder 100 AH", "nach 816", "st. 148 oder später", "94 oder 95", "vor 90", "?",
     "unbekannt", "doppelt", "ca. 4. Jhdt. AH", "(2. Jhdt. AH)", "st. 93 AH ( . )", "st. ca. 210/221", nil]
      .each { |prose| assert_nil PARSER.death_bound(prose), prose.inspect }
  end

  private

  def with_items(xml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "allvariants.xml")
      File.write(path, xml)
      yield path
    end
  end
end
