# frozen_string_literal: true

require "zlib"

module Nabu
  # A dependency-free, in-process single-archive ZIP reader (P39-3).
  #
  # WHY THIS EXISTS: the aozora adapter unzips one member per work, and the
  # live rebuild forked a `unzip` subprocess ~17k times (one fork+exec per
  # work) — the load-cost hotspot. This reader replaces that subprocess with
  # stdlib Zlib, so extraction stays in-process.
  #
  # == Parse the structure HONESTLY, never scan for PK\x03\x04
  #
  # A ZIP is read from its tail inward, NOT by scanning forward for local
  # file-header signatures, because a naive scan is provably wrong:
  #
  #   * DATA DESCRIPTORS (general-purpose bit 3): when set, the local file
  #     header's crc-32 and compressed/uncompressed sizes are written as ZERO
  #     and the real values trail the file data in a "data descriptor" record
  #     (optionally led by PK\x07\x08). A forward scan therefore cannot know
  #     where a member's compressed data ends — only the central directory
  #     carries the authoritative compressed size.
  #   * NESTED BYTES: compressed (or stored) member data can contain the four
  #     bytes PK\x03\x04 by pure coincidence, so scanning for that signature
  #     yields false local-header matches.
  #
  # The central directory (written last, after every member) is the single
  # authoritative index: it lists each member's name, compression method,
  # compressed size and the offset of its local header. So the read order is
  #   End-Of-Central-Directory record  →  Central Directory  →  Local headers.
  #
  # == Member names are junk-bytes-in-the-wild (P38-i1)
  #
  # The owner's canonical aozora zips include a member name invalid in UTF-8
  # AND in CP932 (51135_ruby_65180.zip). Names are therefore kept BINARY and
  # NEVER decoded — the NFC boundary is for text, not for upstream filename
  # bytes. Callers select a member with byte-wise (/…/n) matching.
  #
  # == Compression
  #
  # Method 0 (stored) = a raw byte slice; method 8 (deflate) = Zlib::Inflate
  # with windowBits -15 (raw DEFLATE, no zlib header — the RFC-1951 stream the
  # ZIP format embeds). Any other method, a truncated/absent central
  # directory, a bad offset, a CRC-32 mismatch, or a zip64 archive raises
  # Nabu::ZipReader::Error — which each caller maps to its own quarantine /
  # abort contract (the aozora ParseError, the index FetchError).
  class ZipReader
    # Any structural defect: no EOCD, a bad signature, an unsupported method,
    # a CRC mismatch, or a zip64 archive. Callers rescue this one class.
    class Error < Nabu::Error; end

    # A central-directory entry. +name+ is BINARY (never decoded). Sizes and
    # offset are the central directory's authoritative values (the local
    # header's are unreliable under a data descriptor).
    Entry = Data.define(:name, :compression, :crc32, :compressed_size, :uncompressed_size, :local_header_offset)

    EOCD_SIGNATURE = "PK\x05\x06".b
    CENTRAL_SIGNATURE = "PK\x01\x02".b
    LOCAL_SIGNATURE = "PK\x03\x04".b
    EOCD_MIN_SIZE = 22           # fixed part, before the variable-length comment
    MAX_COMMENT = 0xFFFF         # a 2-byte comment-length field caps the tail scan
    ZIP64_SENTINEL_32 = 0xFFFFFFFF
    ZIP64_SENTINEL_16 = 0xFFFF
    METHOD_STORED = 0
    METHOD_DEFLATE = 8
    RAW_DEFLATE_WINDOW = -Zlib::MAX_WBITS # -15: raw DEFLATE, no zlib/gzip wrapper

    # +bytes+ is the whole archive; a binary copy is taken so slicing and
    # signature comparison are byte-exact regardless of the caller's encoding.
    def initialize(bytes)
      @bytes = bytes.b
      @entries = read_central_directory
    end

    # Every member, in central-directory order.
    attr_reader :entries

    # Decompressed BINARY content of +entry+. Reads the member's LOCAL header
    # (whose name/extra-field lengths locate the data — these legitimately
    # differ from the central directory's extra field), slices exactly the
    # central directory's compressed size, and inflates method 8 (verifying
    # the CRC-32 against the central directory, as `unzip` does).
    def extract(entry)
      offset = entry.local_header_offset
      raise Error, "bad local file header at offset #{offset}" unless @bytes.byteslice(offset, 4) == LOCAL_SIGNATURE

      name_len = u16(offset + 26)
      extra_len = u16(offset + 28)
      data_start = offset + 30 + name_len + extra_len
      compressed = @bytes.byteslice(data_start, entry.compressed_size)
      if compressed.nil? || compressed.bytesize != entry.compressed_size
        raise Error, "member data truncated (#{entry.name.inspect})"
      end

      output = inflate(compressed, entry)
      verify_crc!(output, entry)
      output
    end

    private

    # Locate and parse the central directory via the End-Of-Central-Directory
    # record found in the archive tail.
    def read_central_directory
      eocd = find_eocd
      total = u16(eocd + 10)
      cd_size = u32(eocd + 12)
      cd_offset = u32(eocd + 16)
      if [cd_size, cd_offset].include?(ZIP64_SENTINEL_32) || total == ZIP64_SENTINEL_16
        raise Error, "zip64 archives are not supported"
      end

      # A self-extracting or otherwise prefixed archive shifts every stored
      # offset by the prefix size; recover it from where the CD actually sits
      # (eocd - cd_size) vs where the record claims it starts (cd_offset).
      base = eocd - cd_size - cd_offset
      parse_central_entries(cd_offset + base, total, base)
    end

    # Scan the tail for the EOCD signature. It is followed by a fixed 22-byte
    # record plus a variable comment (≤ 0xFFFF), so the signature can sit at
    # most EOCD_MIN_SIZE + MAX_COMMENT bytes from the end. Take the LAST match
    # whose declared comment length reaches exactly end-of-file — guarding the
    # rare case where the signature's four bytes recur inside the comment.
    def find_eocd
      window = EOCD_MIN_SIZE + MAX_COMMENT
      search_from = [@bytes.bytesize - window, 0].max
      scan = @bytes.byteslice(search_from, @bytes.bytesize - search_from)
      position = scan.bytesize
      loop do
        position = scan.rindex(EOCD_SIGNATURE, position - 1)
        raise Error, "end-of-central-directory signature not found (not a zip archive?)" if position.nil?

        eocd = search_from + position
        comment_len = u16(eocd + 20)
        return eocd if eocd + EOCD_MIN_SIZE + comment_len == @bytes.bytesize
      end
    end

    def parse_central_entries(offset, total, base)
      entries = []
      total.times do
        unless @bytes.byteslice(offset, 4) == CENTRAL_SIGNATURE
          raise Error, "bad central directory header at offset #{offset}"
        end

        name_len = u16(offset + 28)
        extra_len = u16(offset + 30)
        comment_len = u16(offset + 32)
        entries << Entry.new(
          name: @bytes.byteslice(offset + 46, name_len),
          compression: u16(offset + 10),
          crc32: u32(offset + 16),
          compressed_size: u32(offset + 20),
          uncompressed_size: u32(offset + 24),
          local_header_offset: u32(offset + 42) + base
        )
        offset += 46 + name_len + extra_len + comment_len
      end
      entries
    end

    def inflate(compressed, entry)
      case entry.compression
      when METHOD_STORED
        compressed
      when METHOD_DEFLATE
        begin
          Zlib::Inflate.new(RAW_DEFLATE_WINDOW).inflate(compressed)
        rescue Zlib::Error => e
          raise Error, "inflate failed (#{entry.name.inspect}): #{e.message}"
        end
      else
        raise Error, "unsupported compression method #{entry.compression} (#{entry.name.inspect})"
      end
    end

    def verify_crc!(output, entry)
      # The central directory carries the true CRC even under a data descriptor
      # (it is written after the member); a zero recorded CRC means the archive
      # declined to assert one, so there is nothing to check against.
      return if entry.crc32.zero?

      actual = Zlib.crc32(output)
      return if actual == entry.crc32

      raise Error, format("crc mismatch (%<name>s): expected %<want>08x, got %<got>08x",
                          name: entry.name.inspect, want: entry.crc32, got: actual)
    end

    def u16(offset) = @bytes.byteslice(offset, 2).unpack1("v")

    def u32(offset) = @bytes.byteslice(offset, 4).unpack1("V")
  end
end
