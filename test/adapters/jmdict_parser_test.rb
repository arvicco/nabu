# frozen_string_literal: true

require "test_helper"

# The edrdg-xml family, JMdict half (P32-4): one entry per <entry> keyed by
# ent_seq, kanji-first headwords with kana-only fallback, and the
# internal-DTD entity expansion (&n; → prose) via the NOENT reader.
class JmdictParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("edrdg")

  def entries
    @entries ||= File.open(File.join(FIXTURES, "JMdict_e.xml")) do |io|
      Nabu::Adapters::JmdictParser.new.entries(io)
    end
  end

  def by_id
    @by_id ||= entries.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_one_entry_per_ent_seq_in_file_order
    assert_equal %w[1000000 1150410 1318970 1358280 1366410 1438210].sort,
                 entries.map(&:entry_id).sort
    assert_equal entries.map(&:entry_id).uniq, entries.map(&:entry_id)
  end

  def test_kanji_first_headword_with_first_gloss
    love = by_id.fetch("1150410")
    assert_equal "愛", love.headword
    assert_equal "jpn", love.language
    assert_equal "love", love.gloss
    assert_match(/^kanji: 愛/, love.body)
    assert_match(/^readings: /, love.body)
  end

  def test_kana_only_entries_fall_back_to_the_first_reading
    mark = by_id.fetch("1000000")
    assert_equal "ヽ", mark.headword
    assert_equal "repetition mark in katakana", mark.gloss
  end

  def test_pos_entities_expand_to_prose_never_raw_entity_names
    mark = by_id.fetch("1000000")
    assert_includes mark.body, "(unclassified)",
                    "&unc; must expand through the internal DTD (NOENT)"
    entries.each { |entry| refute_match(/&[a-z-]+;/, entry.body) }
  end

  def test_senses_are_numbered_with_their_glosses
    taberu = by_id.fetch("1358280")
    assert_match(/^1\. /, taberu.body)
    assert_includes taberu.body, "eat"
  end

  def test_output_is_nfc
    entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end
end
