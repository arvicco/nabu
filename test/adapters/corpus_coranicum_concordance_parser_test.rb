# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# CorpusCoranicumConcordanceParser: one quran_concordance/suraNNN.xml (the
# Talmon concordance as edited by Corpus Coranicum) read into its word
# analyses, keyed by (verse, word number), in file order. Fixtures: the
# whole real sura001.xml, sura111.xml and sura112.xml.
class CorpusCoranicumConcordanceParserTest < Minitest::Test
  PARSER = Nabu::Adapters::CorpusCoranicumConcordanceParser
  DIR = File.join(Nabu::TestSupport.fixtures("corpus-coranicum"), "data", "quran_concordance")

  def analyses(name = "sura001.xml", sura: 1) = PARSER.new.analyses(File.join(DIR, name), sura: sura)

  def test_keys_every_analysis_by_verse_and_word_number
    rows = analyses
    assert_equal 29, rows.size, "one key per Cairo word of sura 1"
    assert_equal 31, rows.values.sum(&:size), "two words carry a second analysis"
    assert_equal [[1, 1], [1, 2], [1, 3], [1, 4], [2, 1]], rows.keys.first(5)
    assert_equal(%w[1 2], rows.fetch([2, 3]).map { |row| row["analysis_number"] })
  end

  def test_values_are_decoded_text_verbatim
    row = analyses.fetch([1, 3]).first
    assert_equal "rḥm", row["root_corpus_coranicum"]
    assert_equal "rHm", row["root_rafi_talmon"]
    assert_equal "raḥmān", row["base_corpus_coranicum"]
    assert_equal "fa&laan", row["analyse_pattern"], "the &amp; entity decodes"
    assert_equal "", row["analyse_mood"], "an empty seg is the empty string"
  end

  def test_a_row_of_another_sura_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { analyses("sura112.xml", sura: 1) }
    assert_includes error.message, "sura 112"
  end

  def test_an_unknown_segment_type_is_a_parse_error
    with_file(->(xml) { xml.sub('<seg type="analyse_mood"/>', '<seg type="analyse_voice"/>') }) do |path|
      error = assert_raises(Nabu::ParseError) { PARSER.new.analyses(path, sura: 112) }
      assert_includes error.message, "analyse_voice"
    end
  end

  def test_a_row_without_its_key_is_a_parse_error
    with_file(->(xml) { xml.sub('<seg type="word_number">1</seg>', '<seg type="word_number"/>') }) do |path|
      assert_raises(Nabu::ParseError) { PARSER.new.analyses(path, sura: 112) }
    end
  end

  private

  def with_file(edit)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sura112.xml")
      File.write(path, edit.call(File.read(File.join(DIR, "sura112.xml"), encoding: "utf-8")))
      yield path
    end
  end
end
