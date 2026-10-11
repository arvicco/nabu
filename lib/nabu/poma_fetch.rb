# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"
require "nokogiri"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Polite page crawl for the Royal Danish Library's Guaman Poma edition
  # (P117-5; architecture §8) — El primer nueva corónica y buen gobierno,
  # GKS 2232 4º, one static XHTML page per manuscript page at a stable
  # permalink:
  #
  #   <base>/titlepage/es/text/     the title page (the manuscript's p. 0)
  #   <base>/<n>/es/text/           pages 1..N
  #
  # Mirrored from OtdoFetch (the page-manifest mold; the retry/attic/ledger
  # machinery line-for-line), with the manifest derived instead of read:
  # the edition publishes no page list, but every page carries the
  # navigation bar's last-page arrow (">|" → <base>/<N>/es/text/) and the
  # table of contents. prepare! GETs the title page, reads N from its
  # last-page arrow, and cross-checks it against the highest page the
  # table of contents links (must be ≤ N, and N ≥ 1) — a reshaped or
  # truncated navigation aborts loudly BEFORE any write. Manifest =
  # titlepage + 1..N (N = 1189 at the 2026-10-11 census: 1,190 pages).
  #
  # == Resume + re-sync posture
  #
  # The edition is a static scholarly publication (2001, revised 2004;
  # site changes 2023/2025 are presentation). A page already on disk is
  # NOT re-fetched, and every fetched page is written AT ONCE (tmp+rename)
  # — an interrupted ~25-minute first crawl resumes where it stopped. The
  # title page is GET-ted on every sync (it carries the manifest) and
  # written only when absent. Refreshing a page means deleting its file.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the title-page GET only; the live tree untouched;
  #              doomed = on-disk page files outside titlepage + 1..N.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, crawl the missing pages, pin the
  #              ledger.
  #
  # A 404 is CENSUSED and skipped (a lone hole is upstream damage, never a
  # reason to abort a polite crawl); a SYSTEMIC miss rate still aborts.
  # 5xx and transport failures retry 3× with exponential backoff.
  class PomaFetch
    # HTTP failure, a reshaped navigation, or a systemic miss. Adapters
    # wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".poma-fetch.json"
    TITLEPAGE = "titlepage"

    # A crawled page file (= page id + .html).
    RECORD_FILENAME = /\A(titlepage|\d+)\.html\z/

    # The navigation bar's last-page arrow and the TOC's page links.
    PAGE_HREF = %r{/permalink/2006/poma/(\d+)/es/text/}

    # Seconds between HTTP requests (sequential, polite — a national
    # library's host; 1,190 pages ≈ 25 minutes at 1 req/s).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count, :missing)

    def self.page_url(base_url, id)
      "#{base_url}/#{id}/es/text/"
    end

    def self.record_filename(id)
      "#{id}.html"
    end

    def self.record?(filename)
      RECORD_FILENAME.match?(filename)
    end

    def self.sync!(base_url:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, records: fetch.records, manifest_count: fetch.manifest_count,
                 missing: fetch.missing)
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
      @titlepage_html = nil
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count, :missing

    def records = @ids.size - @missing.size

    # Phase 1 — the title-page GET only; live tree untouched.
    def prepare!
      @progress&.call("Guaman Poma title page (the manifest)…\n")
      @titlepage_html = get_with_retry(self.class.page_url(@base_url, TITLEPAGE), id: TITLEPAGE)
      last = defend_navigation!(@titlepage_html)
      @ids = [TITLEPAGE] + (1..last).map(&:to_s)
      @manifest_count = @ids.size
      @doomed = doomed_relpaths
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, crawl the missing pages, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(@dir)
      crawl!
      @sha = aggregate_sha
      write_state!
    end

    private

    # N from the last-page arrow; the TOC's highest page link must not
    # exceed it (class note).
    def defend_navigation!(html)
      doc = Nokogiri::HTML(html)
      arrow = doc.css("a").find { |a| a.text.strip == ">|" }
      last = arrow && arrow["href"].to_s[PAGE_HREF, 1]&.to_i
      toc_top = doc.css("#workContent a").filter_map { |a| a["href"].to_s[PAGE_HREF, 1]&.to_i }.max
      return last if last&.positive? && toc_top && toc_top <= last

      raise Error, "Guaman Poma navigation is reshaped: last-page arrow #{last.inspect}, highest " \
                   "table-of-contents page #{toc_top.inspect} — the derived manifest needs both " \
                   "(arrow ≥ TOC); check #{self.class.page_url(@base_url, TITLEPAGE)} by hand"
    end

    def crawl!
      @ids.each_with_index do |id, index|
        name = self.class.record_filename(id)
        if File.file?(File.join(@dir, name))
          @cached += 1
          next
        end

        if id == TITLEPAGE
          write!(name, @titlepage_html)
          @fetched += 1
          next
        end

        @progress&.call("Guaman Poma page #{index}/#{@ids.size - 1}…\n") if (index % 50).zero?
        body = get_with_retry(self.class.page_url(@base_url, id), id: id, missing_ok: true)
        if body.nil?
          @missing << id
          @progress&.call("Guaman Poma page #{id}: 404 (censused, crawl continues)\n")
          next
        end
        write!(name, body)
        @fetched += 1
      end
      cap = [(@ids.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@ids.size} pages 404 — a systemic miss, not holes: the " \
                   "permalink scheme has moved upstream (first missing: #{@missing.first(3).join(', ')})"
    end

    def get_with_retry(url, id:, missing_ok: false)
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
        when 200 then response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        when 404
          return nil if missing_ok

          raise Error, "HTTP 404 for #{url} (#{id})"
        else
          raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Never escape get_with_retry.
    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    def write!(name, body)
      target = File.join(@dir, name)
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    def aggregate_sha
      names = Dir.children(@dir).select { |name| self.class.record?(name) }
      lines = names.sort.map do |name|
        "#{name}\0#{Digest::SHA256.file(File.join(@dir, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha,
                "manifest_count" => @manifest_count, "records" => records,
                "fetched" => @fetched, "cached" => @cached, "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      keep = @ids.to_set { |id| self.class.record_filename(id) }
      Dir.children(@dir).sort.select { |name| self.class.record?(name) && !keep.include?(name) }
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
      pin = previous_sha || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin }
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
