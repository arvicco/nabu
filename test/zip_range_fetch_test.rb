# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::ZipRangeFetch: selected members of a remote zip, read by HTTP Range
# requests — the tail, the central directory, then each kept member's
# bytes — so the archive's excluded bulk is never transferred. Served by a
# WebMock stub that honours Range over a REAL repacked archive
# (test/fixtures/baley-manuscripts/fetch/jinteng-subset.zip: eleven real
# members of the Jinteng deposit, repacked with zip(1)); never the network.
class ZipRangeFetchTest < Minitest::Test
  ZIP = File.binread(File.join(Nabu::TestSupport.fixtures("baley-manuscripts"), "fetch", "jinteng-subset.zip"))
  URL = "https://zenodo.org/api/records/23870159/files/jinteng-alignment-dataset-1.0.0.zip/content"
  KEEP = ->(name) { (name.start_with?("dataset/") && !name.end_with?("strip_mapping.json")) || name == "LICENSE.md" }

  def setup
    @ranges = []
  end

  def stub_ranged(body = ZIP)
    stub_request(:get, URL).to_return do |request|
      range = request.headers["Range"].to_s
      first, last = range[/bytes=(\d+-\d+)/, 1].split("-").map(&:to_i)
      @ranges << [first, last]
      last = [last, body.bytesize - 1].min
      { status: 206, body: body.byteslice(first..last),
        headers: { "Content-Range" => "bytes #{first}-#{last}/#{body.bytesize}" } }
    end
  end

  def sync(dir, **)
    Nabu::ZipRangeFetch.sync!(url: URL, dir: dir, attic_dir: File.join(dir, ".attic"), select: KEEP, **)
  end

  def test_lands_only_the_selected_members_with_the_top_directory_stripped
    stub_ranged
    Dir.mktmpdir do |dir|
      result = sync(dir)
      landed = Dir.glob("**/*", base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort
      assert_equal %w[LICENSE.md dataset/alignment.json dataset/manifest.json dataset/shangshu/transcription.json
                      dataset/tsinghua/source_mapping.json dataset/tsinghua/transcription.json], landed
      assert_equal 6, result.kept
      assert_equal 5, result.skipped, "README, QUICKSTART, strip_mapping, RIGHTS, tools/build_media.py"
      refute result.not_modified
      expected = ZIP.bytesize
      assert_equal expected, result.size
      tsinghua = JSON.parse(File.read(File.join(dir, "dataset/tsinghua/transcription.json")))
      assert_equal "tsinghua", tsinghua["witness_id"]
    end
  end

  def test_never_reads_an_excluded_members_bytes
    stub_ranged
    Dir.mktmpdir do |dir|
      sync(dir)
      entries = Nabu::ZipReader.new(ZIP).entries.reject { |entry| entry.name.end_with?("/") }
      excluded = entries.reject { |entry| KEEP.call(entry.name.sub(%r{\A[^/]+/}, "")) }
      excluded.each do |entry|
        data_start = entry.local_header_offset + 30
        refute(@ranges.any? { |first, last| first <= data_start + 1 && last >= data_start + entry.compressed_size - 1 },
               "#{entry.name}'s bytes were requested")
      end
    end
  end

  def test_an_unchanged_archive_is_not_modified
    stub_ranged
    Dir.mktmpdir do |dir|
      first = sync(dir)
      requests = @ranges.size
      second = sync(dir)
      assert second.not_modified
      assert_equal first.sha, second.sha
      assert_operator @ranges.size - requests, :<=, 3, "a re-sync reads only the size probe, tail and directory"
    end
  end

  def test_a_member_dropped_upstream_is_atticked_after_the_guard
    stub_ranged
    Dir.mktmpdir do |dir|
      sync(dir)
      FileUtils.mkdir_p(File.join(dir, "dataset/gone"))
      File.write(File.join(dir, "dataset/gone/transcription.json"), "{}")
      File.write(File.join(dir, Nabu::ZipRangeFetch::STATE_FILE), "{}")
      seen = nil
      result = sync(dir, guard: ->(doomed) { seen = doomed })
      assert_equal [File.join(dir, "dataset/gone/transcription.json")], seen
      assert_equal ["dataset/gone/transcription.json"], result.atticked
      assert File.file?(File.join(dir, ".attic/dataset/gone/transcription.json"))
    end
  end

  def test_a_server_ignoring_range_is_refused
    stub_request(:get, URL).to_return(status: 200, body: "x")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::ZipRangeFetch::Error) { sync(dir) }
      assert_match(/Range/, error.message)
    end
  end

  def test_a_corrupt_member_fails_its_crc
    corrupt = ZIP.dup
    entry = Nabu::ZipReader.new(ZIP).entries.find { |e| e.name.end_with?("LICENSE.md") }
    name_length, extra_length = corrupt.byteslice(entry.local_header_offset + 26, 4).unpack("vv")
    at = entry.local_header_offset + 30 + name_length + extra_length
    corrupt.setbyte(at, corrupt.getbyte(at) ^ 0xFF)
    stub_ranged(corrupt)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::ZipRangeFetch::Error) { sync(dir) }
      refute File.exist?(File.join(dir, "LICENSE.md")), "nothing lands when one member fails"
    end
  end
end
