# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TshetUinh adapter tests (P32-3): nk2028/tshet-uinh-data's critical-edition
# 廣韻 (Kuangx Yonh) as the Middle Chinese rhyme-dictionary shelf — one
# entry per character × phonological position, with the repo's documented
# 校本 correction-annotation syntax parsed HONESTLY: corrections surface as
# annotations in bodies, transmitted forms preserved in key_raw, never
# silently fixed. Fixture rows are byte-verbatim upstream
# (test/fixtures/tshet-uinh/README.md).
class TshetUinhTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("tshet-uinh")

  def adapter
    Nabu::Adapters::TshetUinh.new
  end

  # --- manifest / capabilities ------------------------------------------------

  def test_manifest_records_the_cc0_dedication
    manifest = Nabu::Adapters::TshetUinh.manifest
    assert_equal "tshet-uinh", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/CC0 1\.0/, manifest.license)
    assert_match(/LICENSE/, manifest.license, "the in-repo LICENSE file is the witness, not the GitHub field")
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::TshetUinh.content_kind
  end

  # --- discover / parse -------------------------------------------------------

  def refs
    adapter.discover(FIXTURES).to_a
  end

  def parsed
    all = refs
    assert_equal 2, all.size
    assert_equal "guangyun:廣韻.csv", all.first.id
    adapter.parse(all.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_character_position_row
    document = parsed
    assert_equal "guangyun", document.slug
    assert_equal "ltc", document.language
    assert_equal 12, document.count
    assert_equal document.count, document.entries.map(&:entry_id).uniq.size,
                 "小韻號.小韻字號 is unique per row"
  end

  def test_plain_entry_carries_position_fanqie_and_definition
    dong = entries_by_id.fetch("1.1")
    assert_equal "東", dong.headword
    assert_match(/\A春方也/, dong.gloss, "釋義 is the gloss, verbatim")
    assert_match(/音韻地位：端一東平/, dong.body)
    assert_match(/韻目：東/, dong.body)
    assert_match(/反切：德紅/, dong.body)
  end

  def test_shiyi_reference_marks_ride_the_body
    jiong = entries_by_id.fetch("1.2")
    assert_equal "菄", jiong.headword
    assert_match(/釋義參照：上/, jiong.body, "the 「同上」 pointer is preserved, not resolved")
  end

  def test_corrected_headword_keeps_the_transmitted_form_as_annotation
    row = entries_by_id.fetch("2.43")
    assert_equal "𪔜", row.headword, "the 校本 correction is the headword"
    assert_equal "𪔝〈𪔜〉", row.key_raw, "the raw cell survives verbatim"
    assert_match(/校訛字：底本作「𪔝」/, row.body, "the correction is an annotation, never silent")
  end

  def test_supplemented_headword_is_flagged_not_silently_added
    row = entries_by_id.fetch("961.1a1")
    assert_equal "嬹", row.headword
    assert_equal "［嬹］", row.key_raw
    assert_match(/應補字/, row.body, "澤存堂本 lacks the character; the supplement is flagged")
  end

  def test_deletion_marked_headword_still_mints_with_the_flag
    row = entries_by_id.fetch("318.9")
    assert_equal "𪈥", row.headword
    assert_match(/應刪字/, row.body)
    assert_match(/字頭說明：澤存堂本衍字/, row.body, "the upstream editorial note rides verbatim")
  end

  def test_fanqie_annotations_stay_verbatim
    yao = entries_by_id.fetch("1692a.1")
    assert_equal "鷕", yao.headword
    assert_match(/反切：以沼｟小｠〈水〉/, yao.body, "the compound 校本 annotation is untouched")
  end

  def test_zhiyin_rows_carry_the_direct_reading_instead_of_fanqie
    zheng = entries_by_id.fetch("1919.1")
    assert_equal "拯", zheng.headword
    refute_match(/反切：/, zheng.body, "the 反切-less row omits the line honestly")
    assert_match(/直音：蒸上聲/, zheng.body)
  end

  def test_empty_shiyi_yields_nil_gloss
    sheng = entries_by_id.fetch("1919.2")
    assert_nil sheng.gloss
    assert_match(/釋義參照：下/, sheng.body)
  end

  def test_headwords_fold_for_lookup
    dong = entries_by_id.fetch("1.1")
    assert_equal Nabu::Normalize.search_form("東", language: "ltc"), dong.headword_folded
  end

  # --- the 王三 second shelf (P88-R4) -----------------------------------------

  def wangsan_parsed
    all = refs
    assert_equal ["guangyun:廣韻.csv", "wangsan:王三.csv"], all.map(&:id),
                 "discover yields both shelves, sorted"
    adapter.parse(all.last)
  end

  def wangsan_by_id
    wangsan_parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_wangsan_parses_as_its_own_dictionary
    document = wangsan_parsed
    assert_equal "wangsan", document.slug
    assert_equal "ltc", document.language
    assert_match(/王仁昫/, document.title)
    assert_equal 10, document.count, "11 fixture rows − 1 headword-less 待校 slot"
    assert_equal document.count, document.entries.map(&:entry_id).uniq.size,
                 "小韻號.小韻內字序 is the unique pair (小韻號.字號 is NOT unique upstream)"
  end

  def test_wangsan_plain_entry_carries_position_pinyin_and_locus
    dong = wangsan_by_id.fetch("1.1")
    assert_equal "東", dong.headword
    assert_equal "徳紅反。木方。二。", dong.gloss, "釋義 verbatim (upstream writes 徳, not 德, here)"
    assert_match(/音韻地位：端一東平/, dong.body)
    assert_match(/切韻拼音：toung/, dong.body)
    assert_match(/韻目：東/, dong.body)
    assert_match(/小韻首字：東/, dong.body)
    assert_match(/反切：德紅反/, dong.body)
    assert_match(/底本位置：頁2 行11 字1/, dong.body)
  end

  def test_wangsan_supplemented_headword_is_flagged_not_silently_added
    row = wangsan_by_id.fetch("23.7.1")
    assert_equal "𩦺", row.headword
    assert_equal "［𩦺］", row.key_raw
    assert_match(/應補字/, row.body, "the ［X］ shape with the '.1' ordinal suffix, flagged like guangyun's a1")
  end

  def test_wangsan_corrected_headword_keeps_the_transmitted_form_as_annotation
    row = wangsan_by_id.fetch("539.3")
    assert_equal "𥮒", row.headword, "the correction verdict is the headword"
    assert_equal "箈〈𥮒〉", row.key_raw
    assert_match(/校訛字：底本作「箈」/, row.body)
    assert_match(/釋義：籠。又子田反。［亦作］⿱竹㵶〈𥷰〉。/, row.body,
                 "annotation brackets inside 釋義 ride verbatim, never applied")
  end

  def test_wangsan_empty_supplement_slot_rides_verbatim
    row = wangsan_by_id.fetch("164.6.1")
    assert_equal "［］", row.headword, "an unrecovered supplied slot — kept raw, never interpreted"
    assert_equal "［］", row.key_raw
    assert_equal "［］", row.gloss
  end

  def test_wangsan_undocumented_bracket_shape_rides_verbatim
    row = wangsan_by_id.fetch("804.2")
    assert_equal "【佯】", row.headword, "【】 is undocumented upstream — verbatim, not invented syntax"
    assert_nil row.gloss, "empty 釋義 → nil gloss"
  end

  def test_wangsan_fanqie_less_row_omits_the_line_honestly
    row = wangsan_by_id.fetch("312.1")
    assert_equal "絓", row.headword
    refute_match(/反切：/, row.body)
    assert_equal "［。］𢙣𢇁。", row.gloss, "釋義 verbatim, brackets included"
  end

  def test_wangsan_headword_less_rows_are_skipped_censused
    entries = wangsan_by_id
    refute entries.key?("45.9"), "the 5 headword-less 待校 slots cannot mint (no key) — censused skip"
    assert_equal 10, entries.size
  end

  def test_wangsan_headwords_fold_for_lookup
    dong = wangsan_by_id.fetch("1.1")
    assert_equal Nabu::Normalize.search_form("東", language: "ltc"), dong.headword_folded
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["tshet-uinh"]
    refute_nil entry, "config/sources.yml must register tshet-uinh"
    assert_equal Nabu::Adapters::TshetUinh, entry.adapter_class
    assert entry.wired, "live (owner order 2026-07-20: P32+P33 sources flipped, post-P34 gate)"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
