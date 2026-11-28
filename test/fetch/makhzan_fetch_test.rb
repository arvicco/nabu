# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/fetch/makhzan_fetch"

# Nabu::MakhzanFetch: the ALTO/METS members of the selected OpenITI MAKHZAN
# documents, read by HTTP Range from the real 6.1 GB deposit zip (served by
# MakhzanRanges from the captured byte ranges — any other byte answers 416),
# plus the record JSON (real, test/fixtures/makhzan/fetch/record.json) and a
# trimmed real metadata TSV (Doc 37/38 Persian, Doc 102/3213 Ottoman).
class MakhzanFetchTest < Minitest::Test
  include MakhzanRanges

  FETCH = File.join(Nabu::TestSupport.fixtures("makhzan"), "fetch")
  TSV = File.binread(File.join(FETCH, "metadata.tsv"))
  TSV_URL = Nabu::MakhzanFetch.file_url(Nabu::MakhzanFetch::METADATA_FILE)
  # The record as it reads for the TRIMMED tsv the test serves (the real
  # file list otherwise untouched).
  PIN = Nabu::MakhzanFetch::PIN.with(metadata_size: TSV.bytesize, metadata_md5: Digest::MD5.hexdigest(TSV))
  OTTOMAN = lambda do |tsv|
    tsv.lines.drop(1).map { |line| line.split("\t") }.select { |cols| cols[0].include?("Ottoman Turkish") }
                                                     .map { |cols| cols[1] }.uniq
  end

  def setup
    record = JSON.parse(File.read(File.join(FETCH, "record.json")))
    record["files"].each do |file|
      file.merge!("size" => PIN.metadata_size, "checksum" => "md5:#{PIN.metadata_md5}") if file["key"].end_with?(".tsv")
    end
    @record = stub_request(:get, Nabu::MakhzanFetch::RECORD_URL).to_return(body: JSON.generate(record))
    @tsv = stub_request(:get, TSV_URL).to_return(body: TSV)
    @ranges = stub_makhzan_zip
  end

  def sync(dir, pin: PIN, **)
    Nabu::MakhzanFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), select: OTTOMAN, pin: pin,
                             http: Faraday.new, **)
  end

  def landed(dir) = Dir.glob("**/*", base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort

  def test_lands_the_selected_documents_xml_and_the_metadata_only
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal ["Doc102/102_14122.xml", "Doc102/METS.xml", "Doc3213/3213_753313.xml",
                    "Doc3213/METS.xml", "OpenITI-Makhzan_Metadata_2026-1-2.tsv"], landed(dir).sort
      assert_equal 2, result.documents
      assert_equal 5, result.kept
      assert_equal 206 + 2, result.skipped, "206 documents never opened + the two page images"
      assert_includes File.read(File.join(dir, "Doc102/102_14122.xml")), 'LANG="ota"'
      assert_equal TSV, File.binread(File.join(dir, "OpenITI-Makhzan_Metadata_2026-1-2.tsv"))
      state = JSON.parse(File.read(File.join(dir, ".makhzan-fetch.json")))
      assert_equal "2026.1.2", state["version"]
      assert_equal %w[Doc102.zip Doc3213.zip], state["documents"]
      assert_operator result.bytes, :<, 50_000, "kilobytes of a 6.1 GB archive"
    end
  end

  def test_requests_carry_the_research_user_agent
    Dir.mktmpdir do |dir|
      sync(dir)
      assert_requested(:get, MakhzanRanges::ZIP_URL, headers: { "User-Agent" => Nabu::MakhzanFetch::USER_AGENT },
                                                     at_least_times: 1)
      assert_requested(:get, Nabu::MakhzanFetch::RECORD_URL, headers: { "User-Agent" => /nabu-research-library/ })
    end
  end

  def test_an_unchanged_deposit_is_not_modified_and_reads_no_member
    Dir.mktmpdir do |dir|
      sync(dir)
      before = @ranges.size
      second = sync(dir)
      assert second.not_modified
      assert_equal 5, second.kept
      assert_equal 2, @ranges.size - before, "only the tail and the outer directory are read again"
      assert_requested @tsv, times: 1
    end
  end

  def test_a_record_version_drift_is_refused_before_any_range_read
    remove_request_stub(@record)
    drifted = JSON.generate("metadata" => { "version" => "2027.1.3" }, "files" => [])
    stub_request(:get, Nabu::MakhzanFetch::RECORD_URL).to_return(body: drifted)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::MakhzanFetch::Error) { sync(dir) }
      assert_match(/2027\.1\.3/, error.message)
      assert_empty @ranges
      assert_empty landed(dir)
    end
  end

  def test_a_directory_unlike_the_pin_is_refused
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::MakhzanFetch::Error) { sync(dir, pin: PIN.with(directory_sha256: "0" * 64)) }
      assert_match(/owner re-pin/, error.message)
      assert_empty landed(dir)
    end
  end

  def test_a_tsv_unlike_its_md5_is_refused
    remove_request_stub(@tsv)
    stub_request(:get, TSV_URL).to_return(body: "#{TSV}tampered")
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::MakhzanFetch::Error) { sync(dir) }
      assert_empty landed(dir)
    end
  end

  def test_a_document_dropped_upstream_is_atticked_after_the_guard
    Dir.mktmpdir do |dir|
      sync(dir)
      only102 = ->(_tsv) { %w[102] }
      seen = nil
      result = Nabu::MakhzanFetch.sync!(dir: dir, attic_dir: File.join(dir, ".attic"), select: only102,
                                        pin: PIN, http: Faraday.new,
                                        guard: ->(doomed) { seen = doomed })
      refute result.not_modified, "a different selection re-reads"
      assert_equal [File.join(dir, "Doc3213/3213_753313.xml"), File.join(dir, "Doc3213/METS.xml")], seen.sort
      assert File.file?(File.join(dir, ".attic", "Doc3213", "3213_753313.xml"))
      refute File.exist?(File.join(dir, "Doc3213", "3213_753313.xml"))
    end
  end
end
