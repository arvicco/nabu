# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "../redirect_follow"
require_relative "remote_zip"
require_relative "zip_fetch"
require_relative "git_fetch"

module Nabu
  # The text members of OpenITI MAKHZAN (Zenodo record 19861912), never its
  # page images. The deposit is one 6.1 GB zip64 archive of 208 STORED
  # per-document zips (Doc<id>.zip: page images + one ALTO XML per page +
  # METS.xml), beside a metadata TSV (one row per page) and release notes.
  # Zenodo honours HTTP Range on the file URL, so the archive is read tail
  # inward (Nabu::RemoteZip): the outer directory, then per SELECTED
  # document its inner directory and exactly its XML members. Measured
  # 2026-11-27 for the 30 Ottoman documents: 2,152,395 bytes in 372
  # requests (the 568 KB TSV and the 17 KB outer directory included; the
  # 279 XML members ~1.56 MB), 248 s; a not-modified re-fetch 2 s. (No git
  # route exists: the OpenITI organisation's github.com/openiti/makhzan
  # repository holds a one-line README only, checked 2026-11-27.)
  #
  # == Contract (the ZipRangeFetch shape)
  #
  #   prepare!   the record API read and checked against the pin (version,
  #              file sizes + md5s); the outer directory read and its
  #              sha256 checked against the pin; the metadata TSV (the
  #              landed copy when its md5 is the pin's, else GET + md5
  #              check) and +select+ over it naming the document ids. The
  #              same pin + selection with every kept file on disk = not
  #              modified (no member is read). Otherwise every selected
  #              document's XML members, inflated + CRC-checked in memory;
  #              doomed = live files not kept any more.
  #   [guard]    the caller's breaker.
  #   complete!  attic the doomed (GitFetch manifest shape), write the kept
  #              files (tmp+rename), delete the doomed, write the state.
  #
  # Layout under +dir+: the TSV at its upstream file name, and per document
  # Doc<id>/<member> exactly as the inner zip names it.
  class MakhzanFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".makhzan-fetch.json"
    RECORD_ID = 19_861_912
    RECORD_VERSION = "2026.1.2"
    RECORD_URL = "https://zenodo.org/api/records/#{RECORD_ID}".freeze
    ZIP_FILE = "OpenITI-Makhzan_Data_2026-1-2.zip"
    METADATA_FILE = "OpenITI-Makhzan_Metadata_2026-1-2.tsv"
    # The XML members of a document zip (ALTO pages + METS); images are not.
    KEEP_MEMBER = %r{\A[^/]+\.xml\z}

    USER_AGENT = "nabu-research-library/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu)".freeze

    # The record version's identity, read off the record 2026-11-27: the
    # file sizes and md5s Zenodo publishes, and the sha256 of the outer
    # zip's central directory (every member's name, size, CRC and offset —
    # the zip's identity without its 6.1 GB). Zenodo records are immutable:
    # a mismatch is corruption or a re-release, an owner re-pin.
    Pin = Data.define(:zip_size, :zip_md5, :directory_sha256, :metadata_size, :metadata_md5)
    # census: 6109859716 / 568495 bytes, 2026-11-27, the record's own file list
    PIN = Pin.new(zip_size: 6_109_859_716, zip_md5: "347a06a5714091665b7292775840a0f0",
                  directory_sha256: "23d6c81b85dcd514394806d369aa59b1fa5a3fc6b2cc252acc9cc9fe2a8bb544",
                  metadata_size: 568_495, metadata_md5: "26e448803e90274a228ebee2a9df7e96")

    Result = Data.define(:sha, :documents, :kept, :skipped, :atticked, :not_modified, :requests, :bytes)

    def self.file_url(name) = "#{RECORD_URL}/files/#{name}/content"

    def self.sync!(dir:, attic_dir:, select:, guard: nil, **)
      fetch = new(dir: dir, attic_dir: attic_dir, select: select, **)
      fetch.prepare!
      guard&.call(fetch.doomed_paths) unless fetch.not_modified?
      fetch.complete!
      fetch.result
    end

    # +select+: the TSV text → the document ids (strings) to take.
    def initialize(dir:, attic_dir:, select:, pin: PIN, http: ZipFetch.default_http, progress: nil)
      @dir = dir
      @attic_dir = attic_dir
      @select = select
      @pin = pin
      @http = http
      @progress = progress
      @kept = {}
      @doomed = []
      @atticked = []
      @documents = []
      @skipped = 0
      @not_modified = false
      @meter = RemoteZip::Meter.new
    end

    def not_modified? = @not_modified

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    def result
      Result.new(sha: @pin.directory_sha256, documents: @documents.size, kept: @kept_count, skipped: @skipped,
                 atticked: @atticked, not_modified: @not_modified, requests: @meter.requests, bytes: @meter.bytes)
    end

    def prepare!
      check_record!
      outer = RemoteZip.new(url: self.class.file_url(ZIP_FILE), http: @http, headers: headers,
                            size: @pin.zip_size, meter: @meter)
      unless outer.directory_sha256 == @pin.directory_sha256
        raise Error, "#{ZIP_FILE}: central directory sha256 #{outer.directory_sha256} is not the pinned " \
                     "#{@pin.directory_sha256} — a changed deposit, an owner re-pin"
      end
      tsv = landed_metadata || metadata!
      ids = @select.call(tsv.dup.force_encoding(Encoding::UTF_8))
      return mark_not_modified! if unchanged?(ids)

      @kept[METADATA_FILE] = tsv
      take_documents!(outer, ids)
      @kept_count = @kept.size
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

    def headers = { "User-Agent" => USER_AGENT }

    # -- the record and its pin ----------------------------------------------------

    def check_record!
      record = JSON.parse(get(RECORD_URL))
      version = record.dig("metadata", "version")
      unless version == RECORD_VERSION
        raise Error,
              "record #{RECORD_ID} is version #{version.inspect}, pinned #{RECORD_VERSION}"
      end

      files = record.fetch("files").to_h { |file| [file["key"], file] }
      check_file!(files, ZIP_FILE, @pin.zip_size, @pin.zip_md5)
      check_file!(files, METADATA_FILE, @pin.metadata_size, @pin.metadata_md5)
    rescue JSON::ParserError, KeyError => e
      raise Error, "record #{RECORD_ID}: unreadable record JSON (#{e.message})"
    end

    def check_file!(files, name, size, md5)
      file = files[name] or raise Error, "record #{RECORD_ID} no longer lists #{name}"
      return if file["size"] == size && file["checksum"] == "md5:#{md5}"

      raise Error,
            "record #{RECORD_ID}: #{name} is #{file['size']} bytes #{file['checksum']}, pinned #{size} md5:#{md5}"
    end

    # The TSV already on disk when its md5 is the pinned one (no re-GET).
    def landed_metadata
      path = File.join(@dir, METADATA_FILE)
      return nil unless File.file?(path)

      bytes = File.binread(path)
      Digest::MD5.hexdigest(bytes) == @pin.metadata_md5 ? bytes : nil
    end

    def metadata!
      bytes = get(self.class.file_url(METADATA_FILE)).b
      unless Digest::MD5.hexdigest(bytes) == @pin.metadata_md5
        raise Error, "#{METADATA_FILE}: md5 #{Digest::MD5.hexdigest(bytes)} is not the pinned #{@pin.metadata_md5}"
      end

      bytes
    end

    def get(url)
      response, = RedirectFollow.get(url, http: @http, error: Error, headers: headers)
      @meter.count(response.body.to_s.bytesize)
      response.body.to_s
    end

    # -- the documents ------------------------------------------------------------

    def take_documents!(outer, ids)
      by_name = outer.entries.to_h { |entry| [entry.name, entry] }
      wanted = ids.map { |id| "Doc#{id}.zip" }
      missing = wanted - by_name.keys
      raise Error, "#{ZIP_FILE} has no member for #{missing.join(', ')}" if missing.any?

      @skipped = by_name.size - wanted.size
      @progress&.call("#{ZIP_FILE}: #{wanted.size} of #{by_name.size} documents by Range…\n")
      wanted.each do |name|
        take_document!(outer.nested(by_name.fetch(name)), File.basename(name, ".zip"))
        @documents << name
      end
    end

    def take_document!(inner, doc_dir)
      inner.entries.each do |entry|
        next if entry.name.end_with?("/")

        unless KEEP_MEMBER.match?(entry.name)
          @skipped += 1
          next
        end

        @kept[File.join(doc_dir, entry.name)] = inner.read(entry)
      end
    end

    # -- landing / retention ---------------------------------------------------------

    # Same deposit, same selection, every kept file still on disk.
    def unchanged?(ids)
      state = read_state
      state["directory_sha256"] == @pin.directory_sha256 && state["metadata_md5"] == @pin.metadata_md5 &&
        state["documents"] == ids.map { |id| "Doc#{id}.zip" } &&
        Array(state["members"]).any? && state["members"].all? { |rel| File.file?(File.join(@dir, rel)) }
    end

    def mark_not_modified!
      state = read_state
      @not_modified = true
      @kept_count = state["members"].size
      @documents = Array(state["documents"])
      @skipped = state["skipped"].to_i
    end

    def live_files
      return [] unless Dir.exist?(@dir)

      Dir.glob("**/*", base: @dir).select { |rel| File.file?(File.join(@dir, rel)) } - [STATE_FILE]
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
      pin = read_state["directory_sha256"] || "pre-#{@pin.directory_sha256}"
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
      state = { "record" => RECORD_ID, "version" => RECORD_VERSION, "zip_size" => @pin.zip_size,
                "directory_sha256" => @pin.directory_sha256, "metadata_md5" => @pin.metadata_md5,
                "documents" => @documents, "members" => @kept.keys.sort, "skipped" => @skipped,
                "requests" => @meter.requests, "bytes" => @meter.bytes, "fetched_at" => Time.now.utc.iso8601 }
      FileUtils.mkdir_p(@dir)
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end
  end
end
