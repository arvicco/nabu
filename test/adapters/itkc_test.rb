# frozen_string_literal: true

require "test_helper"

# The itkc adapter (P78-7): 한국고전번역원 classical originals — the
# OPEN-LICENSED slice of the 한국고전종합DB (the P78-7 scout's channel
# map: 17 verified data.go.kr datasets, one complete work each; the
# rest of the 257-work GO family needs a 공공데이터 제공신청 — the
# owner letter path; the munjip stays parked per D47-c).
class ItkcTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("itkc")

  def adapter = Nabu::Adapters::Itkc.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "itkc"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant_and_the_honest_coverage
    manifest = adapter.manifest
    assert_equal "itkc", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "itkc-xml", manifest.parser_family
    assert_match(/한국고전번역원/, manifest.credit)
  end

  def test_the_dataset_registry_carries_the_seventeen_scouted_works
    assert_equal 17, Nabu::Adapters::Itkc::DATASETS.size
    pks = Nabu::Adapters::Itkc::DATASETS.map { |dataset| dataset[:pk] }
    assert_equal pks.uniq, pks
    assert_includes pks, "15022432", "고운당필기 — the first-registered work"
    assert_includes pks, "15141442", "국조보감"
    assert_includes pks, "15141472", "신증동국여지승람"
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_fascicle_never_the_sidecar
    assert_equal %w[urn:nabu:itkc:go-1295a-0010 urn:nabu:itkc:gp-1550a-0010],
                 adapter.discover(FIXTURES).map(&:id).sort,
                 "the suffix-less 서지 sidecars are metadata, not documents"
  end

  def test_parse_mints_article_passages_with_the_work_record_attached
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:itkc:gp-1550a-0010" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language, "hanmun — upstream's 언어 'coc' is ITKC-internal, not ISO"
    assert_equal "古芸堂筆記 卷一", document.title
    assert_equal "古芸堂筆記", document.metadata["work_title"]
    assert_equal "柳得恭", document.metadata["author"]
    assert_equal({ "not_before" => 1780, "not_after" => 1780, "raw" => "1780" },
                 document.metadata["date"], "the 원문간행년 original print year, never the modern edition")
    first = document.first
    assert_equal "urn:nabu:itkc:gp-1550a-0010:gp-1550a-0010-000-0010", first.urn
    assert_includes first.text, "內閣藏書《圖書集成》"
    assert_equal "圖書集成", first.annotations["title"]
    assert_equal %w[雜著類 其他類], first.annotations["genre_classes"]
    assert_equal "ITKC_BT_1550A_0010_000_0010", first.annotations["translation_ref"]
  end

  def test_the_go_work_parses_with_its_own_print_year
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:itkc:go-1295a-0010" }
    document = adapter.parse(ref)
    assert_equal 1895, document.metadata.dig("date", "not_before")
    assert_equal "國朝寶鑑", document.metadata["work_title"]
  end

  def test_fixture_apparatus_is_recognized
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  class FetchRig
    attr_reader :calls

    Rigged = Struct.new(:dir) do
      def prepare! = nil
      def doomed_paths = []
      def complete! = 7
      def cleanup! = nil
      def sha = "ef" * 32
    end

    def initialize = @calls = []

    def resolver
      lambda do |data_pk|
        @calls << [:resolve, data_pk]
        "https://www.data.go.kr/cmm/cmm/fileDownload.do?atchFileId=FILE_#{data_pk}&fileDetailSn=1"
      end
    end

    def zip_fetch_factory
      lambda do |url:, dir:, attic_dir:, progress:|
        _ = [url, attic_dir, progress]
        @calls << [:fetch, File.basename(dir)]
        Rigged.new(dir)
      end
    end
  end

  def test_fetch_resolves_all_seventeen_datasets_into_per_work_subdirs
    rig = FetchRig.new
    rigged = Nabu::Adapters::Itkc.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      resolves = rig.calls.count { |kind, _| kind == :resolve }
      fetches = rig.calls.count { |kind, _| kind == :fetch }
      assert_equal [17, 17], [resolves, fetches]
      assert_includes rig.calls, [:fetch, "15022432"], "each dataset owns its pk-named subdir"
    end
  end

  # --- registry -------------------------------------------------------------

  def test_registry_row_exists_on_the_korean_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["itkc"]
    refute_nil entry, "config/sources.yml must register itkc"
    assert_equal Nabu::Adapters::Itkc, entry.adapter_class
    assert entry.wired, "first sync owner-verified; flipped 2026-08-19 (r20 semantics)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "korean"
  end
end
