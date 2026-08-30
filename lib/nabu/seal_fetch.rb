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
  # Polite search-index crawl for SEAL — Sources of Early Akkadian
  # Literature (seal.huji.ac.il; P89-3, architecture §8) — the
  # CantigasFetch sibling for a Drupal upstream whose manifest is the
  # paginated advanced-search listing:
  #
  #   GET <base>/advanced-search?page=<0..last>
  #     → 20 rows per page ("Displaying 1 - 20 of 1065", scout 2026-08-30),
  #       each row's title cell linking the text's node page. The LAST page
  #       number comes from page 0's own pager (the pager__item--last
  #       rel="last" link) — never a hardcoded constant, so upstream growth
  #       is followed automatically. All index pages PERSIST at the workdir
  #       root as advanced-search-page-<n>.html sidecars (discovery-census
  #       honesty, the cantigas pattern).
  #   GET <base>/node/<id>                                    per text
  #     → "the URL of every text is permanent" (the project's own promise);
  #       pages land under texts/node-<id>.html. Node ids are NOT SEAL
  #       numbers — identity is the parser's job, reading the page's own
  #       "SEAL no." field; the crawl deals in node ids only.
  #
  # DELIBERATELY MIRRORED from CantigasFetch, not extracted — the fourth
  # HTML-crawl sibling (Otdo/Elephantine/Cantigas); the retry/attic/ledger
  # machinery is line-for-line, the manifest seam differs again (a pager-
  # bounded page loop vs 23 letter GETs). Extraction stays flagged for its
  # own packet, never smuggled into a new-source change.
  #
  # == The grant (thread №21, N. Wasserman email 2026-08-30)
  #
  # Local personal research only — no redistribution. TEXT ONLY: the crawl
  # touches search pages and node pages, NEVER image/copy-photo assets
  # (third-party visual material is excluded from the grant).
  #
  # == Resume + re-sync posture
  #
  # Node pages are stable critical editions; a page already on disk is NOT
  # re-fetched (resume at the file grain): an interrupted ~20-minute first
  # crawl resumes where it stopped, and a re-sync costs the ~54 index GETs.
  # Refreshing a page after an upstream revision means deleting its file —
  # or the canonical dir — and re-syncing.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the index GETs only — cheap, the live tree untouched;
  #              doomed = on-disk node pages no search page lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, land the index sidecars + missing
  #              pages (each write tmp+rename), pin the ledger.
  #
  # A 404 on a listed node is CENSUSED and skipped (P47-i1); a SYSTEMIC
  # miss rate (> the cap) aborts. 5xx AND transport-level failures retry
  # 3× with exponential backoff (P47-i2). The fetch pin is an aggregate
  # sha256 over the sorted (relpath, body-sha) set of node pages — the
  # index sidecars stay out (live-rendered Drupal bytes, not corpus
  # content). A search page listing ZERO texts is a reshaped/maintenance
  # page — abort loudly BEFORE any write (there is no legitimate empty
  # SEAL listing).
  class SealFetch
    # HTTP failure, a reshaped listing, or a persistent 5xx/transport
    # failure. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".seal-fetch.json"

    # Node pages land under this workdir subdir; the index sidecars stay
    # at the root, so record discovery never confuses the two.
    RECORDS_DIR = "texts"

    # A node page as the crawl writes it (texts/node-<id>.html) — basename.
    RECORD_FILENAME = /\Anode-(\d+)\.html\z/

    # A persisted search-index sidecar at the workdir root.
    INDEX_FILENAME = /\Aadvanced-search-page-(\d+)\.html\z/

    # Seconds between HTTP requests (sequential, polite — a university
    # host; ~1,120 requests ≈ 20 minutes at 1 req/s).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses. 404 is NOT here — a missing listed node is
    # censused (P47-i1), never retried.
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; fetching under the " \
                 "SEAL personal-research grant, N. Wasserman 2026-08-30; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count,
                         :missing, :pages)

    # Miss-rate ceiling before the crawl calls the listing broken: a
    # fraction of the manifest, floored so tiny manifests (tests) don't
    # abort on one hole.
    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    # The row scan anchors on the listing's title cell (the header <th>
    # and the per-row <td> share the view-title-table-column marker; each
    # non-greedy match consumes exactly one node link) — verified against
    # the captured page 0 (20 rows → 20 ids, no menu-link ghosts).
    ROW_PATTERN = %r{view-title-table-column.*?href="/node/(\d+)"}mn

    # Page 0's own "last page" pager link — the crawl's page-count source.
    LAST_PAGE_PATTERN = /pager__item--last.*?\?page=(\d+)/mn

    def self.search_url(base_url, page)
      "#{base_url}/advanced-search?page=#{page}"
    end

    # The permanent per-text URL (the project's own permanence promise —
    # also the scholarly-reference key the grant names).
    def self.record_url(base_url, id)
      "#{base_url}/node/#{id}"
    end

    def self.record_relpath(id)
      File.join(RECORDS_DIR, "node-#{id}.html")
    end

    def self.index_filename(page)
      "advanced-search-page-#{page}.html"
    end

    # Is +filename+ (a basename under texts/) a crawled node page? Index
    # sidecars and the state file never match the record shape.
    def self.record?(filename)
      RECORD_FILENAME.match?(filename)
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
                 cached: fetch.cached, records: fetch.records, manifest_count: fetch.manifest_count,
                 missing: fetch.missing, pages: fetch.pages)
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
      @index_bodies = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count, :missing

    def records = @ids.size

    def pages = @index_bodies.size

    # Phase 1 — the search-page GETs only; live tree untouched. Page 0's
    # pager sets the page count; every page's title cells contribute node
    # ids (deduped); the doomed set is computed against the result.
    def prepare!
      first = fetch_index(0)
      (1..last_page(first)).each { |page| fetch_index(page) }
      @ids = @ids.uniq.sort_by { |id| Integer(id, 10) }
      @manifest_count = @ids.size
      @doomed = doomed_relpaths
    end

    # Absolute live-tree node pages no search page lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the index sidecars, crawl the
    # missing pages, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(File.join(@dir, RECORDS_DIR))
      @index_bodies.each { |page, body| write!(self.class.index_filename(page), body) }
      crawl_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the search-page manifest ----------------------------------------------

    def fetch_index(page)
      @progress&.call("SEAL search page=#{page}…\n")
      body = get_with_retry(self.class.search_url(@base_url, page), id: "page=#{page}")
      @index_bodies[page] = body
      harvest_ids!(page, body)
      body
    end

    # The id scan runs on the RAW bytes (the pattern is pure ASCII) — no
    # decode boundary here. A search page listing zero texts is drift, not
    # data: SEAL always lists its corpus, so abort before any write.
    def harvest_ids!(page, body)
      ids = body.b.scan(ROW_PATTERN).flatten.map { |id| id.force_encoding(Encoding::UTF_8) }
      if ids.empty?
        raise Error,
              "search page page=#{page} lists no texts — a maintenance page or a reshaped " \
              "listing; abort before any write (check #{self.class.search_url(@base_url, page)})"
      end

      @ids.concat(ids)
    end

    def last_page(first_body)
      match = LAST_PAGE_PATTERN.match(first_body.b)
      match ? Integer(match[1], 10) : 0
    end

    # -- the page crawl ---------------------------------------------------------

    def crawl_records!
      @ids.each_with_index do |id, index|
        rel = self.class.record_relpath(id)
        if File.file?(File.join(@dir, rel))
          @cached += 1
          next
        end

        @progress&.call("SEAL text #{index + 1}/#{@ids.size} (node=#{id})…\n") if (index % 25).zero?
        body = get_with_retry(self.class.record_url(@base_url, id), id: id, missing_ok: true)
        if body.nil?
          # P47-i1 posture: a listed-but-404 node page — census, skip, keep
          # crawling; the systemic cap below still guards the scheme.
          @missing << id
          @progress&.call("SEAL text node=#{id}: 404 (listed by the search page — censused, " \
                          "crawl continues)\n")
          next
        end
        write!(rel, body)
        @fetched += 1
      end
      cap = [(@ids.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@ids.size} listed node pages 404 — a systemic miss, " \
                   "not holes: the node URL scheme or the listing itself moved upstream " \
                   "(first missing: #{@missing.first(3).join(', ')})"
    end

    # One GET: 200 wins; a 404 returns nil when the caller censuses it
    # (listed node pages, P47-i1) and raises when it cannot (a search page
    # — absence is real breakage); 5xx AND transport-level failures
    # (P47-i2) retry with exponential backoff, then fail loudly.
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
        when 200 then response.body.to_s
        when 404
          return nil if missing_ok

          raise Error, "HTTP 404 for #{url} — the listing promises #{id} but the page is missing"
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

    # RedirectFollow's error channel for one attempt — transport failures
    # and redirect pathologies land here and feed the retry loop (P47-i2);
    # never escapes get_with_retry.
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

    # Content pin: sorted (relpath, body-sha256) over node pages on disk.
    # The index sidecars stay out — live-rendered bytes, not corpus content.
    def aggregate_sha
      texts = File.join(@dir, RECORDS_DIR)
      names = Dir.exist?(texts) ? Dir.children(texts).select { |name| self.class.record?(name) } : []
      lines = names.sort.map do |name|
        "#{File.join(RECORDS_DIR, name)}\0#{Digest::SHA256.file(File.join(texts, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha,
                "manifest_count" => @manifest_count, "pages" => pages,
                "records" => @ids.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk node pages (texts/…) no search page lists. Index sidecars
    # are infrastructure, never doomed.
    def doomed_relpaths
      texts = File.join(@dir, RECORDS_DIR)
      return [] unless Dir.exist?(texts)

      keep = @ids.to_set { |id| self.class.record_relpath(id) }
      Dir.children(texts).sort
         .select { |name| self.class.record?(name) }
         .map { |name| File.join(RECORDS_DIR, name) }
         .reject { |rel| keep.include?(rel) }
    end

    # First copy wins; the manifest records the pin each file vanished at,
    # in GitFetch's exact format so the adapter base class rediscovers the
    # attic generically (texts/ keeps its shape under the attic).
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
