# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"
require_relative "adapters/cantus_source_index"

module Nabu
  # Polite source-list crawl for the Cantus Database (cantusdatabase.org;
  # architecture §8) — the AioFetch sibling for an upstream that publishes
  # a machine source list plus one CSV export per manuscript source:
  #
  #   GET <base>/json-sources/
  #     → {"<source id>": {"csv": "http://cantusdatabase.org/source/<id>/csv/"}, …}
  #       — 305 sources at the 2026-11-04 census, exactly the "Cantus DB:
  #       Sources with Inventories" segment. Persisted as json-sources.json.
  #   GET <base>/sources/?segment=4063&page=<1..last>
  #     → the Browse Sources table for that segment, 100 rows a page (4
  #       pages at the census; "Displaying 1-100 of 305 sources."): the
  #       siglum, holding institution, curated century labels, provenance
  #       and upstream's own advertised chant count per source — the
  #       manuscript metadata the CSV export does not carry. Persisted as
  #       sources-page-<n>.html (the adapter's metadata sidecars).
  #   GET <base>/source/<id>/csv/   per listed source
  #     → the source's inventory, one row per chant record (CRLF, UTF-8, no
  #       BOM). Lands as sources/<id>.csv.
  #
  # The listing's total must equal the rows its pages carry, and its id set
  # must equal the manifest's — either disagreement aborts BEFORE any
  # write (a reshaped or half-published listing is drift, never a partial
  # manifest).
  #
  # DELIBERATELY MIRRORED from AioFetch, not extracted (the house stance on
  # the crawl siblings — extraction stays flagged for its own packet).
  #
  # == Resume + re-sync posture (the row-count staleness signal)
  #
  # The Cantus Database is a living, continuously edited inventory, and the
  # export carries no revision stamp — but the listing's Chants column
  # equals the export's row count on every source probed (15/15 at the
  # census). So an export already on disk whose row count matches the
  # listing is NOT re-fetched (resume at the file grain; a re-sync costs
  # the manifest + listing GETs), and one whose count drifted IS: its old
  # body is atticked first as .attic/sources/<id>.<sha8>.csv, so chant
  # records upstream dropped stay reachable as retained documents (the
  # attic overlay — live wins for every record still listed). An edit that
  # keeps the count lands only when the file is deleted — declared.
  # A freshly fetched export whose row count still disagrees with the
  # listing (an edit between the two GETs) is noted in +drift+, not fatal.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the manifest + listing GETs; the live tree untouched;
  #              doomed = on-disk exports of sources no longer listed.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins) and the superseded, delete the doomed, land the
  #              sidecars + missing/stale exports (tmp+rename), pin the
  #              ledger.
  #
  # A 404 on a listed source is CENSUSED and skipped; a SYSTEMIC miss rate
  # aborts. 5xx AND transport failures retry 3× with backoff. A 200 whose
  # first line is not the export header aborts (a maintenance page never
  # lands as a CSV). The fetch pin is an aggregate sha256 over the sorted
  # (relpath, body-sha) set of exports — the sidecars stay out.
  class CantusFetch
    # HTTP failure, a reshaped listing, or a persistent 5xx/transport
    # failure. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    BASE_URL = "https://cantusdatabase.org"

    # The "Cantus DB: Sources with Inventories" segment — the set
    # /json-sources/ lists (the Sequence Database segment 4064 and the
    # inventory-less sources are not in it).
    # const: upstream's segment id, not a corpus claim
    SEGMENT = 4063

    STATE_FILE = ".cantus-fetch.json"

    MANIFEST_FILENAME = "json-sources.json"

    SOURCES_DIR = "sources"

    # A live export (<id>.csv) or a superseded attic copy (<id>.<sha8>.csv).
    CSV_FILENAME = /\A(\d+)(?:\.[0-9a-f]{8})?\.csv\z/

    PAGE_FILENAME = /\Asources-page-(\d+)\.html\z/

    # The export's own header begins so; anything else is not the export.
    HEADER_MARK = "shelfmark,"

    # Seconds between requests (sequential, polite — ~310 requests ≈ 5 min
    # of pauses, plus response time).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.02
    MISSING_CAP_FLOOR = 5

    # const: loop guard, far above the 4 pages of the census
    MAX_PAGES = 200

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; Cantus Database data under " \
                 "CC BY-NC-SA 4.0; +https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :sources, :pages, :advertised_sources,
                         :advertised_chants, :missing, :drift)

    def self.manifest_url(base_url) = "#{base_url}/json-sources/"

    def self.page_url(base_url, page) = "#{base_url}/sources/?segment=#{SEGMENT}&page=#{page}"

    def self.csv_url(base_url, id) = "#{base_url}/source/#{id}/csv/"

    def self.page_filename(page) = "sources-page-#{page}.html"

    def self.csv_relpath(id) = File.join(SOURCES_DIR, "#{id}.csv")

    # The source id a CSV filename names (live or superseded copy), or nil.
    def self.csv_id(filename)
      match = CSV_FILENAME.match(filename.to_s)
      match && Integer(match[1], 10)
    end

    # The manifest spells its links http://; the host 301s every one to
    # https (probed 2026-11-04), so the scheme is upgraded up front.
    def self.absolute(url) = url.to_s.strip.sub(%r{\Ahttp://}, "https://")

    # Data rows in a CSV body (quoted multi-line fields count once).
    def self.row_count(body)
      count = 0
      CSV.parse(body.to_s.dup.force_encoding(Encoding::UTF_8), headers: true) { count += 1 }
      count
    rescue CSV::MalformedCSVError
      nil
    end

    def self.sync!(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, http: http, delay: delay,
                  progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched, cached: fetch.cached,
                 sources: fetch.sources, pages: fetch.pages, advertised_sources: fetch.advertised_sources,
                 advertised_chants: fetch.advertised_chants, missing: fetch.missing, drift: fetch.drift)
    end

    def initialize(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http, delay: DELAY,
                   progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @manifest = {}
      @manifest_body = nil
      @page_bodies = {}
      @listed = {}
      @doomed = []
      @stale = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
      @drift = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :advertised_sources, :missing, :drift

    def sources = @manifest.size

    def pages = @page_bodies.size

    def advertised_chants = @listed.values.sum { |source| source.chants.to_i }

    # Phase 1 — the manifest + listing GETs; live tree untouched.
    def prepare!
      fetch_manifest!
      fetch_listing!
      check_listing!
      @doomed = doomed_relpaths
      @stale = stale_ids
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished and the superseded, land the sidecars,
    # crawl the missing exports, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      attic_superseded!
      FileUtils.mkdir_p(File.join(@dir, SOURCES_DIR))
      write!(MANIFEST_FILENAME, @manifest_body)
      @page_bodies.each { |page, body| write!(self.class.page_filename(page), body) }
      crawl_exports!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the manifest + listing ----------------------------------------------------

    def fetch_manifest!
      @progress&.call("Cantus json-sources…\n")
      body = get_with_retry(self.class.manifest_url(@base_url), id: "json-sources")
      data = JSON.parse(body)
      raise Error, "json-sources is not a JSON object" unless data.is_a?(Hash)

      @manifest = data.each_with_object({}) do |(key, entry), map|
        id = Integer(key.to_s, 10, exception: false) or next
        url = entry.is_a?(Hash) ? entry["csv"].to_s.strip : ""
        map[id] = url.empty? ? self.class.csv_url(@base_url, id) : self.class.absolute(url)
      end
      raise Error, "json-sources lists no sources — abort before any write" if @manifest.empty?

      @manifest_body = body
    rescue JSON::ParserError => e
      raise Error, "json-sources is not JSON (#{e.message}) — a maintenance page or a reshaped API; " \
                   "abort before any write"
    end

    def fetch_listing!
      page = 1
      last = 1
      while page <= last
        raise Error, "the sources listing exceeded #{MAX_PAGES} pages" if page > MAX_PAGES

        @progress&.call("Cantus sources listing page=#{page}…\n")
        body = get_with_retry(self.class.page_url(@base_url, page), id: "page=#{page}")
        begin
          rows = Adapters::CantusSourceIndex.parse_page(body)
        rescue Nabu::ParseError => e
          raise Error, "listing page=#{page}: #{e.message}"
        end
        raise Error, "listing page=#{page} lists no sources — abort before any write" if rows.empty?

        if page == 1
          @advertised_sources = Adapters::CantusSourceIndex.page_total(body)
          last = Adapters::CantusSourceIndex.last_page(body)
        end
        rows.each { |source| @listed[source.id] = source }
        @page_bodies[page] = body
        page += 1
      end
    end

    def check_listing!
      if @advertised_sources && @advertised_sources != @listed.size
        raise Error, "the listing advertises #{@advertised_sources} sources but its pages carry " \
                     "#{@listed.size} — a reshaped or truncated listing; abort before any write"
      end
      only_manifest = (@manifest.keys - @listed.keys).sort
      only_listing = (@listed.keys - @manifest.keys).sort
      return if only_manifest.empty? && only_listing.empty?

      raise Error, "json-sources and the segment-#{SEGMENT} listing disagree (manifest only: " \
                   "#{only_manifest.first(5).join(', ')}; listing only: #{only_listing.first(5).join(', ')}) — " \
                   "abort before any write"
    end

    # -- the export crawl --------------------------------------------------------------

    def crawl_exports!
      ids = @manifest.keys.sort
      ids.each_with_index do |id, index|
        @progress&.call("Cantus export #{index + 1}/#{ids.size} (source #{id})…\n") if (index % 25).zero?
        crawl_one!(id)
      end
      cap = [(ids.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} listed exports 404 — a systemic miss, not holes: the URL scheme " \
                   "moved upstream (first missing: #{@missing.first(3).join(', ')})"
    end

    def crawl_one!(id)
      rel = self.class.csv_relpath(id)
      if File.file?(File.join(@dir, rel)) && !@stale.include?(id)
        @cached += 1
        return
      end

      body = get_with_retry(@manifest.fetch(id), id: "source #{id}", missing_ok: true)
      if body.nil?
        @missing << id
        @progress&.call("Cantus export #{id}: 404 (listed — censused, crawl continues)\n")
        return
      end
      unless body.b.start_with?(HEADER_MARK)
        raise Error, "source #{id}: the body is not the CSV export (first bytes " \
                     "#{body.b[0, 40].inspect}) — a maintenance page; abort"
      end
      write!(rel, body)
      @fetched += 1
      note_drift!(id, body)
    end

    def note_drift!(id, body)
      advertised = @listed[id]&.chants
      rows = self.class.row_count(body)
      return if advertised.nil? || rows == advertised

      @drift << "#{id}: #{rows.inspect} rows, listing says #{advertised}"
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

    # -- landing / ledger -------------------------------------------------------------

    def write!(rel, body)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    def export_names
      sources = File.join(@dir, SOURCES_DIR)
      return [] unless Dir.exist?(sources)

      Dir.children(sources).sort.grep(/\A\d+\.csv\z/)
    end

    def aggregate_sha
      lines = export_names.map do |name|
        rel = File.join(SOURCES_DIR, name)
        "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => self.class.manifest_url(@base_url), "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => @sha, "sources" => sources, "pages" => pages,
                "advertised_sources" => @advertised_sources, "advertised_chants" => advertised_chants,
                "fetched" => @fetched, "cached" => @cached, "missing" => @missing, "drift" => @drift }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention ----------------------------------------------------------------------

    def doomed_relpaths
      export_names.reject { |name| @manifest.key?(self.class.csv_id(name)) }
                  .map { |name| File.join(SOURCES_DIR, name) }
    end

    # Listed exports on disk whose row count disagrees with the listing.
    def stale_ids
      export_names.filter_map do |name|
        id = self.class.csv_id(name)
        advertised = @listed[id]&.chants
        next if advertised.nil?

        rows = self.class.row_count(File.binread(File.join(@dir, SOURCES_DIR, name)))
        id unless rows == advertised
      end
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

    # A drifted export's old body, kept under its content sha so no
    # superseded version ever clobbers another.
    def attic_superseded!
      @stale.each do |id|
        source = File.join(@dir, self.class.csv_relpath(id))
        next unless File.file?(source)

        sha8 = Digest::SHA256.file(source).hexdigest[0, 8]
        rel = File.join(SOURCES_DIR, "#{id}.#{sha8}.csv")
        destination = File.join(@attic_dir, rel)
        next if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
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
