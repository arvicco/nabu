# frozen_string_literal: true

require "test_helper"

# The Digital Pāḷi Dictionary text-export parser family (dpd-db release
# dpd-txt.zip), run against the trimmed-real dpd fixture.
class DpdTxtParserTest < Minitest::Test
  def entries
    @entries ||= Nabu::Adapters::DpdTxtParser.new.entries(File.join(Nabu::TestSupport.fixtures("dpd"), "dpd.txt"))
  end

  def entry(id) = entries.find { |e| e.entry_id == id }

  def test_entries_are_keyed_by_the_dpd_id_in_file_order
    assert_equal %w[1 7 72479 71509], entries.map(&:entry_id)
  end

  def test_headword_drops_the_homonym_number_and_key_raw_keeps_it
    a = entry("1")
    assert_equal "a", a.headword
    assert_equal "a 1.1", a.key_raw
  end

  def test_gloss_is_the_first_meaning_without_its_register_label
    assert_equal "letter a", entry("1").gloss
    assert_equal "smooth", entry("7").gloss
    assert_equal "with smooth and pure limbs", entry("72479").gloss
  end

  def test_body_keeps_the_head_line_and_every_field
    lines = entry("7").body.lines(chomp: true)
    assert_equal "akakkasa, adj. smooth; tender; not harsh; not rough ✔", lines[0]
    assert_includes lines, "Sanskrit: akarkaśa (na + karkaśa)"
    assert_includes lines, "Construction: na > a + kakkasa"
    refute(lines.any? { |l| l.start_with?("ID:") }, "the id is the entry id, not body text")
  end

  def test_part_of_speech_is_mined_and_root_only_where_printed
    assert_equal({ "pos" => "adj" }, entry("7").annotations)
    assert_equal({ "pos" => "cs" }, entry("71509").annotations)
  end

  def test_output_is_nfc_and_folded
    entries.each do |e|
      assert e.body.unicode_normalized?(:nfc)
      assert_equal Nabu::Normalize.search_form(e.headword, language: "pli"), e.headword_folded
    end
  end

  def test_a_block_without_an_id_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dpd.txt")
      File.write(path, "a 1.1, letter. letter a ✔\n  IPA: /ə/\n")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::DpdTxtParser.new.entries(path) }
    end
  end
end
