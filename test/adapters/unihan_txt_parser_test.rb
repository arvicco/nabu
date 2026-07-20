# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The unihan-txt parser family (P32-4): per-field lines folded into one
# entry per codepoint, the carried-field census verdict enforced (a
# codepoint with only censused-out fields mints nothing), numeric codepoint
# order (the upstream ASCII sort interleaves plane 2 before the BMP).
class UnihanTxtParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("unihan")

  def entries
    @entries ||= Nabu::Adapters::UnihanTxtParser.new.entries(
      File.join(FIXTURES, "Unihan_Readings.txt"),
      variants_path: File.join(FIXTURES, "Unihan_Variants.txt")
    )
  end

  def by_id
    @by_id ||= entries.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_one_entry_per_codepoint_with_a_carried_field_in_numeric_order
    assert_equal %w[U+340A U+340B U+349A U+4E00 U+4E9A U+4E9C U+4E9E U+4EBA U+4F53
                    U+5929 U+611B U+68C4 U+7231 U+9AD4 U+9B75 U+2000B],
                 entries.map(&:entry_id),
                 "numeric codepoint order — plane 2 (U+2000B) sorts LAST, " \
                 "though the upstream ASCII sort puts it before U+3400"
  end

  def test_a_codepoint_with_only_censused_out_fields_mints_nothing
    refute_includes by_id.keys, "U+3403",
                    "U+3403 carries only kCantonese (censused out) and must not mint"
  end

  def test_the_one_entry_carries_readings_definition_and_historical_strata
    one = by_id.fetch("U+4E00")
    assert_equal "一", one.headword
    assert_equal "U+4E00", one.key_raw
    assert_equal "zho", one.language
    assert_equal "one", one.gloss, "first ;-sense of kDefinition"
    assert_includes one.body, "kDefinition: one; a, an; alone"
    assert_includes one.body, "kFanqie: 於悉", "the Middle Chinese fanqie stratum rides"
    assert_includes one.body, "kJapanese: イチ イツ ひと ひとつ"
    assert_includes one.body, "kJapaneseOn: ICHI ITSU"
    assert_includes one.body, "kMandarin: yī"
    assert_match(/^kTang: /, one.body, "the Tang-era reading stratum rides")
  end

  def test_variant_links_ride_verbatim
    assert_includes by_id.fetch("U+4E9E").body, "kSimplifiedVariant: U+4E9A"
    assert_includes by_id.fetch("U+4E9A").body, "kTraditionalVariant: U+4E9E"
  end

  def test_a_variants_only_codepoint_mints_with_the_variant_line_as_body
    spoof = by_id.fetch("U+340A")
    assert_equal "kSpoofingVariant: U+340B", spoof.body
    assert_nil spoof.gloss
  end

  def test_plane_two_codepoints_mint_their_supplementary_character
    entry = by_id.fetch("U+2000B")
    assert_equal "𠀋", entry.headword
    assert_equal "kJapanese: ジョウ たけ", entry.body
  end

  def test_output_is_nfc_and_folded_headwords_are_present
    entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.headword_folded
    end
  end

  def test_malformed_codepoint_key_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "Unihan_Readings.txt")
      File.write(path, "NOT-A-CP\tkDefinition\tbroken\n")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::UnihanTxtParser.new.entries(path) }
    end
  end
end
