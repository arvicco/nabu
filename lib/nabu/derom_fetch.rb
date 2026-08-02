# frozen_string_literal: true

require "digest"
require "erb"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Polite collection-index crawl for the DÉRom Ortolang workspace (P56-4;
  # architecture §8) — the FOURTH ElephantineFetch/OtdoFetch/CantigasFetch
  # HTML-crawl sibling. The Ortolang diffusion content API serves
  # Apache-style index pages per collection:
  #
  #   GET <base>/<collection>            (base = …/api/content/derom/latest)
  #     → "Index of" HTML whose hrefs name every article XML verbatim
  #       (literal spaces and apostrophes in the href paths).
  #   GET <base>/<collection>/<file>.xml  per article (segments
  #     percent-encoded on request; upstream hrefs are unencoded).
  #
  # DELIBERATELY MIRRORED from CantigasFetch, not extracted — the fourth
  # sibling IS the extraction signal those classes flag; extraction stays
  # its own packet, never smuggled into a new-source change. The
  # retry/attic/ledger machinery is line-for-line; the manifest seam
  # differs again (5 collection listings vs 23 letter indexes vs one
  # numbered table vs one session POST).
  #
  # == The auth-gate ground truth (census 2026-08-02)
  #
  # Only FIVE of the workspace's collections are openly served; "4 Fichiers
  # XML articles DERom 4" (the future DÉRom 4) and "7 Fichiers XML Articles
  # en anglais" answer HTTP 303 → auth.ortolang.fr (Keycloak login).
  # COLLECTIONS enumerates the open five ONLY, and two body-shape defenses
  # guard the seam: a listing must look like an index ("Index of" + at
  # least one .xml href) or the crawl aborts BEFORE any write, and a
  # downloaded record must BE XML ("<?xml" prefix) or the crawl dies — a
  # login page never lands as an article.
  #
  # == Resume + re-sync posture
  #
  # The workspace is a versioned archive (snapshot 4, tag v1; next upstream
  # refresh announced for September 2026). A file already on disk is NOT
  # re-fetched (file-grain resume, the CantigasFetch mold); refreshing after
  # an upstream snapshot means deleting the canonical dir — or the stale
  # files — and re-syncing. A listed-but-404 record is FATAL immediately
  # (never censused): the archive's listings and content are consistent, so
  # a hole is real breakage.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the 5 listing GETs only — cheap, the live tree untouched;
  #              doomed = on-disk records no listing names.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, download the missing records (each
  #              write tmp+rename), pin the ledger.
  #
  # Listings are live-rendered index pages, not corpus content — they are
  # never persisted and stay out of the ledger pin (aggregate sha256 over
  # the sorted (relpath, body-sha) record set).
  class DeromFetch
    # HTTP failure, an auth-gated/reshaped listing, a non-XML record body,
    # a listed 404, or a persistent 5xx. Adapters wrap it in
    # Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".derom-fetch.json"

    # The OPEN collections of the `derom` workspace, names verbatim
    # (collections 4 and 7 are auth-gated — class note).
    # const: the upstream open-collection roster, re-censused on drift
    COLLECTIONS = [
      "1 Fichiers XML articles DERom 1",
      "2 Fichiers XML articles DERom 2",
      "3 Fichiers XML articles DERom 3",
      "5 Fichiers XML articles de renvoi a Mertens 2021",
      "6 Fichiers XML articles potiches en attente"
    ].freeze

    # An article href as the index pages print it (path segments unencoded).
    HREF_PATTERN = %r{href="/api/content/[^/"]+/[^/"]+/([^/"]+)/([^/"]+\.xml)"}

    # The index-page shape marker a real listing must carry (the Keycloak
    # login page an auth-gated collection serves has neither this nor any
    # .xml href).
    INDEX_MARKER = "Index of"

    # Seconds between HTTP requests (sequential, polite — a CNRS
    # infrastructure host; ~520 requests ≈ 9 minutes at 1 req/s).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses. 404 is NOT here — a listed-but-missing record in
    # a versioned archive is real breakage, fatal immediately (class note).
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; DÉRom Ortolang workspace, " \
                 "CC BY-NC-SA 4.0; correspondence with É. Buchi 2026-07-29; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count)

    # The collection listing URL — the segment percent-encoded (upstream
    # names carry spaces; ERB::Util.url_encode gives %20, never +).
    def self.collection_url(base_url, collection)
      "#{base_url}/#{ERB::Util.url_encode(collection)}"
    end

    def self.record_url(base_url, collection, filename)
      "#{collection_url(base_url, collection)}/#{ERB::Util.url_encode(filename)}"
    end

    # Is +relpath+ a crawled record ("<collection>/<file>.xml")? The state
    # file and attic never match.
    def self.record?(relpath)
      parts = relpath.split("/")
      parts.size == 2 && parts.last.end_with?(".xml")
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
                 cached: fetch.cached, records: fetch.records, manifest_count: fetch.manifest_count)
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

    def manifest_count = @manifest.size
    def records = @manifest.size

    # Phase 1 — the 5 listing GETs only; live tree untouched. Harvests the
    # (collection, filename) manifest from the hrefs themselves (the pages
    # are self-describing), runs the auth-gate/reshape defense, computes
    # the doomed set.
    def prepare!
      COLLECTIONS.each do |collection|
        @progress&.call("DÉRom index #{collection}…\n")
        harvest!(collection, fetch_listing(collection))
      end
      @manifest = @manifest.uniq.sort
      @doomed = doomed_relpaths
    end

    # Absolute live-tree record files no listing names.
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

    # -- the collection listings ------------------------------------------------

    def fetch_listing(collection)
      get_with_retry(self.class.collection_url(@base_url, collection), label: collection)
    end

    # The hrefs carry the collection and filename verbatim (unencoded), so
    # the manifest comes from the page's own claims. A listing without the
    # index shape or without a single article is what an auth gate (303 →
    # Keycloak login, followed transparently) or an upstream reshape
    # serves — abort loudly BEFORE any write.
    def harvest!(collection, body)
      pairs = body.scan(HREF_PATTERN)
      if pairs.empty? || !body.include?(INDEX_MARKER)
        raise Error,
              "listing #{collection.inspect} is not an article index (no .xml hrefs / no " \
              "#{INDEX_MARKER.inspect} shape) — an auth-gated or reshaped collection; " \
              "abort before any write"
      end

      @manifest.concat(pairs)
    end

    # -- the record downloads ---------------------------------------------------

    def download_records!
      FileUtils.mkdir_p(@dir)
      @manifest.each_with_index do |(collection, filename), index|
        rel = File.join(collection, filename)
        if File.file?(File.join(@dir, rel))
          @cached += 1
          next
        end

        @progress&.call("DÉRom article #{index + 1}/#{@manifest.size} (#{filename})…\n") if (index % 25).zero?
        body = get_with_retry(self.class.record_url(@base_url, collection, filename), label: rel)
        unless xml_body?(body)
          raise Error, "#{rel}: the response body is not XML — a login or error page landing " \
                       "where an article should be; nothing written"
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
    # the versioned-archive posture) is fatal immediately.
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
          raise Error, "HTTP 404 for #{url} — #{label} is listed but missing; the archive's " \
                       "listings and content disagree (fatal, never censused)"
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
    # (404 among them) raises through it too and becomes fatal at the
    # ceiling. Never escapes get_with_retry.
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
                "manifest_count" => @manifest.size,
                "records" => @manifest.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk record files no listing names. The attic (a dot-dir) never
    # matches the glob; the state file never matches the record shape.
    def record_relpaths
      return [] unless Dir.exist?(@dir)

      Dir.glob("*/*.xml", base: @dir).select { |rel| self.class.record?(rel) }
    end

    def doomed_relpaths
      keep = @manifest.to_set { |(collection, filename)| File.join(collection, filename) }
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
