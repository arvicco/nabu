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

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "guangyun:廣韻.csv", refs.first.id
    adapter.parse(refs.first)
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

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["tshet-uinh"]
    refute_nil entry, "config/sources.yml must register tshet-uinh"
    assert_equal Nabu::Adapters::TshetUinh, entry.adapter_class
    refute entry.enabled, "enabled stays false until the owner-fired first sync"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
