# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"
require_relative "adapters/statutes_realm_toc"

module Nabu
  # Paced TOC-walk crawl for the Statutes of the Realm on British History
  # Online (P160-7) — the AioFetch sibling for an upstream with no API and
  # no dump, only HTML:
  #
  #   GET <base>/statutes-realm/vol<V>?page=<p>     V = 5, 6, 7
  #     → the volume TOC, 100 rows a page (vol5 4 pages, vol6 2, vol7 3 at
  #       the 2026-11-05 census). The walk starts at page 0 and follows the
  #       pager's rel=next until a page carries none (never a hardcoded
  #       page count). Every TOC page PERSISTS as toc/vol<V>-page-<p>.html
  #       (discovery-census honesty, the AIO listing-sidecar pattern).
  #   GET <base>/statutes-realm/vol<V>/<slug>        per ACCEPTED row
  #     → the act page, landed as vol<V>/<slug>.html. Rows of the rejected
  #       grains (index letters, preface, chronological table, engravings —
  #       StatutesRealmToc) are never fetched.
  #
  # Vols 1–4 (to 1624) are NOT on BHO: /statutes-realm/vol1 … vol4 answer
  # 404 (probed 2026-11-05), as does vol8; VOLUMES is the served set.
  # robots.txt (read 2026-11-05) disallows only the Drupal shell paths
  # (/admin/, /search/, /user/…, /core/, /profiles/) and sets no
  # crawl-delay; the walk keeps ~1 request a second regardless.
  #
  # DELIBERATELY MIRRORED from AioFetch, not extracted (the house stance on
  # the HTML-crawl siblings).
  #
  # == Resume + re-sync posture
  #
  # A page file already on disk is NOT re-fetched (resume at the file
  # grain). BHO stamps no revision on the pages, so refreshing a revised
  # page means deleting it and re-syncing — the AIO/SEAL posture, declared.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the TOC GETs only — the live tree untouched; doomed = page
  #              files on disk that no accepted row names.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, land the TOC sidecars + missing pages
  #              (each write tmp+rename), pin the ledger.
  #
  # A 404 on a listed page is CENSUSED and skipped; a systemic miss rate
  # aborts. 5xx and transport failures retry 3× with backoff. A TOC page
  # with no rows, or a missing TOC, aborts before any write. The fetch pin
  # is an aggregate sha256 over the sorted (relpath, body-sha) set of page
  # files — the TOC sidecars stay out.
  class StatutesRealmFetch
    # HTTP failure, a reshaped TOC, or a persistent 5xx/transport failure.
    # Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    BASE_URL = "https://www.british-history.ac.uk"

    STATE_FILE = ".statutes-realm-fetch.json"

    TOC_DIR = "toc"

    # The volumes BHO serves (Raithby vols 5–7, 1625–1701).
    VOLUMES = [5, 6, 7].freeze

    # A page file as the crawl writes it (vol<V>/<slug>.html).
    PAGE_RELPATH = %r{\Avol(\d+)/([^/]+)\.html\z}

    # A persisted TOC sidecar (toc/vol<V>-page-<p>.html).
    TOC_FILENAME = /\Avol(\d+)-page-(\d+)\.html\z/

    # Seconds between HTTP requests (sequential, polite — ~670 GETs ≈ 11 min
    # of pauses, plus response time).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    # A rel=next loop guard, far above the 4 pages of the largest volume.
    # const: loop guard, not a corpus claim
    MAX_PAGES = 100

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; Statutes of the Realm pages marked " \
                 "Public Domain; +https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :rows, :accepted, :missing, :toc_pages)

    def self.toc_url(base_url, volume, page)
      "#{base_url}/statutes-realm/vol#{volume}?page=#{page}"
    end

    def self.page_url(base_url, volume, slug)
      "#{base_url}/statutes-realm/vol#{volume}/#{slug}"
    end

    def self.toc_relpath(volume, page)
      File.join(TOC_DIR, "vol#{volume}-page-#{page}.html")
    end

    def self.page_relpath(volume, slug)
      File.join("vol#{volume}", "#{slug}.html")
    end

    def self.sync!(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, volumes: VOLUMES, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, http: http,
                  delay: delay, volumes: volumes, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched, cached: fetch.cached,
                 rows: fetch.rows, accepted: fetch.accepted, missing: fetch.missing, toc_pages: fetch.toc_pages)
    end

    def initialize(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, volumes: VOLUMES, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @volumes = volumes
      @progress = progress
      @rows = []
      @toc_bodies = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :missing

    def rows = @rows.size

    def accepted = accepted_rows.size

    def toc_pages = @toc_bodies.size

    # Phase 1 — the TOC GETs only; live tree untouched.
    def prepare!
      @volumes.each { |volume| walk_toc!(volume) }
      @doomed = doomed_relpaths
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the sidecars, crawl the missing
    # pages, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      @toc_bodies.each { |rel, body| write!(rel, body) }
      crawl_pages!
      @sha = aggregate_sha
      write_state!
    end

    private

    def accepted_rows = @rows.select(&:accepted?)

    # -- the TOC walk -------------------------------------------------------------

    def walk_toc!(volume)
      page = 0
      loop do
        raise Error, "vol#{volume} TOC exceeded #{MAX_PAGES} pages — a rel=next loop upstream" if page >= MAX_PAGES

        @progress&.call("Statutes of the Realm vol#{volume} TOC page=#{page}…\n")
        body = get_with_retry(self.class.toc_url(@base_url, volume, page), id: "vol#{volume} TOC page=#{page}")
        rows = Adapters::StatutesRealmToc.rows(body, volume: volume)
        raise Error, "vol#{volume} TOC page=#{page} lists no rows — abort before any write" if rows.empty?

        @rows.concat(rows)
        @toc_bodies[self.class.toc_relpath(volume, page)] = body
        following = Adapters::StatutesRealmToc.next_page(body)
        break if following.nil?
        raise Error, "vol#{volume} TOC page=#{page} points next to page=#{following}" if following <= page

        page = following
      end
    end

    # -- the page crawl ---------------------------------------------------------

    def crawl_pages!
      rows = accepted_rows
      rows.each_with_index do |row, index|
        @progress&.call("Statutes of the Realm page #{index + 1}/#{rows.size} (vol#{row.volume}/#{row.slug})…\n") \
          if (index % 50).zero?
        crawl_one!(row)
      end
      cap = [(rows.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} listed pages 404 — a systemic miss, not holes: the URL scheme moved " \
                   "upstream (first missing: #{@missing.first(3).join(', ')})"
    end

    def crawl_one!(row)
      rel = self.class.page_relpath(row.volume, row.slug)
      if File.file?(File.join(@dir, rel))
        @cached += 1
        return
      end

      id = "vol#{row.volume}/#{row.slug}"
      body = get_with_retry(self.class.page_url(@base_url, row.volume, row.slug), id: id, missing_ok: true)
      if body.nil?
        @missing << id
        @progress&.call("Statutes of the Realm #{id}: 404 (listed — censused, crawl continues)\n")
        return
      end
      write!(rel, body)
      @fetched += 1
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

    # Internal retry marker; never escapes get_with_retry.
    class RetriableFailure < StandardError; end

    # RedirectFollow's error channel for one attempt; never escapes.
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

    def page_relpaths
      Dir.glob(File.join(@dir, "vol*", "*.html")).map { |path| path.delete_prefix("#{@dir}/") }.grep(PAGE_RELPATH).sort
    end

    def aggregate_sha
      lines = page_relpaths.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => self.class.toc_url(@base_url, @volumes.first, 0), "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha, "volumes" => @volumes, "toc_pages" => toc_pages,
                "rows" => rows, "accepted" => accepted, "fetched" => @fetched, "cached" => @cached,
                "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    def doomed_relpaths
      keep = accepted_rows.to_set { |row| self.class.page_relpath(row.volume, row.slug) }
      page_relpaths.reject { |rel| keep.include?(rel) }
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
