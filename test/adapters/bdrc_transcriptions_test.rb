# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# BdrcTranscriptions adapter tests: BDRC's three CC0 Tibetan page-aligned
# transcription releases on Hugging Face, held as their TEXT columns only
# (Nabu::HfRowsFetch). Fixture (test/fixtures/bdrc-transcriptions/README.md):
# per release, real etext volumes cut to their first pages in page order
# (one row per line, exactly as the fetch lands them), plus each release's
# dataset card and subset_info.json — the rejected metadata grain, pinned
# as the skip-by-rule specimens.
class BdrcTranscriptionsTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("bdrc-transcriptions")
  PREFIX = "urn:nabu:bdrc-transcriptions"
  BERKELEY_MS = "#{PREFIX}:berkeley:VE2115_MA".freeze
  BERKELEY_XYLO = "#{PREFIX}:berkeley:VE4PD1489_MA".freeze
  PALRI = "#{PREFIX}:palri-parkhang:VE1605_MA".freeze
  ACIP = "#{PREFIX}:acip-sungbum:VE1ALS05274I".freeze

  def conformance_adapter = Nabu::Adapters::BdrcTranscriptions.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "bdrc-transcriptions"

  def adapter = Nabu::Adapters::BdrcTranscriptions.new

  def document(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  def test_manifest_records_the_cc0_card_verbatim
    manifest = adapter.manifest
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "CC0-1.0"
    assert_includes manifest.license, "Attribution requested (not required)"
    assert_equal "hf-rows-jsonl", manifest.parser_family
    assert_match(/Buddhist Digital Resource Center/, manifest.credit)
  end

  def test_discover_yields_one_document_per_etext_volume_in_release_order
    assert_equal [ACIP, PALRI, BERKELEY_MS, BERKELEY_XYLO], adapter.discover(FIXTURES).map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  def test_one_passage_per_page_cited_by_the_scan_image
    doc = document(BERKELEY_MS)
    assert_equal 3, doc.size
    assert_equal %W[#{BERKELEY_MS}:21150297 #{BERKELEY_MS}:21150455 #{BERKELEY_MS}:21150456], doc.map(&:urn),
                 "page order is the scan order; the release's own filtering leaves gaps"
    assert_equal "xct", doc.language
    assert(doc.all? { |passage| passage.language == "xct" })
    assert_equal 6, doc.to_a[1].text.lines.size, "the release's manual line breaks are kept verbatim"
  end

  def test_page_annotations_carry_the_scan_and_style_facts
    page = document(BERKELEY_XYLO).first
    assert_equal "I4PD14890028.jpg", page.annotations["image"]
    assert_equal "202604:Kurt:IE2PD17515_MA:VE4PD1489_MA:v2:I4PD14890028.jpg", page.annotations["row_id"]
    assert_equal "woodblock", page.annotations["technology"]
    assert_equal "uchen", page.annotations["script"]
    refute page.annotations.key?("script_4"), "a null writing style is omitted, never stringified"
    assert_includes page.text, "སྤར་བཞེངས་ཀུན་གྱིས་དོན་རྟོགས་ཤོག", "the printing colophon (spar bzhengs)"
    assert_includes document(BERKELEY_XYLO).to_a[1].text, "རྗེ་བཙུན་མི་ལ་རས་པའི", "Milarepa's songs follow"
  end

  def test_document_metadata_mines_every_axis_field_the_release_ships
    meta = document(BERKELEY_MS).metadata
    assert_equal "berkeley", meta["release"]
    assert_equal "BDRC/berkeley-transcriptions", meta["hf_dataset"]
    assert_equal "Kurt", meta["collection"]
    assert_equal "IE23550_MA", meta["etext_instance"]
    assert_equal "VE2115_MA", meta["etext_volume"]
    assert_equal "MW23550", meta["bdrc_version"]
    assert_equal "http://purl.bdrc.io/resource/MW23550", meta["bdrc_url"]
    assert_equal({ "manuscript" => 3 }, meta["technology"])
    assert_equal({ "ume" => 3 }, meta["script"])
    assert_equal 3, meta["pages"]
    assert_equal "202604", meta["release_tag"]
  end

  def test_each_release_parses_with_its_own_columns
    acip = document(ACIP)
    assert_equal %W[#{ACIP}:I1KG10660015 #{ACIP}:I1KG10660020 #{ACIP}:I1KG10660022], acip.map(&:urn)
    assert_equal "ACIP_Sungbum", acip.metadata["collection"]
    assert_equal "MW635", acip.metadata["bdrc_version"]
    assert_equal({ "woodblock" => 3 }, acip.metadata["technology"])
    refute acip.metadata.key?("script_4"), "the ACIP release ships no writing-style column"
    assert acip.first.text.start_with?("༄༅། །པ་ལ།")

    palri = document(PALRI)
    assert_equal "PalriParkhang", palri.metadata["collection"]
    assert_equal "༄། ཆོས་འབྱུང་བསྟན་པའི་ཉི་མ་ཞེས་བྱ་བ་བཞུགས་སོ།།", palri.first.text, "the title page"
    assert_equal({ "danyig_pedri" => 2, "druma" => 1 }, palri.metadata["script_4"])
  end

  def test_title_names_the_release_volume_and_bdrc_version
    assert_equal "Berkeley transcriptions — etext volume VE2115_MA (BDRC MW23550)", document(BERKELEY_MS).title
  end

  def test_the_metadata_grain_is_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 6, skips.skipped_by_rule, "README.md + subset_info.json for each of the three releases"
    assert(skips.notes.any? { |note| note.include?("dataset card") })
  end

  def test_a_page_with_a_blank_transcription_is_dropped_and_counted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "berkeley"))
      lines = File.readlines(File.join(FIXTURES, "berkeley", "VE2115_MA.jsonl"))
      blank = JSON.parse(lines[1]).merge("transcription" => " \n")
      File.write(File.join(dir, "berkeley", "VE2115_MA.jsonl"), [lines[0], "#{JSON.generate(blank)}\n", lines[2]].join)
      doc = adapter.parse(adapter.discover(dir).first)
      assert_equal 2, doc.size
      assert_equal 1, doc.metadata["blank_pages"]
    end
  end

  def test_a_volume_of_only_blank_pages_is_a_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "berkeley"))
      line = JSON.parse(File.readlines(File.join(FIXTURES, "berkeley", "VE2115_MA.jsonl")).first)
      File.write(File.join(dir, "berkeley", "VE2115_MA.jsonl"), "#{JSON.generate(line.merge('transcription' => ''))}\n")
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  def test_fetch_projects_each_release_through_hf_rows_fetch_keyed_by_volume
    calls = []
    fake = lambda do |**kwargs|
      calls << kwargs
      row = { "id" => "202604:Kurt:IE23550_MA:VE2115_MA:v2:23550001.tif" }
      assert_equal "VE2115_MA.jsonl", kwargs[:document_path].call(row)
      assert_nil kwargs[:document_path].call({ "id" => "malformed" }), "an unparseable id has no home"
      assert_equal "23550001.tif", kwargs[:sort_key].call(row)
      Nabu::HfRowsFetch::Result.new(revision: "r", sha: "s", rows: 1, documents: 1, unkeyed: 0, atticked: [],
                                    not_modified: false)
    end
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::BdrcTranscriptions.new(rows_fetch: fake).fetch(dir)
      assert_equal(%w[BDRC/ALL-BDRC-alignments BDRC/palri-parkhang-transcriptions BDRC/berkeley-transcriptions],
                   calls.map { |call| call[:repo] })
      assert_equal File.join(dir, "acip-sungbum"), calls.first[:dir]
      assert_equal %w[README.md subset_info.json], calls.first[:sidecars]
      assert_match(/3 releases/, report.notes)
    end
  end
end
