# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# LzhCollection adapter tests: nk2028's Classical Chinese Collection (CC0),
# scoped to its distinct remainder — the Ming–Qing poetry collections the
# library holds nowhere else. The ten works already held (the Masters 白文
# texts, 李夢陽's 空同集) skip by rule. Fixture: three accepted files (one
# whole, two line-trimmed) beside two rejected-grain specimens.
class LzhCollectionTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("lzh-collection")

  def conformance_adapter = Nabu::Adapters::LzhCollection.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "lzh-collection"

  def adapter = Nabu::Adapters::LzhCollection.new

  def test_manifest_records_the_cc0_grant_and_the_provenance_gap
    manifest = adapter.manifest
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "CC0 1.0 Universal"
    assert_includes manifest.license, "no print edition is named"
    assert_equal "https://github.com/nk2028/lzh-collection", manifest.upstream_url
  end

  def test_discover_yields_the_accepted_poetry_collections_only
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:lzh-collection:史可法詩集 urn:nabu:lzh-collection:甌北集
                    urn:nabu:lzh-collection:夏完淳詩集], refs.map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_passages_are_the_non_blank_lines_with_the_poet_on_the_document
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    assert_equal [11, 5, 11], documents.map(&:size)
    shi = documents.first
    assert_equal "史可法詩集", shi.title
    assert_equal "lzh", shi.language
    assert_equal({ "author" => "史可法", "work" => "史可法詩集", "file" => "data/1_史可法詩集.txt" }, shi.metadata)
    passage = shi.passages[2]
    assert_equal "urn:nabu:lzh-collection:史可法詩集:3", passage.urn
    assert passage.text.start_with?("待理猶煩苦抱疴，公餘側枕柰如何。")
    assert_equal "趙翼", documents[1].metadata.fetch("author"), "甌北集 does not name its poet; the table does"
  end

  def test_juan_headings_ride_the_lines_they_govern
    oubei = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id.end_with?("甌北集") })
    assert_equal "卷一　起丙寅至戊辰", oubei.passages.first.text
    assert(oubei.passages.all? { |passage| passage.annotations == { "juan" => "卷一　起丙寅至戊辰" } })
  end

  def test_compatibility_ideographs_fold_to_their_unified_forms
    raw = File.readlines(File.join(FIXTURES, "data", "2_夏完淳詩集.txt"), chomp: true).last
    assert_includes raw, "\u{F9E7}", "upstream writes 裏 as the compatibility ideograph U+F9E7"
    xia = adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id.end_with?("夏完淳詩集") })
    last = xia.passages.last.text
    refute_includes last, "\u{F9E7}"
    assert_includes last, "佩君衷\u{88CF}衣（一作衣袖\u{88CF}）", "the interlinear variant note stays verbatim"
  end

  def test_held_works_skip_by_rule_with_their_witness_and_strays_are_loud
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(%r{data/老子白文\.txt: held elsewhere — kanripo KR5c0057}, skips.notes.join("\n"))
    assert_match(%r{data/2_李夢陽詩集\.txt: held elsewhere — kanripo KR4e0150 空同集}, skips.notes.join("\n"))
    Dir.mktmpdir do |work|
      FileUtils.cp_r(File.join(FIXTURES, "data"), work)
      File.write(File.join(work, "data", "新詩集.txt"), "新詩\n")
      stray = adapter.discovery_skips(work)
      assert_equal 1, stray.unrecognized
      refute(adapter.discover(work).any? { |ref| ref.id.end_with?("新詩集") })
    end
  end

  def test_the_three_tables_partition_upstreams_thirty_files
    works = Nabu::Adapters::LzhCollection::WORKS
    held = Nabu::Adapters::LzhCollection::HELD
    assert_equal 20, works.size
    assert_equal 10, held.size
    assert_empty works.keys & held.keys
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["lzh-collection"]
    refute_nil entry
    assert_equal Nabu::Adapters::LzhCollection, entry.adapter_class
    refute entry.wired
    assert_equal "manual", entry.sync_policy
  end

  def test_fetch_clones_the_repo_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-lzh-collection-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(FIXTURES, "data"), upstream)
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      lzh = adapter
      lzh.define_singleton_method(:repo_url) { upstream }
      report = lzh.fetch(File.join(root, "canonical"))
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 3, lzh.discover(File.join(root, "canonical")).count
    end
  end
end
