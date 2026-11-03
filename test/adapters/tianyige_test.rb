# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Tianyige: the Tianyige Ming examination records (Joshua
# Snider; Zenodo record 23817595, v1.0, CC0) — machine transcription of 312
# printed 科舉錄 (1371–1684) digitized by the Tianyi Pavilion Museum.
#
# Document = one examination record (pages/<tianyige_id>.jsonl + its
# volumes.tsv row); passage = one page image's transcription, cited p<page>.
# Uncorrected vision-model OCR, declared on every document; the machine
# punctuation and English translation on every page are DECLINED (the
# Honkoku precedent) and never surface, nor does the second OCR reading.
# Dates: the record's reign era + year through config/eras.yml's nianhao rows.
class TianyigeTest < Minitest::Test
  include AdapterConformance

  HONGWU = "urn:nabu:tianyige:0006944"
  KANGXI = "urn:nabu:tianyige:0000538"
  MILITARY = "urn:nabu:tianyige:0007858"

  def conformance_adapter = Nabu::Adapters::Tianyige.new

  def conformance_workdir = Nabu::TestSupport.fixtures("tianyige")

  def conformance_expected_source_id = "tianyige"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def document(urn)
    ref = adapter.discover(workdir).find { |r| r.id == urn } || flunk("no ref #{urn}")
    adapter.parse(ref)
  end

  def test_manifest_records_the_cc0_dedication
    manifest = adapter.manifest
    assert_equal "tianyige", manifest.id
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "CC0 1.0"
    assert_includes manifest.license, "The transcriptions and metadata are released under"
    assert_equal "https://zenodo.org/records/23817595", manifest.upstream_url
  end

  def test_discover_yields_one_document_per_record
    assert_equal [KANGXI, HONGWU, MILITARY], adapter.discover(workdir).map(&:id)
  end

  def test_rejected_grains_are_never_discovered
    %w[documents/0006944.jsonl tables/questions.jsonl graduates.tsv questions.tsv index.html].each do |rel|
      assert File.file?(File.join(workdir, rel)), rel
      refute Nabu::Adapters::Tianyige.keep?(rel), "#{rel} stays outside the fetch cone"
    end
    refute Nabu::Adapters::Tianyige.keep?("text/1371_洪武四年會試錄_0006944.txt")
    assert Nabu::Adapters::Tianyige.keep?("pages/0006944.jsonl")
    assert Nabu::Adapters::Tianyige.keep?("volumes.tsv")
    refute(adapter.discover(workdir).any? { |ref| ref.path.include?("/documents/") || ref.path.include?("/text/") })
    skips = adapter.discovery_skips(workdir)
    assert_equal 0, skips.unrecognized
    assert_equal 0, skips.skipped_by_rule
  end

  def test_a_page_file_without_a_volumes_row_is_unrecognized
    Dir.mktmpdir("nabu-tianyige-stray") do |root|
      FileUtils.mkdir_p(File.join(root, "pages"))
      FileUtils.cp(File.join(workdir, "volumes.tsv"), root)
      FileUtils.cp(File.join(workdir, "pages", "0006944.jsonl"), File.join(root, "pages"))
      FileUtils.cp(File.join(workdir, "pages", "0006944.jsonl"), File.join(root, "pages", "9999999.jsonl"))
      skips = adapter.discovery_skips(root)
      assert_equal 1, skips.unrecognized
      assert_match(/9999999/, skips.notes.join)
      assert_equal [HONGWU], adapter.discover(root).map(&:id)
    end
  end

  def test_record_metadata_and_the_ocr_label
    doc = document(HONGWU)
    assert_equal "lzh", doc.language
    assert_equal "洪武四年會試錄", doc.title
    meta = doc.metadata
    assert_equal "uncorrected-ocr", meta["text_nature"]
    assert_match(/Uncorrected vision-language-model transcription/, meta["ocr_note"])
    assert_equal "metropolitan (會試)", meta["exam_level"]
    assert_equal({ "exam_level" => { "value" => "metropolitan", "raw" => "metropolitan (會試)" } }, meta["facets"])
    assert_equal "明洪武刻本", meta["edition_notes"]
    assert_match %r{\Ahttps://commons\.wikimedia\.org/}, meta["commons_page"]
    assert_nil meta["place"], "a metropolitan record names no province"
  end

  def test_the_reign_year_converts_through_the_nianhao_rows
    assert_equal({ "not_before" => 1371, "not_after" => 1371, "raw" => "洪武4 (Ming Hongwu)", "class" => "composition" },
                 document(HONGWU).metadata["date"])
    kangxi = document(KANGXI)
    assert_equal [1684, 1684], kangxi.metadata["date"].values_at("not_before", "not_after"), "the one Qing record"
    assert_equal "Qing", kangxi.metadata["dynasty"]
    assert_equal "四川", kangxi.metadata["place"]
    assert_equal "Sichuan", kangxi.metadata["province_en"]
  end

  def test_one_passage_per_non_blank_page_cited_by_page
    doc = document(KANGXI)
    assert_equal ["#{KANGXI}:p12", "#{KANGXI}:p15"], doc.map(&:urn)
    assert_equal 2, doc.metadata["blank_pages_skipped"]
    assert doc.find { |p| p.urn.end_with?(":p15") }.text.start_with?("第壹場\n四書\n言寡尤行寡悔祿在其中矣")
  end

  def test_the_transcription_is_verbatim_and_its_provenance_rides_annotations
    page = document(HONGWU).first
    assert page.text.start_with?("會試紀錄題辭\n皇明設科倣古者六藝之教參以")
    notes = page.annotations
    assert_equal 1, notes["page"]
    assert_equal "gemini-4-argon (agy, low effort)", notes["ocr_model"]
    assert_equal "claude-opus-5-5 (Claude Code CLI, low effort)", notes["alt_ocr_model"]
    assert_in_delta 0.9854, notes["agreement"]
    assert_equal ["會一"], notes["banxin"]
    assert_match %r{\Ahttps://commons\.wikimedia\.org/}, notes["scan_url"]
  end

  def test_the_machine_punctuation_translation_and_second_reading_never_surface
    %w[punctuated translation_en translation_model alt_text].each do |field|
      assert(File.read(File.join(workdir, "pages", "0006944.jsonl")).include?("\"#{field}\""), field)
    end
    [HONGWU, KANGXI, MILITARY].each do |urn|
      document(urn).each do |page|
        refute_match(/[A-Za-z]{4,}/, page.text, "no English in the text")
        assert_empty page.annotations.keys & %w[punctuated translation_en translation_model alt_text]
      end
    end
  end

  def test_a_military_record_is_flagged
    doc = document(MILITARY)
    assert_equal true, doc.metadata["military"]
    assert_equal "廣東", doc.metadata["place"]
    assert_equal ["#{MILITARY}:p2"], doc.map(&:urn)
  end

  def test_fetch_pins_the_v1_0_directory
    assert_match %r{\Ahttps://zenodo\.org/api/records/23817595/files/}, Nabu::Adapters::Tianyige::ZIP_URL
    assert_equal "de1bb49f45c9ee8c6311e9ea463bd7f3b74fb9067f4b25ab5175b6549e2041e4",
                 Nabu::Adapters::Tianyige::DIRECTORY_SHA256
  end

  FakeRange = Struct.new(:sha, :completed, keyword_init: true) do
    def prepare! = nil
    def not_modified? = false
    def doomed_paths = []
    def complete! = (self.completed = true)

    def result
      Nabu::ZipRangeFetch::Result.new(sha: sha, size: 1, kept: 315, skipped: 1, atticked: [], not_modified: false)
    end
  end

  def test_a_directory_pin_miss_aborts_before_any_tree_change
    fake = FakeRange.new(sha: "0" * 64, completed: false)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Tianyige.new(range_fetch: ->(**) { fake }).fetch(dir) }
    end
    refute fake.completed
  end
end
