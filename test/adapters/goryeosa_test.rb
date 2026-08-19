# frozen_string_literal: true

require "test_helper"

# The goryeosa adapter (P78-3): 고려사 원문 — the History of Goryeo
# (1451, 정인지 et al.) in the original hanmun, NIKH via data.go.kr
# dataset 15053637. Second member of the nikh-xml family on the korean
# axis; single-dataset sibling of the sillok mold.
class GoryeosaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("goryeosa")

  def adapter = Nabu::Adapters::Goryeosa.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "goryeosa"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant
    manifest = adapter.manifest
    assert_equal "goryeosa", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution, credit the institute"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "nikh-xml", manifest.parser_family
    assert_match(/국사편찬위원회|National Institute of Korean History/, manifest.credit)
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_member_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:goryeosa:kr_000 urn:nabu:goryeosa:kr_069 urn:nabu:goryeosa:kr_118],
                 refs.map(&:id).sort
  end

  def test_the_dtd_is_recognized_never_a_stray
    skips = adapter.discovery_skips(FIXTURES)
    # The fixture dir's manifest.yml is the ONE counted stray (the
    # achemenet precedent — it pins that the census actually counts);
    # history.dtd and the README are recognized.
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  def test_parse_mints_hanmun_passages_per_leaf_section
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa:kr_069" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language, "hanmun = Literary Chinese as read in Korea (the kanripo precedent)"
    assert_equal "志 卷第二十三", document.title
    assert_equal %w[urn:nabu:goryeosa:kr_069:kr_069_0010_0010_0010_0010
                    urn:nabu:goryeosa:kr_069:kr_069_0010_0010_0010_0020
                    urn:nabu:goryeosa:kr_069:kr_069_0010_0010_0010_0060],
                 document.map(&:urn)
    first = document.first
    assert_includes first.text, "上元燃燈會儀"
    assert_includes first.text, "小會日坐殿"
  end

  def test_the_item_wrapped_front_matter_member_parses_whole
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa:kr_000" }
    document = adapter.parse(ref)
    # kr_000 is the zip's ONE <item>-rooted member: four sibling level1
    # sections (진고려사전, 고려세계 ×2, 범례); all of them leaf. The
    # upstream $-carrying section ids ride the urns verbatim.
    assert_equal 13, document.size
    assert_equal "urn:nabu:goryeosa:kr_000:kr_$s01", document.first.urn
    assert_equal "『고려사』를 찬진하는 전", document.title
    assert_includes document.first.text, "進高麗史箋"
  end

  def test_document_metadata_claims_no_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa:kr_069" }
    document = adapter.parse(ref)
    # P78-3 census: goryeosa volume fronts carry NO dateOccured (no 서기
    # line exists anywhere in the zip) — the document honestly claims
    # nothing; the leaf-grain 음/양 machine dates ride annotations.
    assert_nil document.metadata["date"]
    assert_equal({ "volume" => "kr_069" }, document.metadata)
  end

  def test_passage_annotations_carry_the_editorial_title_and_the_lunar_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa:kr_069" }
    document = adapter.parse(ref)
    dated = document.to_a.last
    assert_equal "문종이 한식인 관계로 날짜를 변경하여 연등회를 열다", dated.annotations["title"]
    assert_equal "1048-02-16L0", dated.annotations["date"], "the lunar 음 machine date — no 서기 exists upstream"
    undated = document.first
    assert_nil undated.annotations["date"], "an undated ritual prescription claims nothing"
  end

  def test_an_undated_biography_member_leafs_at_level4
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:goryeosa:kr_118" }
    document = adapter.parse(ref)
    assert_equal "列傳 卷第三十一", document.title
    assert_equal 2, document.size
    assert_equal "조준의 관력과 성향", document.first.annotations["title"]
    assert_nil document.first.annotations["date"], "列傳 members carry no dates at all"
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  # The single-dataset choreography: resolve the CURRENT atchFileId for
  # dataset 15053637 (the id bumps on upstream file replacement — the
  # resolution is the contract), then one ZipFetch into the FLAT
  # workdir, attic at workdir/.attic.
  class FetchRig
    attr_reader :calls

    Rigged = Struct.new(:dir) do
      def prepare! = nil
      def doomed_paths = []
      def complete! = 3
      def cleanup! = nil
      def sha = "ab" * 32
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
    rigged = Nabu::Adapters::Goryeosa.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal "ab" * 32, report.sha, "one dataset, one pin"
      assert_equal ["data.go.kr 15053637"], report.notes
      assert_equal [[:resolve, "15053637"], [:fetch, workdir, File.join(workdir, ".attic")]],
                   rig.calls
    end
  end

  def test_discover_walks_a_flat_real_workdir
    Dir.mktmpdir do |workdir|
      FileUtils.cp(File.join(FIXTURES, "kr_069.xml"), workdir)
      FileUtils.cp(File.join(FIXTURES, "history.dtd"), workdir)
      assert_equal %w[urn:nabu:goryeosa:kr_069], adapter.discover(workdir).map(&:id)
    end
  end
end
