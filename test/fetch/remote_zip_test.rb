# frozen_string_literal: true

require "test_helper"
require "nabu/fetch/remote_zip"

# Nabu::RemoteZip: a remote zip read by HTTP Range — zip64 directories and
# stored archives nested inside the archive. Served by MakhzanRanges: the
# REAL 6.1 GB OpenITI MAKHZAN zip, from the byte ranges captured off it (a
# zip64 outer archive of 208 stored per-document zips); any byte outside
# the captures answers 416, so an over-read fails the test.
class RemoteZipTest < Minitest::Test
  include MakhzanRanges

  def zip = Nabu::RemoteZip.new(url: ZIP_URL)

  def test_reads_the_zip64_directory_of_the_outer_archive
    stub_makhzan_zip
    outer = zip
    assert_equal ZIP_SIZE, outer.size
    assert_equal 208, outer.entries.size, "one stored zip per document"
    first = outer.entries.first
    assert_equal "Doc101.zip", first.name
    assert_equal 0, first.compression
    last = outer.entries.last
    assert_equal "Doc971.zip", last.name
    assert_operator last.local_header_offset, :>, 0xFFFFFFFF, "a zip64 extra carries the offset past 4 GiB"
    assert_equal "23d6c81b85dcd514394806d369aa59b1fa5a3fc6b2cc252acc9cc9fe2a8bb544", outer.directory_sha256
  end

  def test_reads_members_of_a_nested_stored_zip_without_the_images
    requested = stub_makhzan_zip
    outer = zip
    inner = outer.nested(outer.entries.find { |e| e.name == "Doc102.zip" })
    names = inner.entries.map(&:name)
    assert_includes names, "102_14122.png"
    assert_includes names, "METS.xml"
    page = inner.read(inner.entries.find { |e| e.name == "102_14122.xml" })
    assert_includes page.force_encoding(Encoding::UTF_8), "<alto"
    assert_includes page, 'LANG="ota"'
    image = inner.entries.find { |e| e.name == "102_14122.png" }
    assert_operator image.compressed_size, :>, 1_000_000
    refute(requested.any? { |first, last| last - first > 100_000 }, "no request large enough to carry the image")
    assert_operator outer.meter.bytes, :<, 40_000
  end

  def test_a_nested_read_is_crc_checked
    stub_makhzan_zip
    outer = zip
    inner = outer.nested(outer.entries.find { |e| e.name == "Doc3213.zip" })
    entry = inner.entries.find { |e| e.name == "METS.xml" }
    forged = entry.with(crc32: entry.crc32 ^ 1)
    error = assert_raises(Nabu::RemoteZip::Error) { inner.read(forged) }
    assert_match(/CRC-32/, error.message)
  end

  def test_a_server_ignoring_range_is_refused
    stub_makhzan_zip(status: 200)
    error = assert_raises(Nabu::RemoteZip::Error) { zip.entries }
    assert_match(/refusing to read the whole archive/, error.message)
  end

  def test_only_a_stored_member_opens_as_a_window
    stub_makhzan_zip
    outer = zip
    inner = outer.nested(outer.entries.find { |e| e.name == "Doc102.zip" })
    deflated = inner.entries.find { |e| e.name == "METS.xml" }
    assert_equal 8, deflated.compression
    assert_raises(Nabu::RemoteZip::Error) { inner.nested(deflated) }
  end
end
