# frozen_string_literal: true

require "digest"
require "zlib"

require_relative "../redirect_follow"
require_relative "zip_fetch"

module Nabu
  # A remote zip read by HTTP Range, tail inward — the reader half of
  # Nabu::ZipRangeFetch's doctrine, grown the two things that class refuses:
  #
  # - ZIP64. An archive past 4 GiB (or 65,535 members) parks 0xFFFFFFFF /
  #   0xFFFF sentinels in its End-Of-Central-Directory record and keeps the
  #   real values in the zip64 EOCD (found through its locator, the 20 bytes
  #   before the EOCD), and per member in the 0x0001 extra field.
  # - NESTED archives. A STORED member that is itself a zip is a contiguous
  #   byte window of the outer file; #nested answers a RemoteZip over that
  #   window, so an inner member is reached without reading the rest of the
  #   inner archive (OpenITI MAKHZAN: one 6.1 GB zip of 208 stored per-
  #   document zips, each mostly page images beside a few kB of ALTO).
  #
  # Every member read is one request (local header + data, sized from the
  # directory's extra length; a second request only when the local header's
  # extra differs) and CRC-32 checked. A server answering a Range request
  # with anything but 206 raises — never a silent whole-archive download.
  # +meter+ counts requests and bytes across a reader and its windows.
  class RemoteZip
    class Error < Nabu::Error; end

    # const: ZIP format record sizes, signatures and sentinels, not corpus claims
    EOCD_BYTES = 22
    LOCATOR_BYTES = 20
    EOCD64_BYTES = 56
    LOCAL_BYTES = 30
    TAIL_BYTES = EOCD_BYTES + 0xFFFF
    EOCD_SIGNATURE = "PK\x05\x06".b
    LOCATOR_SIGNATURE = "PK\x06\x07".b
    EOCD64_SIGNATURE = "PK\x06\x06".b
    CENTRAL_SIGNATURE = "PK\x01\x02".b
    LOCAL_SIGNATURE = "PK\x03\x04".b
    ZIP64_32 = 0xFFFFFFFF
    ZIP64_16 = 0xFFFF
    ZIP64_EXTRA = 0x0001
    METHODS = { 0 => :stored, 8 => :deflate }.freeze

    Entry = Data.define(:name, :compression, :flags, :crc32, :compressed_size, :uncompressed_size,
                        :local_header_offset, :extra_length)

    # Requests and bytes transferred, shared by a reader and its windows.
    class Meter
      attr_reader :requests, :bytes

      def initialize
        @requests = 0
        @bytes = 0
      end

      def count(bytes)
        @requests += 1
        @bytes += bytes
      end
    end

    attr_reader :url, :meter

    # +offset+/+size+ bound a window of the remote file (a nested archive);
    # without +size+ the whole file is the archive and a bytes=0-0 probe
    # reads its length from Content-Range.
    def initialize(url:, http: ZipFetch.default_http, headers: {}, offset: 0, size: nil, meter: Meter.new)
      @url = url
      @http = http
      @headers = headers
      @offset = offset
      @size = size
      @meter = meter
    end

    def size = @size ||= probe_size

    # The central directory's members, in directory order (memoized).
    def entries
      @entries ||= read_directory
    end

    # sha256 of the central-directory bytes — the archive's identity (every
    # member's name, size, CRC and offset) without reading the members.
    def directory_sha256
      entries
      @directory_sha256
    end

    # The member's bytes, inflated and CRC-32 checked.
    def read(entry)
      raise Error, "#{@url}: #{entry.name} is encrypted" if entry.flags.anybits?(1)

      kind = METHODS[entry.compression] or raise Error, "#{@url}: #{entry.name} uses method #{entry.compression}"
      data = member_data(entry)
      bytes = kind == :deflate ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) : data
      raise Error, "#{@url}: #{entry.name} fails its CRC-32" unless Zlib.crc32(bytes) == entry.crc32

      bytes
    rescue Zlib::Error => e
      raise Error, "#{@url}: #{entry.name} does not inflate (#{e.message})"
    end

    # A RemoteZip over a STORED member's bytes (an archive inside the archive).
    def nested(entry)
      unless METHODS[entry.compression] == :stored
        raise Error, "#{@url}: #{entry.name} is compressed — only a stored member is a readable window"
      end

      start = data_start(entry, ranged(entry.local_header_offset, entry.local_header_offset + LOCAL_BYTES - 1))
      self.class.new(url: @url, http: @http, headers: @headers, offset: @offset + entry.local_header_offset + start,
                     size: entry.compressed_size, meter: @meter)
    end

    private

    # -- the archive structure -----------------------------------------------------

    def probe_size
      _body, headers = raw_ranged(0, 0)
      total = headers["content-range"].to_s[%r{/(\d+)\z}, 1]
      raise Error, "#{@url}: no Content-Range total on the size probe" unless total

      Integer(total)
    end

    # The EOCD record: the last 22 bytes when the archive has no comment
    # (the norm), else found by scanning the 64 KiB tail. The zip64 records
    # (locator + EOCD64) precede it; they ride the same read when present.
    def read_directory
      tail_start = [size - EOCD_BYTES - LOCATOR_BYTES - EOCD64_BYTES, 0].max
      tail = ranged(tail_start, size - 1)
      unless tail.bytesize >= EOCD_BYTES && tail.byteslice(-EOCD_BYTES, 4) == EOCD_SIGNATURE
        tail_start = [size - TAIL_BYTES - LOCATOR_BYTES - EOCD64_BYTES, 0].max
        tail = ranged(tail_start, size - 1)
      end
      eocd = tail.rindex(EOCD_SIGNATURE) or raise Error, "#{@url}: no End-Of-Central-Directory record"
      count, cd_size, cd_offset = tail.byteslice(eocd + 10, 10).unpack("vVV")
      if count == ZIP64_16 || [cd_size, cd_offset].include?(ZIP64_32)
        count, cd_size, cd_offset = zip64_directory(tail, tail_start, eocd)
      end

      directory = ranged(cd_offset, cd_offset + cd_size - 1)
      @directory_sha256 = Digest::SHA256.hexdigest(directory)
      entries = parse_directory(directory)
      raise Error, "#{@url}: directory lists #{entries.size} members, EOCD says #{count}" unless entries.size == count

      entries
    end

    # [count, cd_size, cd_offset] from the zip64 EOCD named by the locator.
    def zip64_directory(tail, tail_start, eocd)
      locator = eocd - LOCATOR_BYTES
      unless locator >= 0 && tail.byteslice(locator, 4) == LOCATOR_SIGNATURE
        raise Error, "#{@url}: zip64 sentinels without a zip64 locator"
      end

      at = tail.byteslice(locator + 8, 8).unpack1("Q<")
      record = if at >= tail_start && at + EOCD64_BYTES <= tail_start + tail.bytesize
                 tail.byteslice(at - tail_start, EOCD64_BYTES)
               else
                 ranged(at, at + EOCD64_BYTES - 1)
               end
      raise Error, "#{@url}: bad zip64 End-Of-Central-Directory record" unless record.start_with?(EOCD64_SIGNATURE)

      record.byteslice(32, 24).unpack("Q<Q<Q<")
    end

    def parse_directory(bytes)
      entries = []
      pos = 0
      while pos < bytes.bytesize
        unless bytes.byteslice(pos, 4) == CENTRAL_SIGNATURE
          raise Error, "#{@url}: bad central-directory signature at #{pos}"
        end

        entry, pos = directory_entry(bytes, pos)
        entries << entry
      end
      entries
    end

    def directory_entry(bytes, pos)
      flags, method, _time, _date, crc, csize, usize, nlen, xlen, clen =
        bytes.byteslice(pos + 8, 26).unpack("vvvvVVVvvv")
      offset = bytes.byteslice(pos + 42, 4).unpack1("V")
      name = bytes.byteslice(pos + 46, nlen).force_encoding(Encoding::UTF_8)
      usize, csize, offset = widen(bytes.byteslice(pos + 46 + nlen, xlen), name, usize, csize, offset)
      entry = Entry.new(name: name, compression: method, flags: flags, crc32: crc, compressed_size: csize,
                        uncompressed_size: usize, local_header_offset: offset, extra_length: xlen)
      [entry, pos + 46 + nlen + xlen + clen]
    end

    # The zip64 extra field (0x0001) carries, in this order, exactly the
    # values whose 32-bit slots hold the sentinel.
    def widen(extra, name, usize, csize, offset)
      return [usize, csize, offset] unless [usize, csize, offset].include?(ZIP64_32)

      values = zip64_values(extra) or raise Error, "#{@url}: #{name} has zip64 sentinels without a zip64 extra"
      usize = values.shift if usize == ZIP64_32
      csize = values.shift if csize == ZIP64_32
      offset = values.shift if offset == ZIP64_32
      raise Error, "#{@url}: #{name}'s zip64 extra is short" if [usize, csize, offset].include?(nil)

      [usize, csize, offset]
    end

    def zip64_values(extra)
      pos = 0
      while pos + 4 <= extra.bytesize
        id, len = extra.byteslice(pos, 4).unpack("vv")
        return extra.byteslice(pos + 4, len).unpack("Q<*") if id == ZIP64_EXTRA

        pos += 4 + len
      end
      nil
    end

    # -- member bytes -------------------------------------------------------------

    def member_data(entry)
      first = entry.local_header_offset
      guess = LOCAL_BYTES + entry.name.bytesize + entry.extra_length
      blob = ranged(first, first + guess + entry.compressed_size - 1)
      start = data_start(entry, blob)
      return blob.byteslice(start, entry.compressed_size) if start + entry.compressed_size <= blob.bytesize
      return "".b if entry.compressed_size.zero?

      ranged(first + start, first + start + entry.compressed_size - 1)
    end

    # The data's offset from the local header (its own name + extra lengths).
    def data_start(entry, header)
      raise Error, "#{@url}: bad local header for #{entry.name}" unless header.byteslice(0, 4) == LOCAL_SIGNATURE

      nlen, xlen = header.byteslice(26, 4).unpack("vv")
      LOCAL_BYTES + nlen + xlen
    end

    # Bytes first..last of THIS archive (window-relative).
    def ranged(first, last)
      if first.negative? || last >= size
        raise Error,
              "#{@url}: read #{first}-#{last} outside the archive (#{size} bytes)"
      end

      raw_ranged(@offset + first, @offset + last).first
    end

    def raw_ranged(first, last)
      response, = RedirectFollow.get(@url, http: @http, error: Error,
                                           headers: @headers.merge("Range" => "bytes=#{first}-#{last}"),
                                           accept: [200, 206])
      unless response.status == 206
        raise Error, "#{@url}: the server answered a Range request with HTTP #{response.status} — refusing " \
                     "to read the whole archive"
      end

      body = response.body.to_s.b
      @meter.count(body.bytesize)
      [body, response.headers]
    end
  end
end
