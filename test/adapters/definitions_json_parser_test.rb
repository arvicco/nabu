# frozen_string_literal: true

require "test_helper"

# The definitions-json parser family: a top-level JSON array of
# {"word", "definitions": [...]} records whose definition strings carry
# the printed book's inline markup (<strong> forms, <i> English glosses)
# — the shape of stscoundrel's Cleasby-Vigfusson and Zoëga editions.
# Exercised over the trimmed-real Cleasby-Vigfusson fixture.
class DefinitionsJsonParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("cleasby-vigfusson"), "json", "cleasby-vigfusson.json")

  def entries
    @entries ||= Nabu::Adapters::DefinitionsJsonParser.new(language: "non").entries(FIXTURE)
  end

  def entry(id) = entries.find { |e| e.entry_id == id }

  def test_one_entry_per_record_in_file_order
    assert_equal ["abbadís", "Gýmir", "stefja:1", "stefja:2"], entries.map(&:entry_id)
    assert(entries.all? { |e| e.language == "non" })
  end

  # A word printed more than once (homographs) numbers EVERY occurrence
  # 1-based in file order; a unique word keeps the bare word as its id.
  def test_homographs_number_every_occurrence
    assert_equal %w[stefja stefja], [entry("stefja:1"), entry("stefja:2")].map(&:headword)
    assert_equal "stefja", entry("stefja:1").key_raw
  end

  def test_body_is_one_line_per_definition_with_markup_stripped
    assert_equal "f. abbess. Hkr. iii. 398, Fms. vii. 239, Gþl. 365.", entry("abbadís").body
    assert_equal ["að, to prevent; stefja manntjón, Fms. x. 418.",
                  "II. to address with a stave or stanza; þá stefjaði trollkona á hann ok spurði hverr " \
                  "þar fór (then follows the ditty), Edda 95."],
                 entry("stefja:1").body.lines(chomp: true)
  end

  # The gloss is the first italic span (the book's English) with at least
  # three letters, trailing punctuation trimmed; no italics → nil.
  def test_gloss_is_the_first_italic_english_span
    assert_equal "abbess", entry("abbadís").gloss
    assert_equal "to prevent", entry("stefja:1").gloss
    assert_nil entry("stefja:2").gloss, "the suffix entry prints no italic English"
  end

  def test_headword_folded_is_the_search_form
    assert_equal Nabu::Normalize.search_form("abbadís", language: "non"), entry("abbadís").headword_folded
  end

  # Regression (the offending bytes are in the fixture): upstream's Gýmir
  # definition carries U+0343 COMBINING GREEK KORONIS, which NFC maps to
  # U+0313 — normalized at this boundary, never stored raw.
  def test_non_nfc_upstream_text_is_normalized_at_the_boundary
    raw = JSON.parse(File.read(FIXTURE)).find { |r| r["word"] == "Gýmir" }["definitions"].first
    refute raw.unicode_normalized?(:nfc), "the fixture keeps upstream's non-NFC bytes"
    body = entry("Gýmir").body
    assert body.unicode_normalized?(:nfc)
    assert_includes body, "̓"
  end

  def test_malformed_json_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, "[{\"word\": ")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::DefinitionsJsonParser.new(language: "non").entries(path) }
    end
  end

  def test_a_record_without_a_word_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, '[{"definitions": ["x"]}]')
      assert_raises(Nabu::ParseError) { Nabu::Adapters::DefinitionsJsonParser.new(language: "non").entries(path) }
    end
  end
end
