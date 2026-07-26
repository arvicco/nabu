# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"

module Nabu
  # Polite id-manifest crawl for the Berlin Elephantine database (P47-1;
  # architecture §8) — the TitusFetch sibling for an upstream that is neither
  # a git repo nor a zip nor an API but ONE session-stateful POST listing plus
  # a static per-id TEI tree:
  #
  #   POST <base>/objects/index.php  body showresults=15000
  #     → the complete object listing in one ~10.5 MB HTML page (10,744
  #       object.php?o=<id> links at the 2026-07-26 census, header "10744
  #       Results"), PERSISTED in canonical as objects_index.html — it doubles
  #       as a metadata sidecar (per-row modern title / text flag).
  #   GET  <base>/xml/elephantine_erc_db_<ID6>.tei.xml  per id
  #     → ID6 is the id ZERO-PADDED to 6 digits (the unpadded URL 404s).
  #   GET  the four authority files (places / modern_persons / literature /
  #        ancient_persons) once per sync, same /xml/ dir.
  #
  # == The session-truncation defense (census risk, verified live)
  #
  # The listing POST is session-stateful: a stale search filter riding a
  # cookie would silently truncate the id set. This class sends NO cookies,
  # and asserts extracted unique ids == the page's own "N Results" header —
  # a mismatch (or a missing header) aborts loudly BEFORE any write.
  #
  # == Resume + re-sync posture (frozen export)
  #
  # Every sampled TEI is Last-Modified 2022-11-24 (the ERC project ended
  # 2022) — a single frozen export, zero churn expected. A record already on
  # disk is therefore NOT re-fetched (resume at the file grain, the
  # TitusFetch mold): an interrupted ~3 h first crawl resumes where it
  # stopped, and a re-sync costs one POST + four authority GETs. Refreshing
  # a record after an (unannounced) upstream re-release means deleting its
  # file — or the canonical dir — and re-syncing; upstream serves
  # ETag/Last-Modified, so a conditional-GET refresh mode is cheap to add
  # the day churn actually appears.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the manifest POST only — cheap, the live tree untouched;
  #              doomed = on-disk record files whose id the manifest no
  #              longer lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy wins),
  #              delete them, land the listing + missing records + authority
  #              files (each write tmp+rename), pin the ledger. Unlike the
  #              in-memory stagers (Iness/Sefaria) the record crawl writes as
  #              it goes — 10,744 files / ~315 MB never buffer — which is
  #              safe exactly because a mid-crawl failure resumes at the
  #              file grain.
  #
  # A 404 on a manifest-promised id is a HARD anomaly (loud Error, sync
  # aborts); 5xx/timeouts retry 3× with exponential backoff. The fetch pin is
  # an aggregate sha256 over the sorted (filename, body-sha) set of records +
  # authority files — a reproducible content identity, the non-git ledger
  # mold.
  class ElephantineFetch
    # HTTP failure, a truncated/malformed listing, or a manifest-promised id
    # that 404s. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".elephantine-fetch.json"

    # The persisted listing POST (canonical metadata sidecar — class note).
    OBJECTS_FILE = "objects_index.html"

    # The four authority files fetched once per sync beside the records
    # (same /xml/ dir; body @ref fragments resolve against them).
    # census: the /xml/ dir's four authority files, 2026-07-26 (frozen export)
    AUTHORITY_FILES = %w[places modern_persons literature ancient_persons]
                      .map { |name| "elephantine_erc_db_#{name}.tei.xml" }.freeze

    # A record file as the crawl writes it (= as upstream serves it).
    RECORD_FILENAME = /\Aelephantine_erc_db_(\d{6})\.tei\.xml\z/

    # Seconds between HTTP requests (sequential, polite — a museum's host;
    # the census clocked ~80 ms/response, so 1 req/s dominates the crawl).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal (census crawl
    # plan: retry 3× exponential backoff).
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses; 404 is deliberately NOT here — on a
    # manifest-promised id it is a hard anomaly, never a retry.
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count)

    # The padded per-id TEI URL — ID6 zero-padding is load-bearing (the
    # unpadded URL 404s upstream).
    def self.record_url(base_url, id)
      "#{base_url}/xml/#{record_filename(id)}"
    end

    def self.record_filename(id)
      "elephantine_erc_db_#{id.to_s.rjust(6, '0')}.tei.xml"
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
      @ids = []
      @listing_html = nil
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count

    def records = @ids.size

    # Phase 1 — the manifest POST only; live tree untouched. Extracts the id
    # set, runs the truncation defense, computes the doomed set.
    def prepare!
      @listing_html = post_listing
      @ids = @listing_html.scan(/object\.php\?o=(\d+)/).flatten.uniq
                          .map { |id| id.rjust(6, "0") }.sort
      @manifest_count = results_header(@listing_html)
      defend_truncation!
      @doomed = doomed_relpaths
    end

    # Absolute live-tree record files the manifest no longer lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the listing, crawl the missing
    # records, refresh the authority files, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(@dir)
      write!(OBJECTS_FILE, @listing_html)
      crawl_records!
      fetch_authorities!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the manifest -----------------------------------------------------------

    def post_listing
      @progress&.call("Elephantine objects listing (POST showresults=15000)…\n")
      pause
      response = @http.post("#{@base_url}/objects/index.php", "showresults=15000",
                            { "User-Agent" => USER_AGENT,
                              "Content-Type" => "application/x-www-form-urlencoded" })
      raise Error, "objects listing POST returned HTTP #{response.status}" unless response.status == 200

      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    rescue Faraday::Error => e
      raise Error, "objects listing POST failed: #{e.message}"
    end

    # The page's own "N Results" header — the truncation cross-check.
    def results_header(html)
      match = html.match(/(\d+)\s+Results/)
      raise Error, "objects listing carries no \"N Results\" header — upstream page shape changed" unless match

      Integer(match[1], 10)
    end

    def defend_truncation!
      return if @ids.size == @manifest_count && @ids.any?

      raise Error,
            "objects listing is TRUNCATED: header says #{@manifest_count} Results but the page " \
            "carries #{@ids.size} unique object ids — the listing POST is session-stateful and a " \
            "stale filter silently truncates; retry (this client sends no cookies) and check " \
            "#{@base_url}/objects/index.php by hand"
    end

    # -- the record crawl -------------------------------------------------------

    def crawl_records!
      @ids.each_with_index do |id, index|
        name = self.class.record_filename(id)
        if File.file?(File.join(@dir, name))
          @cached += 1
          next
        end

        @progress&.call("Elephantine record #{index + 1}/#{@ids.size} (#{id})…\n") if (index % 100).zero?
        write!(name, get_with_retry(self.class.record_url(@base_url, id), id: id))
        @fetched += 1
      end
    end

    def fetch_authorities!
      AUTHORITY_FILES.each do |name|
        @progress&.call("Elephantine authority file #{name}…\n")
        write!(name, get_with_retry("#{@base_url}/xml/#{name}", id: name))
      end
    end

    # One GET: 200 wins; 404 on a manifest-promised id is a HARD anomaly
    # (the id-list and the file tree are one frozen export — a hole is
    # damage, never routine); 5xx/timeout retries with exponential backoff.
    def get_with_retry(url, id:)
      attempt = 0
      begin
        attempt += 1
        pause
        response, = RedirectFollow.get(url, http: @http, error: Error,
                                            headers: { "User-Agent" => USER_AGENT },
                                            accept: [200, 404, *RETRIABLE_STATUSES])
        case response.status
        when 200 then response.body.to_s
        when 404
          raise Error, "HTTP 404 for #{url} — the objects listing promises id #{id} but the TEI " \
                       "file is missing: a hard anomaly in the frozen export, investigate upstream"
        else
          raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Internal marker for a retriable HTTP failure (5xx); never escapes
    # get_with_retry.
    class RetriableFailure < StandardError; end
    private_constant :RetriableFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    # -- landing / ledger -------------------------------------------------------

    def write!(name, body)
      target = File.join(@dir, name)
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    # Content pin: sorted (filename, body-sha256) over records + authority
    # files on disk. The listing HTML stays out — its bytes carry the search
    # form's per-request state, not corpus content.
    def aggregate_sha
      names = Dir.children(@dir).select do |name|
        RECORD_FILENAME.match?(name) || AUTHORITY_FILES.include?(name)
      end
      lines = names.sort.map do |name|
        "#{name}\0#{Digest::SHA256.file(File.join(@dir, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha,
                "manifest_count" => @manifest_count,
                "records" => @ids.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk record files whose id the manifest no longer lists. Authority
    # files and the listing are infrastructure, never doomed.
    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      keep = @ids.to_set { |id| self.class.record_filename(id) }
      Dir.children(@dir).select { |name| RECORD_FILENAME.match?(name) && !keep.include?(name) }
    end

    # First copy wins; the manifest records the pin each file vanished at,
    # in GitFetch's exact format so the adapter base class rediscovers the
    # attic generically. The doomed set is pinned under the PREVIOUS ledger's
    # sha when one exists (the pin they vanished at), else this sync's
    # manifest count stamp.
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
