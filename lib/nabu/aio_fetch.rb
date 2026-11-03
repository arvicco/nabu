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
  # Polite REST-listing crawl for AIO — Attic Inscriptions Online
  # (www.atticinscriptions.com; P154) — the SealFetch sibling for an
  # upstream that publishes its own REST API (the Swagger spec at /api/,
  # "Attic Inscriptions Online REST API", read 2026-11-02):
  #
  #   GET <base>/inscription/list_all_inscriptions.json?page=<1..>
  #     → {"count": 3466, "next": <url|null>, "inscriptions": [{"aio_key":
  #       "AIO_5", "url": "www.atticinscriptions.com/inscription/IGII31/292",
  #       "api_url": "…/IGII31/292.json"}, …]} — 100 rows per page, 35 pages
  #       at the 2026-11-02 census. The crawl follows upstream's own "next"
  #       link until it is null (never a hardcoded page count) and checks
  #       the collected key set against the advertised "count". Every
  #       listing page PERSISTS at the workdir root as list-page-<n>.json
  #       (discovery-census honesty, the cantigas/seal pattern).
  #   GET https://<api_url>                      per inscription, the record
  #     → the API record: references, translation_title, translators, IPR,
  #       and the texts as Base64 EpiDoc ("translation_epidoc" always,
  #       "greek_epidoc" where AIO publishes its own Greek text).
  #   GET https://<url>                          per inscription, the page
  #     → the inscription page: the fields the API omits (Date, Monument
  #       type, Inscription type, Original location, Findspot, the
  #       translators' footnotes, Added/Updated, the CC BY-SA 3.0 badge).
  #   Both land under records/ as aio-<n>.json + aio-<n>.html, n = the
  #   numeric part of upstream's aio_key (the page's own "ID: AIO_<n>").
  #
  # Images are NEVER fetched (photographs carry their own holders' terms);
  # the Greek-view page (?text_type=greek) is never fetched either — the
  # API record already carries the same text as EpiDoc.
  #
  # DELIBERATELY MIRRORED from SealFetch, not extracted (the house stance
  # on the HTML-crawl siblings — extraction stays flagged for its own
  # packet). The manifest seam differs (a "next"-linked JSON listing) and
  # each record is a PAIR of files.
  #
  # == Resume + re-sync posture
  #
  # A record file already on disk is NOT re-fetched (resume at the file
  # grain): an interrupted first crawl resumes where it stopped, and a
  # re-sync costs the ~35 listing GETs plus whatever is missing. Pages
  # carry an "Updated:" stamp but the listing carries no revision field, so
  # refreshing a revised record means deleting its pair (or the canonical
  # dir) and re-syncing — the SEAL posture, declared.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the listing GETs only — cheap, the live tree untouched;
  #              doomed = on-disk record files no listing page names.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, land the listing sidecars + missing
  #              record files (each write tmp+rename), pin the ledger.
  #
  # A 404 on a listed record is CENSUSED and skipped (P47-i1); a SYSTEMIC
  # miss rate aborts. 5xx AND transport failures retry 3× with backoff
  # (P47-i2). The fetch pin is an aggregate sha256 over the sorted
  # (relpath, body-sha) set of record files — the listing sidecars stay
  # out. A listing page with zero rows, or a key set that disagrees with
  # upstream's own "count", aborts loudly BEFORE any write.
  class AioFetch
    # HTTP failure, a reshaped listing, or a persistent 5xx/transport
    # failure. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    BASE_URL = "https://www.atticinscriptions.com"

    STATE_FILE = ".aio-fetch.json"

    RECORDS_DIR = "records"

    # A record file as the crawl writes it (records/aio-<n>.json|html).
    RECORD_FILENAME = /\Aaio-(\d+)\.(json|html)\z/

    # A persisted listing sidecar at the workdir root.
    LISTING_FILENAME = /\Alist-page-(\d+)\.json\z/

    # upstream's own key shape ("AIO_3869").
    AIO_KEY = /\AAIO_(\d+)\z/

    # Seconds between HTTP requests (sequential, polite — a British School
    # at Athens host; ~6,970 requests ≈ 60 min of pauses at 0.5 s, plus
    # response time).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 0.5

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    # Hard ceiling on listing pages followed — a "next" loop guard, far
    # above the 35 pages of the 2026-11-02 census.
    # const: loop guard, not a corpus claim
    MAX_PAGES = 1_000

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; AIO texts under CC BY-SA 3.0; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :advertised,
                         :missing, :pages)

    # One listed inscription: the numeric key and its two upstream URLs.
    Row = Data.define(:number, :page_url, :api_url)

    def self.listing_url(base_url, page)
      "#{base_url}/inscription/list_all_inscriptions.json?page=#{page}"
    end

    def self.listing_filename(page)
      "list-page-#{page}.json"
    end

    def self.record_relpath(number, extension)
      File.join(RECORDS_DIR, "aio-#{number}.#{extension}")
    end

    def self.record?(filename)
      RECORD_FILENAME.match?(filename)
    end

    # The listing's host-relative URLs ("www.atticinscriptions.com/…")
    # read as https; its absolute "next" links are spelled http:// and the
    # host 301s every one of them to https (probed 2026-11-02), so the
    # scheme is upgraded up front — one GET per page, not two.
    def self.absolute(url)
      url = url.to_s.strip
      return url.sub(%r{\Ahttp://}, "https://") if url.match?(%r{\Ahttps?://})

      "https://#{url}"
    end

    def self.sync!(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, records: fetch.records, advertised: fetch.advertised,
                 missing: fetch.missing, pages: fetch.pages)
    end

    def initialize(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @rows = []
      @listing_bodies = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :advertised, :missing

    def records = @rows.size

    def pages = @listing_bodies.size

    # Phase 1 — the listing GETs only; live tree untouched.
    def prepare!
      url = self.class.listing_url(@base_url, 1)
      page = 1
      while url
        raise Error, "listing exceeded #{MAX_PAGES} pages — a \"next\" loop upstream" if page > MAX_PAGES

        url = fetch_listing(page, url)
        page += 1
      end
      @rows = @rows.uniq(&:number).sort_by(&:number)
      check_count!
      @doomed = doomed_relpaths
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the sidecars, crawl the missing
    # record files, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(File.join(@dir, RECORDS_DIR))
      @listing_bodies.each { |page, body| write!(self.class.listing_filename(page), body) }
      crawl_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the listing manifest ----------------------------------------------------

    # One listing page: rows harvested, the body kept for its sidecar;
    # returns the absolute "next" URL or nil.
    def fetch_listing(page, url)
      @progress&.call("AIO listing page=#{page}…\n")
      body = get_with_retry(url, id: "page=#{page}")
      data = parse_listing(body, page)
      @listing_bodies[page] = body
      @advertised = Integer(data["count"], exception: false) if page == 1
      harvest_rows!(page, data)
      following = data["next"].to_s.strip
      following.empty? ? nil : self.class.absolute(following)
    end

    def parse_listing(body, page)
      data = JSON.parse(body)
      raise Error, "listing page=#{page} is not a JSON object" unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise Error, "listing page=#{page} is not JSON (#{e.message}) — a maintenance page or a " \
                   "reshaped API; abort before any write"
    end

    def harvest_rows!(page, data)
      rows = Array(data["inscriptions"]).filter_map { |entry| row_of(entry) }
      raise Error, "listing page=#{page} lists no inscriptions — abort before any write" if rows.empty?

      @rows.concat(rows)
    end

    def row_of(entry)
      return nil unless entry.is_a?(Hash)

      match = AIO_KEY.match(entry["aio_key"].to_s.strip) or return nil
      page_url = entry["url"].to_s.strip
      api_url = entry["api_url"].to_s.strip
      return nil if page_url.empty? || api_url.empty?

      Row.new(number: Integer(match[1], 10), page_url: self.class.absolute(page_url),
              api_url: self.class.absolute(api_url))
    end

    # Upstream's own "count" is the census claim: the collected key set
    # must match it exactly (a short listing is drift, never a silent
    # partial manifest).
    def check_count!
      return if @advertised.nil? || @advertised == @rows.size

      raise Error, "listing advertises count=#{@advertised} but its pages name #{@rows.size} " \
                   "distinct aio_keys — a reshaped or truncated listing; abort before any write"
    end

    # -- the record crawl ------------------------------------------------------

    def crawl_records!
      @rows.each_with_index do |row, index|
        @progress&.call("AIO record #{index + 1}/#{@rows.size} (AIO_#{row.number})…\n") if (index % 50).zero?
        { "json" => row.api_url, "html" => row.page_url }.each do |extension, url|
          crawl_one!(row, extension, url)
        end
      end
      cap = [(@rows.size * 2 * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} listed record files 404 — a systemic miss, not holes: the URL " \
                   "scheme or the listing moved upstream (first missing: #{@missing.first(3).join(', ')})"
    end

    def crawl_one!(row, extension, url)
      rel = self.class.record_relpath(row.number, extension)
      if File.file?(File.join(@dir, rel))
        @cached += 1
        return
      end

      body = get_with_retry(url, id: "AIO_#{row.number}.#{extension}", missing_ok: true)
      if body.nil?
        @missing << "AIO_#{row.number}.#{extension}"
        @progress&.call("AIO record AIO_#{row.number}.#{extension}: 404 (listed — censused, crawl continues)\n")
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
        when 200 then response.body.to_s
        when 404
          return nil if missing_ok

          raise Error, "HTTP 404 for #{url} (#{id}) — the listing itself is missing"
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

    def record_names
      records = File.join(@dir, RECORDS_DIR)
      Dir.exist?(records) ? Dir.children(records).sort.select { |name| self.class.record?(name) } : []
    end

    def aggregate_sha
      lines = record_names.sort.map do |name|
        rel = File.join(RECORDS_DIR, name)
        "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => self.class.listing_url(@base_url, 1), "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha, "advertised" => @advertised,
                "pages" => pages, "records" => @rows.size, "fetched" => @fetched,
                "cached" => @cached, "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    def doomed_relpaths
      keep = @rows.each_with_object(Set.new) do |row, set|
        %w[json html].each { |extension| set << self.class.record_relpath(row.number, extension) }
      end
      record_names.sort.map { |name| File.join(RECORDS_DIR, name) }.reject { |rel| keep.include?(rel) }
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
