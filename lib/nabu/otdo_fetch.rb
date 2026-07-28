# frozen_string_literal: true

require "cgi"
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
  # Polite page-manifest crawl for Old Tibetan Documents Online (P48-5;
  # architecture §8) — the ElephantineFetch sibling for an upstream that is
  # neither a git repo nor a zip nor an API but ONE stateless catalog page
  # plus per-document HTML pages:
  #
  #   GET <base>/archives            the complete catalog in one page — a
  #       numbered table (rows 1..N), one <input name="datatxt[]"
  #       value="<slug>"> checkbox per document (414 rows at the
  #       2026-07-28 census). PERSISTED in canonical as
  #       archives_index.html — it doubles as a metadata sidecar (the
  #       per-row content/title column).
  #   GET <base>/archives?p=<slug>   one critical edition per document.
  #       Slugs carry apostrophes (insc_'Bis2) — percent-encoded on the
  #       wire, verbatim in the filename <slug>.html.
  #
  # DELIBERATELY MIRRORED from ElephantineFetch, not extracted: that class
  # is live-verified owner-crawl code and the two crawls differ in every
  # seam a shared base would have to parameterize (manifest acquisition
  # GET-vs-session-POST, count defense numbered-rows-vs-Results-header,
  # id shape slug-vs-ID6, authority files none-vs-four). The retry/attic/
  # ledger machinery is mirrored line-for-line; a third HTML-crawl sibling
  # is the signal to extract.
  #
  # == The count-assertion defense (the site's own numbering)
  #
  # The catalog table numbers its rows 1..N in the first cell. Extracted
  # unique slugs MUST equal both the row count and the highest row number —
  # a mismatch (or an empty table: a maintenance page, a shape change)
  # aborts loudly BEFORE any write.
  #
  # == Resume + re-sync posture
  #
  # Pages are served by a live application (no Last-Modified; a per-request
  # CSRF token rides every page body), but the EDITIONS are stable critical
  # texts. A page already on disk is NOT re-fetched (resume at the file
  # grain, the TitusFetch mold): an interrupted ~7-minute first crawl
  # resumes where it stopped, and a re-sync costs one catalog GET.
  # Refreshing a page after an upstream revision means deleting its file —
  # or the canonical dir — and re-syncing.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the catalog GET only — cheap, the live tree untouched;
  #              doomed = on-disk page files whose slug the catalog no
  #              longer lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, land the catalog + missing pages
  #              (each write tmp+rename), pin the ledger.
  #
  # A 404 on a catalog-promised page is CENSUSED and skipped (the P47-i1
  # lesson: a lone hole is upstream damage to report, never a reason to
  # abort a polite crawl); a SYSTEMIC miss rate (> the cap) still aborts —
  # that shape means the URL scheme moved, not a hole. 5xx AND transport-
  # level failures retry 3× with exponential backoff (P47-i2). The fetch
  # pin is an aggregate sha256 over the sorted (filename, body-sha) set of
  # page files — the catalog sidecar stays out (its bytes carry the
  # per-request CSRF token, not corpus content).
  class OtdoFetch
    # HTTP failure, a truncated/malformed catalog, or a systemic miss.
    # Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".otdo-fetch.json"

    # The persisted catalog GET (canonical metadata sidecar — class note).
    ARCHIVES_FILE = "archives_index.html"

    # A document slug as the catalog prints it: letters/digits/underscore/
    # hyphen/apostrophe (insc_'Bis2, ITJ_0737-1 — census 2026-07-28).
    SLUG_SHAPE = /\A[A-Za-z0-9][A-Za-z0-9_'-]*\z/

    # A page file as the crawl writes it (= slug + .html). The catalog
    # sidecar matches the shape too, so membership goes through .record?.
    RECORD_FILENAME = /\A([A-Za-z0-9][A-Za-z0-9_'-]*)\.html\z/

    # Seconds between HTTP requests (sequential, polite — a university
    # institute's host; 414 pages ≈ 7 minutes at 1 req/s).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses; 404 is deliberately NOT here — a missing page is
    # censused (P47-i1), never retried.
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count, :missing)

    # Miss-rate ceiling before the crawl calls the catalog broken: a
    # fraction of the manifest, floored so tiny manifests (tests) don't
    # abort on one hole.
    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    # The per-document page URL — the apostrophe slugs (insc_'Bis2) must be
    # percent-encoded or the GET 404s.
    def self.record_url(base_url, slug)
      "#{base_url}/archives?p=#{CGI.escape(slug)}"
    end

    def self.record_filename(slug)
      "#{slug}.html"
    end

    # Is +filename+ a crawled document page? The catalog sidecar matches
    # RECORD_FILENAME's shape, so it is excluded by name here (and a catalog
    # slug colliding with the sidecar stem aborts in prepare!).
    def self.record?(filename)
      filename != ARCHIVES_FILE && RECORD_FILENAME.match?(filename)
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
      @slugs = []
      @catalog_html = nil
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count, :missing

    def records = @slugs.size

    # Phase 1 — the catalog GET only; live tree untouched. Extracts the
    # slug set, runs the count-assertion defense, computes the doomed set.
    def prepare!
      @catalog_html = fetch_catalog
      @slugs = extract_slugs(@catalog_html)
      @manifest_count = @slugs.size
      defend_count!
      @doomed = doomed_relpaths
    end

    # Absolute live-tree page files the catalog no longer lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the catalog, crawl the missing
    # pages, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(@dir)
      write!(ARCHIVES_FILE, @catalog_html)
      crawl_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the catalog ------------------------------------------------------------

    def fetch_catalog
      @progress&.call("OTDO archives catalog (GET /archives)…\n")
      pause
      response, = RedirectFollow.get("#{@base_url}/archives", http: @http, error: Error,
                                                              headers: { "User-Agent" => USER_AGENT },
                                                              accept: [200])
      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    rescue Faraday::Error => e
      raise Error, "archives catalog GET failed: #{e.message}"
    end

    # One slug per checkbox row, HTML entities unescaped (the catalog
    # escapes the apostrophe slugs as &#039;).
    def extract_slugs(html)
      slugs = html.scan(/name="datatxt\[\]" value="([^"]+)"/).flatten
                  .map { |slug| CGI.unescapeHTML(slug) }
      slugs.each do |slug|
        raise Error, "catalog slug #{slug.inspect} violates the slug shape — upstream id scheme changed" unless
          SLUG_SHAPE.match?(slug)
        raise Error, "catalog slug #{slug.inspect} collides with the #{ARCHIVES_FILE} sidecar" if
          self.class.record_filename(slug) == ARCHIVES_FILE
      end
      slugs
    end

    # The catalog's own row numbering (1..N in each row's first cell) is
    # the count cross-check: unique slugs MUST equal both the row count and
    # the highest row number, or the page was truncated/reshaped.
    def defend_count!
      rows = @catalog_html.scan('<tr class="content-row">').size
      top = @catalog_html.scan(%r{<td class="b">\s*(\d+)\s*</td>}).flatten.map { |n| Integer(n, 10) }.max || 0
      return if @slugs.any? && @slugs.uniq.size == @slugs.size && @slugs.size == rows && rows == top

      raise Error,
            "archives catalog is TRUNCATED or reshaped: #{@slugs.size} document slugs " \
            "(#{@slugs.uniq.size} unique) against #{rows} table rows numbered up to #{top} — " \
            "the numbered catalog is the census cross-check; retry and check " \
            "#{@base_url}/archives by hand"
    end

    # -- the page crawl ---------------------------------------------------------

    def crawl_records!
      @slugs.each_with_index do |slug, index|
        name = self.class.record_filename(slug)
        if File.file?(File.join(@dir, name))
          @cached += 1
          next
        end

        @progress&.call("OTDO page #{index + 1}/#{@slugs.size} (#{slug})…\n") if (index % 25).zero?
        body = get_with_retry(self.class.record_url(@base_url, slug), id: slug, missing_ok: true)
        if body.nil?
          # P47-i1: a promised-but-missing page — census, skip, keep
          # crawling. The tail reports it; a systemic rate aborts below.
          @missing << slug
          @progress&.call("OTDO page #{slug}: 404 (promised by the catalog — censused, crawl continues)\n")
          next
        end
        write!(name, body)
        @fetched += 1
      end
      cap = [(@slugs.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@slugs.size} catalog slugs 404 — a systemic miss, not " \
                   "holes: the page URL scheme or the catalog itself has moved upstream " \
                   "(first missing: #{@missing.first(3).join(', ')})"
    end

    # One GET: 200 wins; a 404 returns nil (the caller censuses it, P47-i1);
    # 5xx AND transport-level failures (P47-i2) retry with the same
    # exponential backoff.
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

          raise Error, "HTTP 404 for #{url} — the archives catalog promises #{id} but the page is missing"
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

    def write!(name, body)
      target = File.join(@dir, name)
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    # Content pin: sorted (filename, body-sha256) over page files on disk.
    # The catalog HTML stays out — its bytes carry the per-request CSRF
    # token, not corpus content.
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
                "manifest_count" => @manifest_count,
                "records" => @slugs.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk page files whose slug the catalog no longer lists. The
    # catalog sidecar is infrastructure, never doomed.
    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      keep = @slugs.to_set { |slug| self.class.record_filename(slug) }
      Dir.children(@dir).select { |name| self.class.record?(name) && !keep.include?(name) }
    end

    # First copy wins; the manifest records the pin each file vanished at,
    # in GitFetch's exact format so the adapter base class rediscovers the
    # attic generically. The doomed set is pinned under the PREVIOUS
    # ledger's sha when one exists, else a pre-ledger timestamp stamp.
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
