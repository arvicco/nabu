# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "nabu/adapters/makhzan"

# Makhzan adapter tests: OpenITI MAKHZAN's Ottoman Turkish manuscripts
# (Zenodo 10.5281/zenodo.19861912, CC BY-NC-SA 4.0). Fixture
# (test/fixtures/makhzan/README.md): the workdir as MakhzanFetch lands it —
# a trimmed real metadata TSV and three documents' real ALTO + METS: Doc102
# (Leiden Or. 1076, Ṭavāʾif-i ʿaşere, 1569), Doc3178 (Leiden Or. 1094, a
# mecmūʿa "c. 1500", Arabic/Ottoman/Persian — LANG="mul") and Doc3262
# (Leipzig B. or. 232, Revnaḳ-ı Būstān, "17th c.", two of its ten pages, its
# METS and TSV rows trimmed to match). The TSV's two Persian documents (37,
# 38) are the rejected-grain specimen.
class MakhzanTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("makhzan")
  PREFIX = "urn:nabu:makhzan"

  def conformance_adapter = Nabu::Adapters::Makhzan.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "makhzan"

  def adapter = Nabu::Adapters::Makhzan.new

  def document(id)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "#{PREFIX}:#{id}" } || flunk("discover must yield #{id}")
    adapter.parse(ref)
  end

  def test_manifest_records_the_noncommercial_record_license
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "CC BY-NC-SA 4.0"
    assert_includes manifest.license, "cc-by-nc-sa-4.0"
    assert_match(%r{10\.5281/zenodo\.19861912}, manifest.credit)
    assert_equal "alto-escriptorium", manifest.parser_family
  end

  def test_discover_takes_the_ottoman_documents_in_numeric_order
    assert_equal %W[#{PREFIX}:102 #{PREFIX}:3178 #{PREFIX}:3262], adapter.discover(FIXTURES).map(&:id)
  end

  def test_other_languages_are_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 2, skips.skipped_by_rule
    assert(skips.notes.any? { |note| note.include?("Persian 2") })
  end

  def test_a_listed_ottoman_document_without_its_files_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("#{FIXTURES}/.", dir)
      FileUtils.rm_rf(File.join(dir, "Doc3178"))
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("3178") })
    end
  end

  def test_one_passage_per_transcribed_line_cited_part_and_ordinal
    leiden = document(102)
    assert_equal 19, leiden.size
    assert_equal "#{PREFIX}:102:14122.1", leiden.first.urn
    assert_equal "وكيمني اهل كشف ايلدي ، وكيمي مجذب وسالك ، وكيمني سالك", leiden.first.text
    assert_equal "ota", leiden.language
    assert_equal "Kitāb-i Ṭavā’if-i ‘aşere", leiden.title
    assert_equal({ "part" => "14122", "image" => "102_14122.png", "line_id" => "eSc_line_f9be8fc5" },
                 leiden.first.annotations)
  end

  def test_pages_follow_the_mets_order
    bustan = document(3262)
    assert_equal 44, bustan.size, "22 + 22 transcribed lines, as the TSV counts them"
    assert_equal %w[759523 759525], bustan.map { |p| p.annotations["part"] }.uniq
    assert_equal "#{PREFIX}:3262:759525.22", bustan.to_a.last.urn
  end

  def test_document_metadata_is_mined_from_the_tsv
    leiden = document(102).metadata
    assert_equal "Or. 1076", leiden["call_no"]
    assert_equal "Leiden University", leiden["repository"]
    assert_equal "Vâhidi", leiden["compiler"]
    assert_equal "taliq", leiden["hand"]
    assert_equal "Sufism", leiden["genre"]
    assert_equal "Poetry", leiden["form"]
    assert_equal ["Delicate hand with high ascenders"], leiden["notes"]
    assert_equal({ "not_before" => 1569, "not_after" => 1569, "raw" => "1569" }, leiden["date"])
    assert_equal "10.5281/zenodo.19861912", leiden["doi"]
    refute leiden.key?("place"), "the holding library is never the place claim"
  end

  def test_a_circa_and_a_century_date_and_the_polity_place
    majmua = document(3178).metadata
    assert_equal({ "not_before" => 1500, "not_after" => 1500, "raw" => "c. 1500", "circa" => true }, majmua["date"])
    bustan = document(3262).metadata
    assert_equal({ "not_before" => 1601, "not_after" => 1700, "raw" => "17th c." }, bustan["date"])
    assert_equal "Ottoman Empire", bustan["place"]
  end

  def test_a_multilingual_manuscript_keeps_its_language_claims
    majmua = document(3178)
    assert_equal "ota", majmua.language
    assert_equal "Arabic, Ottoman Turkish, Persian", majmua.metadata["languages"]
    assert_equal "ara,ota,fas", majmua.metadata["language_codes"]
    assert_equal "mul", majmua.first.annotations["page_language"]
  end

  def test_date_of_reads_the_volume_date_shapes
    date = Nabu::Adapters::Makhzan.method(:date_of)
    assert_equal({ "not_before" => 1438, "not_after" => 1438, "raw" => "1438" }, date.call("1438"))
    assert_equal({ "not_before" => 1801, "not_after" => 1900, "raw" => "19th c." }, date.call("19th c."))
    assert_equal({ "raw" => "after 1600" }, date.call("after 1600"))
    assert_nil date.call(nil)
  end

  def test_ottoman_ids_select_every_ottoman_language_label
    tsv = File.read(File.join(FIXTURES, "OpenITI-Makhzan_Metadata_2026-1-2.tsv"))
    assert_equal %w[102 3178 3262], Nabu::Adapters::Makhzan.ottoman_ids(tsv)
  end

  def test_mets_and_tsv_disagreeing_is_a_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("#{FIXTURES}/.", dir)
      FileUtils.rm(File.join(dir, "Doc3262", "3262_759525.xml"))
      ref = adapter.discover(dir).find { |r| r.id == "#{PREFIX}:3262" }
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_fetch_wraps_the_range_fetch_and_reports_the_transfer
    result = Nabu::MakhzanFetch::Result.new(sha: "abc", documents: 30, kept: 279, skipped: 1427, atticked: [],
                                            not_modified: false, requests: 400, bytes: 1_600_000)
    calls = []
    fetcher = lambda do |**kwargs|
      calls << kwargs
      result
    end
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::Makhzan.new(fetcher: fetcher).fetch(dir)
      assert_equal "abc", report.sha
      assert_match(/30 documents: 279 files kept by Range \(1600000 bytes in 400 requests\)/, report.notes)
      assert_equal dir, calls.first[:dir]
      tsv = File.read(File.join(FIXTURES, "OpenITI-Makhzan_Metadata_2026-1-2.tsv"))
      assert_equal %w[102 3178 3262], calls.first[:select].call(tsv), "the fetch selects by the adapter's own rule"
    end
  end

  def test_a_fetch_error_aborts_the_sync
    fetcher = ->(**) { raise Nabu::MakhzanFetch::Error, "pin drift" }
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Makhzan.new(fetcher: fetcher).fetch(dir) }
    end
  end

  def test_probes_the_zenodo_zip_for_liveness
    target = Nabu::Adapters::Makhzan.http_probe_targets.first
    assert_equal :http_zip, Nabu::Adapters::Makhzan.remote_probe_strategy
    assert_equal Nabu::MakhzanFetch.file_url(Nabu::MakhzanFetch::ZIP_FILE), target.zip_url
    assert target.liveness_only
  end
end
