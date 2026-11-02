# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "zlib"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"

module Nabu
  # SELECTED members of a remote zip, read with HTTP Range requests (P153;
  # first consumer the Baley excavated-manuscript alignment deposits on
  # Zenodo, whose 38–570 MB zips are ~99% manuscript-image crops beside a
  # few MB of JSON). The archive is read the honest way, tail inward
  # (Nabu::ZipReader's doctrine): the End-Of-Central-Directory record, then
  # the central directory, then — per kept member — its local header and
  # exactly its compressed bytes. An excluded member's bytes are never
  # requested.
  #
  # == Contract
  #
  #   prepare!   size probe (bytes=0-0 → Content-Range), EOCD, directory;
  #              the directory's sha256 is the archive identity — equal to
  #              the stored pin with every kept file on disk = not modified.
  #              Otherwise every kept member is fetched, inflated and CRC-32
  #              checked IN MEMORY; doomed = live files not kept any more.
  #   [guard]    the caller's breaker.
  #   complete!  attic the doomed (GitFetch manifest shape), write the kept
  #              members (tmp+rename), delete the doomed, write the state.
  #
  # Member names lose the archive's single top directory when there is one
  # (the ZipFetch layout rule). Zip64, encrypted members and methods other
  # than stored/deflate raise Error, as does a server answering a Range
  # request with anything but 206 (no silent whole-archive download).
  class ZipRangeFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".zip-range-fetch.json"

    # const: the EOCD record's fixed size (ZIP format), not a corpus count
    EOCD_BYTES = 22
    # const: the EOCD record + the 64 KiB comment cap (ZIP format), not a corpus count
    TAIL_BYTES = EOCD_BYTES + 0xFFFF
    # const: ZIP format signatures and sentinels, not a corpus claim
    EOCD_SIGNATURE = "PK\x05\x06".b
    CENTRAL_SIGNATURE = "PK\x01\x02".b
    LOCAL_SIGNATURE = "PK\x03\x04".b
    ZIP64_32 = 0xFFFFFFFF
    METHODS = { 0 => :stored, 8 => :deflate }.freeze

    Entry = Data.define(:name, :compression, :flags, :crc32, :compressed_size, :uncompressed_size,
                        :local_header_offset)
    Result = Data.define(:sha, :size, :kept, :skipped, :atticked, :not_modified)

    def self.sync!(url:, dir:, attic_dir:, select:, guard: nil, **)
      fetch = new(url: url, dir: dir, attic_dir: attic_dir, select: select, **)
      fetch.prepare!
      guard&.call(fetch.doomed_paths) unless fetch.not_modified?
      fetch.complete!
      fetch.result
    end

    def initialize(url:, dir:, attic_dir:, select:, http: ZipFetch.default_http, progress: nil)
      @url = url
      @dir = dir
      @attic_dir = attic_dir
      @select = select
      @http = http
      @progress = progress
      @kept = {}
      @doomed = []
      @atticked = []
      @skipped = 0
      @not_modified = false
    end

    def not_modified? = @not_modified

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    def result
      Result.new(sha: @sha, size: @size, kept: @kept_count, skipped: @skipped, atticked: @atticked,
                 not_modified: @not_modified)
    end

    def prepare!
      @size = archive_size
      entries = read_directory
      top = single_top(entries)
      files = entries.reject { |entry| entry.name.end_with?("/") }
      chosen = files.filter_map do |entry|
        rel = top ? entry.name.delete_prefix(top) : entry.name
        @select.call(rel) ? [rel, entry] : nil
      end
      @skipped = files.size - chosen.size
      @kept_count = chosen.size
      if unchanged?(chosen.map(&:first))
        @not_modified = true
        return
      end

      @progress&.call("#{@url}: #{chosen.size} of #{files.size} members by Range…\n")
      chosen.each { |rel, entry| @kept[rel] = extract(entry) }
      @doomed = live_files - @kept.keys
    end

    def complete!
      return if @not_modified

      attic_doomed!
      @kept.each { |rel, bytes| write!(rel, bytes) }
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_state!
    end

    private

    # -- the archive structure -----------------------------------------------------

    def archive_size
      _body, headers = ranged(0, 0)
      total = headers["content-range"].to_s[%r{/(\d+)\z}, 1]
      raise Error, "#{@url}: no Content-Range total on the size probe" unless total

      Integer(total)
    end

    # The EOCD record: the last 22 bytes when the archive has no comment
    # (the norm), else found by scanning the 64 KiB tail.
    def read_directory
      tail, = ranged([@size - EOCD_BYTES, 0].max, @size - 1)
      tail, = ranged([@size - TAIL_BYTES, 0].max, @size - 1) unless tail.start_with?(EOCD_SIGNATURE)
      eocd = tail.rindex(EOCD_SIGNATURE) or raise Error, "#{@url}: no End-Of-Central-Directory record"
      count, cd_size, cd_offset = tail.byteslice(eocd + 10, 10).unpack("vVV")
      raise Error, "#{@url}: a zip64 archive (unsupported)" if [cd_size, cd_offset].include?(ZIP64_32)

      directory, = ranged(cd_offset, cd_offset + cd_size - 1)
      @sha = Digest::SHA256.hexdigest(directory)
      entries = parse_directory(directory)
      raise Error, "#{@url}: directory lists #{entries.size} members, EOCD says #{count}" unless entries.size == count

      entries
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
      raise Error, "#{@url}: a zip64 member (unsupported)" if [csize, usize, offset].include?(ZIP64_32)

      entry = Entry.new(name: bytes.byteslice(pos + 46, nlen).force_encoding(Encoding::UTF_8), compression: method,
                        flags: flags, crc32: crc, compressed_size: csize, uncompressed_size: usize,
                        local_header_offset: offset)
      [entry, pos + 46 + nlen + xlen + clen]
    end

    def single_top(entries)
      tops = entries.map { |entry| entry.name.split("/", 2).first }.uniq
      return nil unless tops.size == 1 && entries.all? { |entry| entry.name.include?("/") }

      "#{tops.first}/"
    end

    def extract(entry)
      raise Error, "#{@url}: #{entry.name} is encrypted" if entry.flags.anybits?(1)

      kind = METHODS[entry.compression] or raise Error, "#{@url}: #{entry.name} uses method #{entry.compression}"
      header, = ranged(entry.local_header_offset, entry.local_header_offset + 29)
      raise Error, "#{@url}: bad local header for #{entry.name}" unless header.byteslice(0, 4) == LOCAL_SIGNATURE

      nlen, xlen = header.byteslice(26, 4).unpack("vv")
      start = entry.local_header_offset + 30 + nlen + xlen
      data = entry.compressed_size.zero? ? "".b : ranged(start, start + entry.compressed_size - 1).first
      bytes = kind == :deflate ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) : data
      raise Error, "#{@url}: #{entry.name} fails its CRC-32" unless Zlib.crc32(bytes) == entry.crc32

      bytes
    rescue Zlib::Error => e
      raise Error, "#{@url}: #{entry.name} does not inflate (#{e.message})"
    end

    def ranged(first, last)
      response, = RedirectFollow.get(@url, http: @http, error: Error, headers: { "Range" => "bytes=#{first}-#{last}" },
                                           accept: [200, 206])
      unless response.status == 206
        raise Error, "#{@url}: the server answered a Range request with HTTP #{response.status} — refusing " \
                     "to read the whole archive"
      end

      [response.body.to_s.b, response.headers]
    end

    # -- landing / retention ---------------------------------------------------------

    def unchanged?(rels)
      state = read_state
      state["sha256"] == @sha && state["url"] == @url && rels.all? { |rel| File.file?(File.join(@dir, rel)) }
    end

    def live_files
      return [] unless Dir.exist?(@dir)

      Dir.glob("**/*", base: @dir).select { |rel| File.file?(File.join(@dir, rel)) }
    end

    def write!(rel, bytes)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", bytes)
      File.rename("#{target}.tmp", target)
    end

    def attic_doomed!
      @doomed.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next unless File.file?(source)
        next if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
      record_attic_manifest! unless @atticked.empty?
    end

    def record_attic_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      pin = read_state["sha256"] || "pre-#{@sha}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      File.write(path, JSON.pretty_generate(manifest))
    end

    def read_state
      path = File.join(@dir, STATE_FILE)
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    rescue JSON::ParserError
      {}
    end

    def write_state!
      state = { "url" => @url, "sha256" => @sha, "size" => @size, "members" => @kept.keys.sort,
                "skipped" => @skipped, "fetched_at" => Time.now.utc.iso8601, "last_modified" => nil }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end
  end
end
