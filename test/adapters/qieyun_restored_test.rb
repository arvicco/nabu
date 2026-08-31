# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# QieyunRestored adapter tests (P88-A2): nk2028/qieyun-restored — the
# *Qieyun* 切韻 itself (Lu Fayan, 601 CE), the parent rhyme dictionary the
# held 廣韻 (tshet-uinh) expanded, as restored by Fujita Takumi (2017
# thesis / 2023 monograph) and extracted upstream from the thesis PDF's
# appendix table. One entry per character row; the thesis-table (頁, 行)
# position is the stable entry id (verified unique ×11,158; 小韻 numbering
# RESTARTS per 韻目 — the fixture trim pins the 冬 restart). Fixture rows
# are byte-verbatim upstream (test/fixtures/qieyun-restored/README.md).
class QieyunRestoredTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("qieyun-restored")

  def adapter
    Nabu::Adapters::QieyunRestored.new
  end

  # --- manifest / capabilities ----------------------------------------------

  def test_manifest_records_the_mit_grant
    manifest = Nabu::Adapters::QieyunRestored.manifest
    assert_equal "qieyun-restored", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/MIT/, manifest.license)
    assert_match(/藤田拓海|Fujita/, manifest.license, "the restoration's scholar rides the credit line")
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::QieyunRestored.content_kind
  end

  # --- discover / parse -----------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "qieyun:切韻 藤田拓海復元.csv", refs.first.id
    adapter.parse(refs.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_character_row
    document = parsed
    assert_equal "qieyun", document.slug
    assert_equal "ltc", document.language
    assert_equal 165, document.count
    assert_equal document.count, document.entries.map(&:entry_id).uniq.size,
                 "頁.行 is unique per row (verified ×11,158 upstream)"
  end

  def test_entry_carries_position_rime_and_definition
    dong = entries_by_id.fetch("1.1")
    assert_equal "東", dong.headword
    assert_equal "徳紅反.二.", dong.gloss, "釋義 is the gloss, verbatim — fanqie and count included"
    assert_match(/音韻地位：端一東平/, dong.body)
    assert_match(/韻目：東/, dong.body)
    assert_match(/小韻：1（音類 端1，序数 1）/, dong.body)
  end

  def test_the_xiaoyun_numbering_restart_across_rime_headings_stays_unambiguous
    dong_winter = entries_by_id.fetch("5.12")
    assert_equal "冬", dong_winter.headword
    assert_match(/韻目：冬/, dong_winter.body)
    assert_match(/小韻：1（音類 端1，序数 244）/, dong_winter.body,
                 "小韻 1 recurs in 冬 — the 頁.行 id keeps entries distinct across the restart")
  end

  def test_headwords_fold_for_lookup
    dong = entries_by_id.fetch("1.1")
    refute_nil dong.headword_folded
    assert_equal Nabu::Normalize.search_form("東", language: "ltc"), dong.headword_folded
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["qieyun-restored"]
    refute_nil entry, "config/sources.yml must register qieyun-restored"
    assert_equal Nabu::Adapters::QieyunRestored, entry.adapter_class
    assert entry.wired, "live (first sync verified + owner sign-off 2026-08-30; flipped 2026-08-31)"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
