# frozen_string_literal: true

require "test_helper"

# The Mahan Kosh JSON parser family (redroyals/mahan-kosh-multilingual,
# the Gurmukhi lane), run against the trimmed-real mahan-kosh fixture.
class MahanKoshJsonParserTest < Minitest::Test
  def entries
    dir = Nabu::TestSupport.fixtures("mahan-kosh")
    @entries ||= Nabu::Adapters::MahanKoshJsonParser.new.entries(
      core_path: File.join(dir, "core", "core.json"), gurmukhi_path: File.join(dir, "gurmukhi", "gurmukhi.json")
    )
  end

  def entry(id) = entries.find { |e| e.entry_id == id }

  def test_live_grid_rows_become_entries_and_excluded_rows_do_not
    assert_equal %w[1-37-0 1-37-13 1-37-21], entries.map(&:entry_id)
  end

  def test_the_gurmukhi_body_reads_line_by_line_with_its_print_locator
    u = entry("1-37-0")
    assert_equal "ਉ", u.headword
    lines = u.body.lines(chomp: true)
    assert lines[0].start_with?(Nabu::Normalize.nfc("ਸੰ. उ. ਸੰਗ੍ਯਾ- ਬ੍ਰਹਮਾ। ੨. ")), lines[0]
    assert_includes lines[0], "ਵਿਸ\u{F032}ਨੁ", "upstream's private-use legacy-font residue is carried verbatim"
    assert lines[1].start_with?(Nabu::Normalize.nfc("੫. ਸੰਬੋਧਨ।")), "upstream's # marks the print's paragraph break"
    assert_equal "Mahan Kosh vol. 1, p. 37", lines.last
    assert_equal Nabu::Normalize.nfc("ਸੰ. उ. ਸੰਗ੍ਯਾ- ਬ੍ਰਹਮਾ"), u.gloss
  end

  def test_the_books_own_lemma_heads_the_entry_when_it_differs_from_the_grid
    camel = entry("1-37-13")
    assert_equal "ਉਸਟ", camel.headword
    assert_equal "ਉਸਟਰੂ ਨੇਨ", camel.key_raw
  end

  def test_a_row_without_a_recovered_body_keeps_its_locator_and_no_gloss
    bare = entry("1-37-21")
    assert_equal "Mahan Kosh vol. 1, p. 37", bare.body
    assert_nil bare.gloss
    assert_equal({ "volume" => 1, "page" => 37 }, bare.annotations)
  end

  def test_output_is_nfc_and_folded
    entries.each do |e|
      assert e.body.unicode_normalized?(:nfc)
      assert e.headword.unicode_normalized?(:nfc)
      assert_equal Nabu::Normalize.search_form(e.headword, language: "pan"), e.headword_folded
    end
  end
end
