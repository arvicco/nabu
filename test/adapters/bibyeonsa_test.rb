# frozen_string_literal: true

require "test_helper"

# The bibyeonsa adapter (P78-3): 비변사등록 원문 — the Records of the
# Border Defense Command (1617–1892, the Joseon state council's daily
# register) in the original hanmun, NIKH via data.go.kr dataset
# 15053636. nikh-xml family, korean axis.
class BibyeonsaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("bibyeonsa")

  def adapter = Nabu::Adapters::Bibyeonsa.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "bibyeonsa"

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_data_go_kr_grant
    manifest = adapter.manifest
    assert_equal "bibyeonsa", manifest.id
    assert_equal "attribution", manifest.license_class, "D47-a: 제한 없음 → attribution, credit the institute"
    assert_match(/제한 없음/, manifest.license)
    assert_equal "nikh-xml", manifest.parser_family
    assert_match(/국사편찬위원회|National Institute of Korean History/, manifest.credit)
  end

  # --- discover → parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_book_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[urn:nabu:bibyeonsa:bb_001 urn:nabu:bibyeonsa:bb_054],
                 refs.map(&:id).sort
  end

  def test_the_dtd_is_recognized_never_a_stray
    skips = adapter.discovery_skips(FIXTURES)
    # manifest.yml is the ONE counted stray (the achemenet precedent).
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  def test_parse_mints_hanmun_passages_per_leaf_entry
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:bibyeonsa:bb_054" }
    document = adapter.parse(ref)
    assert_equal "lzh", document.language, "hanmun = Literary Chinese as read in Korea (the kanripo precedent)"
    assert_equal "비변사등록 54책", document.title
    assert_equal %w[urn:nabu:bibyeonsa:bb_054:bb_054_001_01_0010
                    urn:nabu:bibyeonsa:bb_054:bb_054_001_01_0020],
                 document.map(&:urn)
    roster = document.first
    assert_includes roster.text, "甲申正月朔座目", "the 좌목 roster table flattens to its text"
    assert_includes roster.text, "尹趾完"
    assert_includes document.to_a.last.text, "備忘記"
  end

  def test_the_item_wrapped_first_book_parses_whole
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:bibyeonsa:bb_001" }
    document = adapter.parse(ref)
    # bb_001 is the zip's ONE <item>-rooted member (single level1 — the
    # 1책 book with NIKH's 1959 print-edition front, whose 서문 preface
    # rides the front apparatus, never a passage). Its level2 year
    # sections INTERLEAVE 1617 and 1616 — the census's non-monotonic
    # year witness, kept across two leaves here.
    assert_equal "비변사등록 1책", document.title
    assert_equal %w[urn:nabu:bibyeonsa:bb_001:bb_001_001_01_0010
                    urn:nabu:bibyeonsa:bb_001:bb_001_002_01_0010],
                 document.map(&:urn)
    assert_equal %w[1617-01-00L0 1616-12-30L0], document.map { |passage| passage.annotations["date"] },
                 "the untyped machine dates ride annotations; years interleave upstream"
  end

  def test_document_metadata_claims_no_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:bibyeonsa:bb_054" }
    document = adapter.parse(ref)
    # P78-3 census: book fronts carry publication data (dateIssued 1959,
    # the NIKH print edition) but NO dateOccured; the content years live
    # on level2 value attrs and the per-entry machine dates — the
    # document claims nothing at its own grain.
    assert_nil document.metadata["date"]
    assert_equal({ "volume" => "bb_054" }, document.metadata)
  end

  def test_passage_annotations_carry_the_editorial_title_and_the_machine_date
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:bibyeonsa:bb_054" }
    annotations = adapter.parse(ref).first.annotations
    assert_equal "肅宗 30년(1704) 1월 좌목", annotations["title"]
    assert_equal "1704-01-00L0", annotations["date"], "bibyeonsa's dateOccured carries NO type attr — date only"
  end

  # --- fetch (rigged — no network in tests, ever) ---------------------------

  class FetchRig
    attr_reader :calls

    Rigged = Struct.new(:dir) do
      def prepare! = nil
      def doomed_paths = []
      def complete! = 3
      def cleanup! = nil
      def sha = "ef" * 32
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
    rigged = Nabu::Adapters::Bibyeonsa.new(resolver: rig.resolver, zip_fetch_factory: rig.zip_fetch_factory)
    Dir.mktmpdir do |workdir|
      report = rigged.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal "ef" * 32, report.sha, "one dataset, one pin"
      assert_equal ["data.go.kr 15053636"], report.notes
      assert_equal [[:resolve, "15053636"], [:fetch, workdir, File.join(workdir, ".attic")]],
                   rig.calls
    end
  end

  def test_discover_walks_a_flat_real_workdir
    Dir.mktmpdir do |workdir|
      FileUtils.cp(File.join(FIXTURES, "bb_054.xml"), workdir)
      FileUtils.cp(File.join(FIXTURES, "history.dtd"), workdir)
      assert_equal %w[urn:nabu:bibyeonsa:bb_054], adapter.discover(workdir).map(&:id)
    end
  end
end
