# frozen_string_literal: true

require "test_helper"

# The sjw adapter (P78-2): 승정원일기 — the Daily Records of the Royal
# Secretariat, the library's largest single source by characters
# (242.25M on the web DB; the dump censused at 298 members / 2.44 GB).
# Same nikh-xml family as sillok; the scale rides the streaming parser.
class SjwTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("sjw")

  def adapter = Nabu::Adapters::Sjw.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "sjw"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant
    manifest = adapter.manifest
    assert_equal "sjw", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "nikh-xml", manifest.parser_family
    assert_match(/국사편찬위원회|National Institute of Korean History/, manifest.credit)
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_year_member_with_the_short_id
    assert_equal %w[urn:nabu:sjw:k00 urn:nabu:sjw:l04],
                 adapter.discover(FIXTURES).map(&:id).sort,
                 "2nd_K00.sjw.y.xml → k00 — the filename's reign-year key, suffix shed"
  end

  def test_the_dtd_is_recognized_and_the_fixture_manifest_is_the_one_stray
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  def test_parse_mints_hanmun_passages_per_article_with_the_weather_record
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sjw:k00" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language
    assert_equal "승정원일기 고종00년", document.title
    assert_equal %w[urn:nabu:sjw:k00:k00120130-00000
                    urn:nabu:sjw:k00:k00120130-00100
                    urn:nabu:sjw:k00:k00120130-00200],
                 document.map(&:urn),
                 "passage urn = the leaf's upstream id, redundant SJW- prefix shed, lowercased"
    roster = document.first
    assert_includes roster.text, "行都承旨 閔致庠 金吾待命。", "the 座目 duty roster with inline 근무현황 glosses"
    assert_equal "晴", roster.annotations["weather"],
                 "the day's weather record rides every article via the ancestor chain"
    assert_equal "座目", roster.annotations["title"]
  end

  def test_document_metadata_carries_the_structured_date_for_the_timeline
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sjw:l04" }
    date = adapter.parse(ref).metadata["date"]
    assert_equal({ "not_before" => 1910, "not_after" => 1910, "raw" => "1910" }, date)
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  class FetchRig
    attr_reader :calls

    Rigged = Struct.new(:dir) do
      def prepare! = nil
      def doomed_paths = []
      def complete! = 298
      def cleanup! = nil
      def sha = "cd" * 32
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
        @calls << [:fetch, dir]
        Rigged.new(dir)
      end
    end
  end

  def test_fetch_resolves_the_single_dataset_into_the_flat_workdir
    rig = FetchRig.new
    rigged = Nabu::Adapters::Sjw.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal "cd" * 32, report.sha
      assert_equal [[:resolve, "15064218"], [:fetch, workdir]], rig.calls
    end
  end

  # --- registry -------------------------------------------------------------

  def test_registry_row_exists_on_the_korean_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sjw"]
    refute_nil entry, "config/sources.yml must register sjw"
    assert_equal Nabu::Adapters::Sjw, entry.adapter_class
    assert entry.wired, "first sync owner-verified; flipped 2026-08-19 (r20 semantics)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "korean"
  end
end
