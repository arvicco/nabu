# frozen_string_literal: true

require "test_helper"

# The sillok adapter (P78-1): 조선왕조실록 원문 — the Veritable Records
# of the Joseon Dynasty, hanmun original text, NIKH via data.go.kr
# datasets 15053647 (Taejo–Cheoljong) + 15053646 (Gojong/Sunjong).
# Founds the nikh-xml family and the korean axis.
class SillokTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("sillok")

  def adapter = Nabu::Adapters::Sillok.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "sillok"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant
    manifest = adapter.manifest
    assert_equal "sillok", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution, credit the institute"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "nikh-xml", manifest.parser_family
    assert_match(/국사편찬위원회|National Institute of Korean History/, manifest.credit)
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_volume_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:sillok:waa_200 urn:nabu:sillok:wqa_000 urn:nabu:sillok:wzc_121],
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

  def test_parse_mints_hanmun_passages_per_leaf_article
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sillok:wzc_121" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language, "hanmun = Literary Chinese as read in Korea (the kanripo precedent)"
    assert_equal "純宗[附錄] 二十一年", document.title
    assert_equal %w[urn:nabu:sillok:wzc_121:wzc_12105003_001 urn:nabu:sillok:wzc_121:wzc_12107006_001],
                 document.map(&:urn)
    first = document.first
    assert_includes first.text, "純明皇后徽號望"
    assert_includes first.text, "【陰曆戊辰三月十四日】", "원주 notes ride inline, verbatim"
  end

  def test_document_metadata_carries_the_structured_date_for_the_timeline
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sillok:wzc_121" }
    date = adapter.parse(ref).metadata["date"]
    assert_equal({ "not_before" => 1928, "not_after" => 1928, "raw" => "1928" }, date,
                 "the :structured MetadataDates shape — one year envelope per volume")
  end

  def test_an_undated_appendix_volume_carries_no_date_claim
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sillok:waa_200" }
    document = adapter.parse(ref)
    assert_nil document.metadata["date"], "no 서기 front date — honestly dateless, never a guess"
    assert_equal 2, document.size
  end

  def test_passage_annotations_carry_the_article_apparatus
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sillok:wzc_121" }
    annotations = adapter.parse(ref).first.annotations
    assert_equal "순명 황후의 휘호를 경현성휘로 정하다", annotations["title"]
    assert_equal "1928-05-03L0", annotations["date"]
    assert_equal ["왕실-종사(宗社)", "왕실-비빈(妃嬪)"], annotations["subject_classes"]
    assert(annotations["sources"].any? { |source| source.include?("18장 A면") })
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  # The two-dataset choreography: each data.go.kr dataset resolves its
  # atchFileId fresh (the id bumps on every upstream file replacement —
  # the resolution, not the id, is the contract) and lands in its own
  # subdir with its own ZipFetch state + attic.
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
        _ = [url, attic_dir, progress]
        @calls << [:fetch, dir]
        Rigged.new(dir)
      end
    end
  end

  def test_fetch_resolves_and_fetches_both_datasets_into_their_own_subdirs
    rig = FetchRig.new
    rigged = Nabu::Adapters::Sillok.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal "#{'ab' * 32}+#{'ab' * 32}", report.sha, "one pin per dataset, joined"
      assert_equal [[:resolve, "15053647"], [:fetch, File.join(workdir, "taejo-cheoljong")],
                    [:resolve, "15053646"], [:fetch, File.join(workdir, "gojong-sunjong")]],
                   rig.calls
    end
  end

  def test_discover_walks_the_two_dataset_subdirs_of_a_real_workdir
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "taejo-cheoljong"))
      FileUtils.mkdir_p(File.join(workdir, "gojong-sunjong"))
      FileUtils.cp(File.join(FIXTURES, "2nd_waa_200.xml"), File.join(workdir, "taejo-cheoljong"))
      FileUtils.cp(File.join(FIXTURES, "2nd_wzc_121.xml"), File.join(workdir, "gojong-sunjong"))
      assert_equal %w[urn:nabu:sillok:waa_200 urn:nabu:sillok:wzc_121],
                   adapter.discover(workdir).map(&:id).sort
    end
  end

  # --- registry -------------------------------------------------------------

  def test_registry_row_exists_on_the_korean_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sillok"]
    refute_nil entry, "config/sources.yml must register sillok"
    assert_equal Nabu::Adapters::Sillok, entry.adapter_class
    assert entry.wired, "first sync owner-verified; flipped 2026-08-19 (r20 semantics)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "korean", "sillok mints the korean axis"
  end
end
