# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The `sentence-lines` parser family (P80-6): one plain-text file, one
# sentence per line, no ids — the shared carrier of the small-languages
# pack (cv-sardinian, salom, aranese). The tests pin the two censused
# upstream quirks the family exists to hold: a final line WITHOUT a
# trailing newline still yields (Common Voice), and blank lines yield
# nothing while line-number identity stays put (the Şalom trailing blank).
class SentenceLinesParserTest < Minitest::Test
  def parser
    Nabu::Adapters::SentenceLinesParser.new
  end

  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sentences.txt")
      File.binwrite(path, content)
      yield path
    end
  end

  def test_yields_number_and_text_per_line_in_file_order
    with_file("Una frase.\nUn'àtera.\n") do |path|
      assert_equal [[1, "Una frase."], [2, "Un'àtera."]], parser.each_sentence(path).to_a
    end
  end

  def test_final_line_without_trailing_newline_still_yields
    with_file("Una frase.\nÙndighi.") do |path|
      assert_equal [[1, "Una frase."], [2, "Ùndighi."]],
                   parser.each_sentence(path).to_a,
                   "the Common Voice artifact ends without a newline — the last sentence is real"
    end
  end

  def test_blank_lines_yield_nothing_but_keep_line_number_identity
    with_file("Una frase.\n\n  \nOtra frase.\n\n") do |path|
      assert_equal [[1, "Una frase."], [4, "Otra frase."]],
                   parser.each_sentence(path).to_a,
                   "blank/whitespace-only lines mint no passage; numbering never re-flows"
    end
  end

  def test_returns_an_enumerator_without_a_block
    with_file("Una frase.\n") do |path|
      enum = parser.each_sentence(path)
      assert_kind_of Enumerator, enum
      assert_equal [[1, "Una frase."]], enum.to_a
    end
  end

  def test_text_is_yielded_verbatim_not_normalized
    decomposed = "Décembre"
    with_file("#{decomposed}\n") do |path|
      assert_equal [[1, decomposed]], parser.each_sentence(path).to_a,
                   "NFC is the ADAPTER boundary's job (Normalize.nfc); the parser stays verbatim"
    end
  end

  def test_invalid_utf8_raises_parse_error_naming_file_and_line
    with_file("bona\n\xFFmala\n".b) do |path|
      error = assert_raises(Nabu::ParseError) { parser.each_sentence(path).to_a }
      assert_match(/line 2/, error.message)
      assert_includes error.message, path
    end
  end
end
