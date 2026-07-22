# frozen_string_literal: true

require "test_helper"
require "zlib"

# Nabu::ZipReader (P39-3): the dependency-free in-process single-archive zip
# reader that replaces the ~17k `unzip` subprocesses the aozora rebuild forked.
#
# The load-bearing guarantee is BYTE-IDENTITY with `unzip -p` on every real
# aozora fixture zip (the junk-name offender and the corrupt trim included),
# plus honest handling of the format traps a naive PK\x03\x04 scan gets wrong:
# data descriptors (zeroed local sizes) and member data that coincidentally
# contains local-header signature bytes. Those two are built here as REAL,
# spec-conformant archives (a zip container, not fake corpus text) and are
# cross-checked against the system `unzip -p` so the fixtures stay honest.
class ZipReaderTest < Minitest::Test
  FIXTURE_ZIPS = Dir.glob(
    File.expand_path("fixtures/aozora/cards/*/files/*.zip", __dir__)
  ).freeze

  VALID_FIXTURES = FIXTURE_ZIPS.grep_v(/56151_ruby_60063/).freeze
  CORRUPT_FIXTURE = FIXTURE_ZIPS.grep(/56151_ruby_60063/).first

  # A member spec for the hand-built zips below (:compression, not :method —
  # Struct#method would collide).
  Member = Struct.new(:name, :content, :compression, :crc, :compressed, :data_descriptor, :corrupt_crc)

  # -- byte-identity pins over the real fixtures --------------------------------

  def test_every_valid_fixture_extracts_byte_identically_to_unzip_p
    refute_empty VALID_FIXTURES, "the aozora fixture zips must be present"
    VALID_FIXTURES.each do |path|
      reader = Nabu::ZipReader.new(File.binread(path))
      txt = reader.entries.find { |entry| entry.name.match?(/\.txt\z/in) }
      refute_nil txt, "#{File.basename(path)}: a .txt member"
      reference = Nabu::Shell.run("unzip", "-p", path)
      assert_equal reference.b, reader.extract(txt).b,
                   "#{File.basename(path)}: reader output must equal `unzip -p` byte-for-byte"
    end
  end

  # The P38-i1 offender: a single member named with bytes invalid in UTF-8 AND
  # CP932. Names are BINARY and never decoded.
  def test_junk_member_name_is_kept_binary_and_never_decoded
    path = FIXTURE_ZIPS.grep(/51135_ruby_65180/).first
    reader = Nabu::ZipReader.new(File.binread(path))
    name = reader.entries.first.name
    assert_equal Encoding::BINARY, name.encoding
    refute name.valid_encoding? && name.dup.force_encoding("UTF-8").valid_encoding?,
           "the member name is deliberately non-UTF-8 junk bytes"
    assert name.match?(/\.txt\z/in), "byte-wise /n matching still selects it"
  end

  # The corrupt trim has no central directory: unzip fails, and so must we.
  def test_corrupt_zip_without_central_directory_raises
    error = assert_raises(Nabu::ZipReader::Error) do
      Nabu::ZipReader.new(File.binread(CORRUPT_FIXTURE))
    end
    assert_match(/central-directory/i, error.message)
  end

  def test_error_is_a_nabu_error_so_callers_can_map_it
    assert_operator Nabu::ZipReader::Error, :<, Nabu::Error
  end

  # -- format traps a forward scan gets wrong -----------------------------------

  # Data descriptor (general-purpose bit 3): the LOCAL header's sizes/crc are
  # zero, and only the central directory carries the real compressed size. A
  # reader that trusted the local header (or scanned for the next PK\x03\x04)
  # would misread the member. Cross-checked against `unzip -p`.
  def test_deflate_member_with_a_data_descriptor
    content = "秘密の中に PK\x03\x04 みたいなバイト列がある\n" * 40
    zip = build_zip([member("body.txt", content, deflate: true, data_descriptor: true)])
    reader = Nabu::ZipReader.new(zip)
    entry = reader.entries.first

    assert_equal 0, local_field(zip, entry, 18), "local header compressed size is zeroed under a data descriptor"
    assert_equal content.b, reader.extract(entry).b
    assert_equal content.b, unzip_p(zip).b, "the harness built a zip real `unzip` also reads"
  end

  # Stored (method 0) member whose CONTENT contains the local-header signature
  # bytes: a naive scan finds a false member boundary; honest CD parsing does
  # not.
  def test_stored_member_whose_content_contains_local_signature_bytes
    content = ("A" * 10) + "PK\x03\x04".b + ("B" * 10)
    zip = build_zip([member("stored.txt", content, deflate: false)])
    reader = Nabu::ZipReader.new(zip)
    assert_equal 1, reader.entries.size, "exactly one member despite the nested signature bytes"
    assert_equal content.b, reader.extract(reader.entries.first).b
    assert_equal content.b, unzip_p(zip).b
  end

  def test_multi_member_selection_by_byte_wise_suffix
    zip = build_zip([
                      member("readme.md", "notes", deflate: true),
                      member("work.txt", "the text body\n", deflate: true),
                      member("cover.png", "\x89PNG binary".b, deflate: false)
                    ])
    reader = Nabu::ZipReader.new(zip)
    txts = reader.entries.select { |entry| entry.name.match?(/\.txt\z/in) }
    assert_equal 1, txts.size
    assert_equal "the text body\n".b, reader.extract(txts.first).b
  end

  # A prefixed (self-extracting-style) archive shifts every stored offset by the
  # prefix length; the reader recovers the shift from the EOCD.
  def test_prefixed_archive_offsets_are_recovered
    inner = build_zip([member("x.txt", "prefixed content\n", deflate: true)])
    zip = ("SFX STUB PREFIX BYTES" * 8).b + inner
    reader = Nabu::ZipReader.new(zip)
    assert_equal "prefixed content\n".b, reader.extract(reader.entries.first).b
  end

  def test_unsupported_compression_method_raises
    zip = build_zip([member("x.txt", "data", deflate: false, method_override: 99)])
    error = assert_raises(Nabu::ZipReader::Error) { Nabu::ZipReader.new(zip).extract(Nabu::ZipReader.new(zip).entries.first) }
    assert_match(/unsupported compression method 99/, error.message)
  end

  def test_crc_mismatch_raises
    zip = build_zip([member("x.txt", "honest bytes", deflate: true, corrupt_crc: true)])
    reader = Nabu::ZipReader.new(zip)
    error = assert_raises(Nabu::ZipReader::Error) { reader.extract(reader.entries.first) }
    assert_match(/crc mismatch/, error.message)
  end

  def test_zip64_sentinel_in_eocd_raises
    zip = build_zip([member("x.txt", "data", deflate: true)], eocd_total: 0xFFFF)
    error = assert_raises(Nabu::ZipReader::Error) { Nabu::ZipReader.new(zip) }
    assert_match(/zip64/, error.message)
  end

  def test_entry_exposes_the_authoritative_sizes
    content = "count me\n" * 5
    zip = build_zip([member("x.txt", content, deflate: true)])
    entry = Nabu::ZipReader.new(zip).entries.first
    assert_equal content.bytesize, entry.uncompressed_size
    assert_equal Zlib.crc32(content), entry.crc32
  end

  private

  def unzip_p(zip_bytes)
    Dir.mktmpdir("zip-reader-test") do |dir|
      path = File.join(dir, "a.zip")
      File.binwrite(path, zip_bytes)
      Nabu::Shell.run("unzip", "-p", path)
    end
  end

  # A signature-agnostic little-endian field read from a member's local header.
  def local_field(zip, entry, offset)
    zip.byteslice(entry.local_header_offset + offset, 4).unpack1("V")
  end

  # -- a minimal but spec-conformant zip builder --------------------------------

  def member(name, content, deflate:, data_descriptor: false, method_override: nil, corrupt_crc: false)
    content = content.b
    compressed = deflate ? raw_deflate(content) : content
    Member.new(
      name.b, content, method_override || (deflate ? 8 : 0),
      Zlib.crc32(content), compressed, data_descriptor, corrupt_crc
    )
  end

  def raw_deflate(bytes)
    z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    out = z.deflate(bytes, Zlib::FINISH)
    z.close
    out
  end

  # Assemble local headers + members + central directory + EOCD by hand so the
  # data-descriptor and stored variants are exact.
  def build_zip(members, eocd_total: nil)
    body = +"".b
    central = +"".b
    members.each do |mem|
      offset = body.bytesize
      stored_crc = mem.corrupt_crc ? (mem.crc ^ 0xFFFFFFFF) : mem.crc
      body << local_header(mem)
      body << mem.compressed
      body << data_descriptor(mem, stored_crc) if mem.data_descriptor
      central << central_header(mem, offset, stored_crc)
    end
    cd_offset = body.bytesize
    body << central
    body << eocd(members.size, central.bytesize, cd_offset, eocd_total)
    body
  end

  def local_header(mem)
    # Under a data descriptor (bit 3) the local sizes/crc are zero.
    flags = mem.data_descriptor ? 0x0008 : 0
    crc = mem.data_descriptor ? 0 : mem.crc
    csize = mem.data_descriptor ? 0 : mem.compressed.bytesize
    usize = mem.data_descriptor ? 0 : mem.content.bytesize
    ["PK\x03\x04".b, 20, flags, mem.compression, 0, 0, crc, csize, usize, mem.name.bytesize, 0]
      .pack("a4vvvvvVVVvv") + mem.name
  end

  def data_descriptor(mem, crc)
    ["PK\x07\x08".b, crc, mem.compressed.bytesize, mem.content.bytesize].pack("a4VVV")
  end

  def central_header(mem, offset, crc)
    ["PK\x01\x02".b, 20, 20, (mem.data_descriptor ? 0x0008 : 0), mem.compression, 0, 0,
     crc, mem.compressed.bytesize, mem.content.bytesize, mem.name.bytesize, 0, 0, 0, 0, 0, offset]
      .pack("a4vvvvvvVVVvvvvvVV") + mem.name
  end

  def eocd(count, cd_size, cd_offset, total_override)
    total = total_override || count
    ["PK\x05\x06".b, 0, 0, count, total, cd_size, cd_offset, 0].pack("a4vvvvVVv")
  end
end
