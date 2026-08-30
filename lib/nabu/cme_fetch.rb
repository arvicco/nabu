# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Polite autoindex crawl for the Corpus of Middle English (P82-2;
  # architecture §8) — the FIFTH ElephantineFetch/OtdoFetch/CantigasFetch/
  # DeromFetch crawl sibling. medictionary.info (the MED/CME companion site
  # run by the corpus's own editors) serves the whole May-2026 normalized
  # corpus as plain files behind ONE Apache "Index of /texts" listing:
  #
  #   GET <base>/texts/            → autoindex HTML naming every corpus XML
  #                                  (297 files, ~200 MB, one 20 MB outlier)
  #   GET <base>/texts/<name>.xml  → one TCP-schema document
  #
  # DELIBERATELY MIRRORED from DeromFetch, not extracted — the fifth
  # sibling IS the extraction signal those classes flag; extraction stays
  # its own packet, never smuggled into a new-source change. The
  # retry/attic/ledger machinery is line-for-line; the manifest seam
  # differs again (one autoindex listing vs 5 collection listings vs 23
  # letter indexes vs one numbered table).
  #
  # == Why the autoindex, not the Dropbox/Box CME-all.zip
  #
  # Point 3 of medictionary.info offers the same corpus as a bulk zip on
  # Dropbox/Box share links (the U-M institutional folder zips to ~1.96 GB
  # with extras). Share-link tokens fail the automation bar; the /texts/
  # autoindex serves the identical May-2026 files (Last-Modified 2026-05-09
  # across all 297) from stable public URLs — the honest unattended fetch.
  # The grant (P.F. Schaffner, 2026-08-20): "obtain them by any means
  # convenient".
  #
  # == Resume + re-sync posture (the DeromFetch mold)
  #
  # A file already on disk is NOT re-fetched (file-grain resume). The
  # corpus moves in rare wholesale normalization waves (May 2026 was one);
  # refreshing after such a wave means deleting the stale canonical files
  # and re-syncing. A listed-but-404 record is FATAL immediately (the
  # autoindex lists what exists — a hole is real breakage, never censused).
  #
  # == Retention (the house contract)
  #
  #   prepare!   the ONE listing GET — cheap, the live tree untouched;
  #              doomed = on-disk records the listing no longer names.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, download the missing records (each
  #              write tmp+rename), pin the ledger.
  class CmeFetch
    # HTTP failure, a reshaped/outage listing, a non-XML record body, a
    # listed 404, or a persistent 5xx. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".cme-fetch.json"

    # Where records land under the source workdir.
    TEXTS_DIR = "texts"

    # A record href as the autoindex prints it: a bare filename, no path,
    # no query (the ?C=N;O=D sort links and the "/" parent row never match).
    HREF_PATTERN = %r{href="([^"?/]+\.xml)"}

    # The autoindex shape marker a real listing must carry (an outage page
    # or a site reshape has neither this nor any .xml href).
    INDEX_MARKER = "Index of"

    # Seconds between HTTP requests (sequential, polite — a small personal
    # Apache host; ~298 requests ≈ 8–10 minutes at 1 req/s plus transfer).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses. 404 is NOT here — a listed-but-missing record is
    # real breakage, fatal immediately (class note).
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; Corpus of Middle English, " \
                 "grant P.F. Schaffner 2026-08-20; +https://github.com/arvicco/nabu; " \
                 "contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :listed)

    def self.listing_url(base_url)
      "#{base_url}/#{TEXTS_DIR}/"
    end

    def self.record_url(base_url, filename)
      "#{listing_url(base_url)}#{filename}"
    end

    # Is +relpath+ a crawled record ("texts/<file>.xml")? The state file
    # and attic never match.
    def self.record?(relpath)
      parts = relpath.split("/")
      parts.size == 2 && parts.first == TEXTS_DIR && parts.last.end_with?(".xml")
    end

    # One-shot choreography. +guard+ receives the absolute doomed paths
    # between prepare! and complete!.
    def self.sync!(base_url:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, listed: fetch.listed)
    end

    def initialize(base_url:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @manifest = []
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
    end

    attr_reader :atticked, :sha, :fetched, :cached

    def listed = @manifest.size

    # Phase 1 — the one listing GET; live tree untouched. Harvests the
    # filename manifest from the autoindex's own hrefs, runs the
    # reshape defense, computes the doomed set.
    def prepare!
      @progress&.call("CME index #{self.class.listing_url(@base_url)}…\n")
      harvest!(fetch_listing)
      @doomed = doomed_relpaths
    end

    # Absolute live-tree record files the listing no longer names.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, download the missing records, pin the
    # ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      download_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the autoindex listing --------------------------------------------------

    def fetch_listing
      get_with_retry(self.class.listing_url(@base_url), label: "texts index")
    end

    # The hrefs carry the filenames verbatim, so the manifest comes from
    # the page's own claims. A listing without the index shape or without a
    # single record (an outage page or a site reshape) aborts loudly
    # BEFORE any write.
    def harvest!(body)
      names = body.scan(HREF_PATTERN).flatten
      if names.empty? || !body.include?(INDEX_MARKER)
        raise Error,
              "#{self.class.listing_url(@base_url)} is not a corpus autoindex (no .xml hrefs / " \
              "no #{INDEX_MARKER.inspect} shape) — an outage or site reshape; abort before any write"
      end

      @manifest = names.uniq.sort
    end

    # -- the record downloads ---------------------------------------------------

    def download_records!
      FileUtils.mkdir_p(File.join(@dir, TEXTS_DIR))
      @manifest.each_with_index do |filename, index|
        rel = File.join(TEXTS_DIR, filename)
        if File.file?(File.join(@dir, rel))
          @cached += 1
          next
        end

        @progress&.call("CME text #{index + 1}/#{@manifest.size} (#{filename})…\n") if (index % 25).zero?
        body = get_with_retry(self.class.record_url(@base_url, filename), label: rel)
        unless xml_body?(body)
          raise Error, "#{rel}: the response body is not XML — an error page landing where a " \
                       "text should be; nothing written"
        end

        write!(rel, body)
        @fetched += 1
      end
    end

    # A record must BE an XML document (optional UTF-8 BOM tolerated).
    def xml_body?(body)
      body.b.delete_prefix("\xEF\xBB\xBF".b).start_with?("<?xml".b)
    end

    # One GET: 200 wins; 5xx and transport-level failures retry with
    # exponential backoff, then fail loudly; anything else (404 included —
    # the autoindex-consistency posture) is fatal immediately.
    def get_with_retry(url, label:)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure,
                                  headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, 404, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        case response.status
        when 200 then response.body.to_s
        when 404
          raise Error, "HTTP 404 for #{url} — #{label} is listed but missing; the autoindex and " \
                       "the files disagree (fatal, never censused)"
        else raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (#{label}; after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Internal marker for a retriable failure; never escapes get_with_retry.
    class RetriableFailure < StandardError; end

    # RedirectFollow's error channel for one attempt — transport failures
    # and redirect pathologies feed the retry loop; a non-accepted status
    # raises through it too and becomes fatal at the ceiling. Never escapes
    # get_with_retry.
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    # -- landing / ledger -------------------------------------------------------

    def write!(rel, body)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    # Content pin: sorted (relpath, body-sha256) over record files on disk.
    def aggregate_sha
      lines = record_relpaths.sort.map do |rel|
        "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha,
                "listed" => @manifest.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk record files the listing no longer names. The attic (a
    # dot-dir) never matches the glob; the state file never matches the
    # record shape.
    def record_relpaths
      return [] unless Dir.exist?(@dir)

      Dir.glob("#{TEXTS_DIR}/*.xml", base: @dir).select { |rel| self.class.record?(rel) }
    end

    def doomed_relpaths
      keep = @manifest.to_set { |filename| File.join(TEXTS_DIR, filename) }
      record_relpaths.reject { |rel| keep.include?(rel) }
    end

    # First copy wins; the manifest records the pin each file vanished at,
    # in GitFetch's exact format so the adapter base class rediscovers the
    # attic generically.
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
      pin = previous_sha || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end

    def previous_sha
      path = File.join(@dir, STATE_FILE)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))["sha256"]
    rescue JSON::ParserError
      nil
    end
  end
end
