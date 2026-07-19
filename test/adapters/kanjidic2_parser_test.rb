# frozen_string_literal: true

require "test_helper"

# The edrdg-xml family, KANJIDIC2 half (P32-4): one entry per <character>,
# "U+XXXX" ids minted through one upcase (the verified upstream quirk: BMP
# ucs values are lowercase hex, plane-2 values UPPERCASE), readings split
# by r_type, English-only meanings.
class Kanjidic2ParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("edrdg")

  def entries
    @entries ||= File.open(File.join(FIXTURES, "kanjidic2.xml")) do |io|
      Nabu::Adapters::Kanjidic2Parser.new.entries(io)
    end
  end

  def by_id
    @by_id ||= entries.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_one_entry_per_character_with_codepoint_ids
    assert_equal 10, entries.size
    assert_includes by_id.keys, "U+4E9C"
    assert_equal entries.map(&:entry_id).uniq, entries.map(&:entry_id)
  end

  def test_plane_two_ucs_hex_case_quirk_is_normalized_into_one_key_shape
    assert_includes by_id.keys, "U+2000B",
                    "plane-2 ucs values are UPPERCASE hex upstream and must join the same key space"
    assert_equal "𠀋", by_id.fetch("U+2000B").headword
  end

  def test_the_asia_kanji_carries_readings_meanings_and_misc_facts
    asia = by_id.fetch("U+4E9C")
    assert_equal "亜", asia.headword
    assert_equal "亜", asia.key_raw
    assert_equal "jpn", asia.language
    assert_equal "Asia", asia.gloss
    assert_match(/^on: /, asia.body)
    assert_includes asia.body, "ア"
    assert_match(/^kun: /, asia.body)
    assert_match(/^meaning: /, asia.body)
    assert_match(/stroke_count 7/, asia.body)
  end

  def test_non_english_meanings_stay_upstream
    entries.each do |entry|
      refute_match(/m_lang/, entry.body)
    end
  end

  def test_output_is_nfc
    entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end
end
