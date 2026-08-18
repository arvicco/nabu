# frozen_string_literal: true

require "test_helper"

# The goryeosa-jeoryo adapter (P78-3): 고려사절요 원문 — the Essentials
# of Goryeo History (1452, 김종서 et al., the chronological digest
# sibling of the goryeosa) in the original hanmun, NIKH via data.go.kr
# dataset 15115521. nikh-xml family, korean axis.
class GoryeosaJeoryoTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("goryeosa-jeoryo")

  def adapter = Nabu::Adapters::GoryeosaJeoryo.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "goryeosa-jeoryo"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant
    manifest = adapter.manifest
    assert_equal "goryeosa-jeoryo", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution, credit the institute"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "nikh-xml", manifest.parser_family
    assert_match(/국사편찬위원회|National Institute of Korean History/, manifest.credit)
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_member_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:goryeosa-jeoryo:kj_000 urn:nabu:goryeosa-jeoryo:kj_033],
                 refs.map(&:id).sort
  end

  def test_the_dtd_is_recognized_never_a_stray
    skips = adapter.discovery_skips(FIXTURES)
    # manifest.yml is the ONE counted stray (the achemenet precedent).
    # Census note: the LIVE zip also carries one stray .jpg with a
    # CP949-mojibake name — the census counts it loudly, never parses it.
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  def test_parse_mints_hanmun_passages_per_leaf_article
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa-jeoryo:kj_033" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language, "hanmun = Literary Chinese as read in Korea (the kanripo precedent)"
    assert_equal "高麗史節要 卷33", document.title
    assert_equal %w[urn:nabu:goryeosa-jeoryo:kj_033:kj_033_0010_0010_0010_0010
                    urn:nabu:goryeosa-jeoryo:kj_033:kj_033_0010_0010_0010_0020
                    urn:nabu:goryeosa-jeoryo:kj_033:kj_033_0010_0010_0010_0030
                    urn:nabu:goryeosa-jeoryo:kj_033:kj_033_0010_0010_0010_0040],
                 document.map(&:urn)
    assert_includes document.first.text, "高麗史節要卷之三十三"
    assert_includes document.first.text, "戊辰 辛禑十四年"
  end

  def test_the_item_wrapped_front_matter_member_parses_whole
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa-jeoryo:kj_000" }
    document = adapter.parse(ref)
    # kj_000 is the zip's ONE <item>-rooted member: four sibling level1
    # sections (진전/범례/수사관/목록), each a leaf; $-carrying ids ride
    # the urns verbatim.
    assert_equal %w[kj_$s01 kj_$s02 kj_$s03 kj_$s04],
                 document.map { |passage| passage.urn.split(":").last }.to_a
    assert_equal "進高麗史節要箋", document.title
    assert_includes document.first.text, "謹將新撰高麗史節要"
  end

  def test_document_metadata_claims_no_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa-jeoryo:kj_033" }
    document = adapter.parse(ref)
    # P78-3 census: the root level1 front carries coveragePeriod prose
    # but NO dateOccured (the bare machine year sits two levels down, on
    # the level3 year front) — the document claims nothing; the
    # per-article 음/양 machine dates ride annotations.
    assert_nil document.metadata["date"]
    assert_equal({ "volume" => "kj_033" }, document.metadata)
  end

  def test_passage_annotations_carry_the_editorial_title_and_the_lunar_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa-jeoryo:kj_033" }
    annotations = adapter.parse(ref).first.annotations
    assert_equal "염흥방이 조반의 추국을 주도하다가 순군에 갇히다", annotations["title"]
    assert_equal "1388-01-01L0", annotations["date"], "the lunar 음 machine date — no 서기 exists upstream"
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  class FetchRig
    attr_reader :calls

    Rigged = Struct.new(:dir) do
      def prepare! = nil
      def doomed_paths = []
      def complete! = 3
      def cleanup! = nil
      def sha = "cd" * 32
    end

    def initialize
      @calls = []
    end

    def resolver
      lambda do |pk|
        @calls << [:resolve, pk]
        "https://www.data.go.kr/cmm/cmm/fileDownload.do?atchFileId=FILE_#{pk}&fileDetailSn=1"
      end
    end

    def zip_fetch_factory
      lambda do |url:, dir:, attic_dir:, progress:|
        _ = [url, progress]
        @calls << [:fetch, dir, attic_dir]
        Rigged.new(dir)
      end
    end
  end

  def test_fetch_resolves_and_fetches_the_one_dataset_into_the_flat_workdir
    rig = FetchRig.new
    rigged = Nabu::Adapters::GoryeosaJeoryo.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal "cd" * 32, report.sha, "one dataset, one pin"
      assert_equal ["data.go.kr 15115521"], report.notes
      assert_equal [[:resolve, "15115521"], [:fetch, workdir, File.join(workdir, ".attic")]],
                   rig.calls
    end
  end

  def test_discover_walks_a_flat_real_workdir
    Dir.mktmpdir do |workdir|
      FileUtils.cp(File.join(FIXTURES, "kj_033.xml"), workdir)
      FileUtils.cp(File.join(FIXTURES, "history.dtd"), workdir)
      assert_equal %w[urn:nabu:goryeosa-jeoryo:kj_033], adapter.discover(workdir).map(&:id)
    end
  end
end
