# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Buckwalter — the extended Buckwalter transliteration the
# Quranic Arabic Corpus writes its forms in, rendered one-to-one back into
# the Arabic letters and signs it encodes. Used ONLY to mint the
# quranic-corpus search form; the stored text never passes through it.
class BuckwalterTest < Minitest::Test
  BW = Nabu::Adapters::Buckwalter

  def test_every_inventory_character_of_the_corpus_maps_to_one_codepoint
    # The FORM column's whole character inventory (live-file census:
    # 57 distinct characters besides the space; the standard | is mapped
    # too though the corpus spells alef-madda A^).
    inventory = "'>&<}AbptvjHxd*rzs$SDTZEg_fqklmnhwYyFNKauio~^#`{:@\"[;,.!-+%]|"
    inventory.each_char do |char|
      arabic = BW.to_arabic(char)
      assert_equal 1, arabic.length, "#{char.inspect} renders to exactly one codepoint"
      assert_includes 0x0600..0x06FF, arabic.ord, "#{char.inspect} renders into the Arabic block"
    end
    assert_equal inventory.length, inventory.chars.map { |char| BW.to_arabic(char) }.uniq.size,
                 "one-to-one: no two Buckwalter characters share a rendering"
  end

  def test_the_emphatics_and_their_plain_counterparts_stay_distinct
    { "H" => "ح", "h" => "ه", "S" => "ص", "s" => "س", "D" => "ض", "d" => "د", "T" => "ط", "t" => "ت",
      "Z" => "ظ", "z" => "ز", "A" => "ا", "a" => "َ" }.each do |bw, arabic|
      assert_equal arabic, BW.to_arabic(bw), bw
    end
  end

  def test_real_verses_render_letter_for_letter
    # Q 112:1 and 1:7's last word, the corpus's own forms, in upstream's
    # character order (no normalization — that is search_form's step).
    assert_equal "قُلْ هُوَ ٱللَّهُ " \
                 "أَحَدٌ",
                 BW.to_arabic("qulo huwa {ll~ahu >aHadN")
    assert_equal "ٱلضَّآلِّينَ",
                 BW.to_arabic("{lD~aA^l~iyna")
  end

  def test_anything_outside_the_inventory_passes_through
    assert_equal "ـ 12 é", BW.to_arabic("_ 12 é")
  end
end
