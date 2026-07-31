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
  # Polite letter-index crawl for Cantigas Medievais Galego-Portuguesas
  # (P55-1; architecture §8) — the OtdoFetch sibling for an upstream whose
  # manifest is not ONE catalog page but 23 alphabetical incipit indexes:
  #
  #   GET <base>/listacantigas.asp?letra=<A..Z, no K/W/Y>
  #     → the incipit index for one letter (4-column rows: incipit link,
  #       music icons DUPLICATING the link, author, genre). Ids dedupe by
  #       cdcant (letter A: 326 links → 244 unique ids, census 2026-07-31).
  #       All 23 pages PERSIST in canonical as listacantigas-<L>.html — they
  #       double as metadata sidecars (the author/genre columns).
  #   GET <base>/cantiga.asp?cdcant=<id>&semanotacoes=true   per cantiga
  #     → semanotacoes=true strips the note spans/icons for clean verse
  #       lines while KEEPING author, rubric, sidebar metadata and the Nota
  #       geral (scout-verified); the cosmetic pv parameter is dropped
  #       (byte-diff-verified no-op).
  #
  # DELIBERATELY MIRRORED from OtdoFetch/ElephantineFetch, not extracted —
  # but this IS the third HTML-crawl sibling those classes name as the
  # extraction signal. The retry/attic/ledger machinery is line-for-line;
  # the manifest seam differs again (23 letter GETs + dedupe vs one numbered
  # table vs one session POST). Extraction is flagged for its own packet,
  # never smuggled into a new-source change.
  #
  # == The sparse-id ground truth (census 2026-07-31)
  #
  # cdcant is SPARSE (letter A alone reaches 1713) and an INVALID id answers
  # HTTP **500**, not 404. Therefore: enumeration comes ONLY from the letter
  # indexes (never a sequential probe), and a 500 on a LISTED id is a real
  # error — retried (RETRIABLE_STATUSES), then fatal. It is never censused
  # away, and the IIS error body never lands as a page file.
  #
  # == The honest-empty defense
  #
  # letra=Z is valid-but-empty: zero cantiga links, the page's own
  # "Não existem cantigas…" marker (its ASCII core is EMPTY_MARKER). A
  # linkless page WITHOUT the marker is a maintenance/reshape page — abort
  # loudly BEFORE any write. All 23 letters empty aborts too.
  #
  # == Resume + re-sync posture
  #
  # Pages are served by a live Classic ASP application (no Last-Modified,
  # per-session cookies), but the EDITIONS are stable critical texts. A page
  # already on disk is NOT re-fetched (resume at the file grain, the
  # TitusFetch mold): an interrupted ~29-minute first crawl resumes where it
  # stopped, and a re-sync costs 23 index GETs. Refreshing a page after an
  # upstream revision means deleting its file — or the canonical dir — and
  # re-syncing.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the 23 index GETs only — cheap, the live tree untouched;
  #              doomed = on-disk page files whose cdcant no index lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape, first copy
  #              wins), delete them, land the 23 index sidecars + missing
  #              pages (each write tmp+rename), pin the ledger.
  #
  # A 404 on a listed id is CENSUSED and skipped (the P47-i1 posture kept,
  # though upstream 500s invalid ids today); a SYSTEMIC miss rate (> the
  # cap) still aborts. 5xx AND transport-level failures retry 3× with
  # exponential backoff (P47-i2). The fetch pin is an aggregate sha256 over
  # the sorted (filename, body-sha) set of page files — the index sidecars
  # stay out (live-rendered bytes, not corpus content). Bodies land as RAW
  # Windows-1252 bytes — the decode boundary is the parser's, canonical
  # keeps what upstream served.
  class CantigasFetch
    # HTTP failure, a reshaped/markerless index, an empty census, or a
    # persistent 500/transport failure. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".cantigas-fetch.json"

    # The 23 incipit indexes — the site's own alphabet: no K/W/Y incipits
    # exist; Z is valid-but-empty and still enumerated (census 2026-07-31).
    # const: the upstream index alphabet, re-censused on shape drift
    LETTERS = (("A".."Z").to_a - %w[K W Y]).freeze

    # A page file as the crawl writes it (cantiga-<cdcant>.html).
    RECORD_FILENAME = /\Acantiga-(\d+)\.html\z/

    # A persisted letter index (canonical metadata sidecar — class note).
    INDEX_FILENAME = /\Alistacantigas-([A-Z])\.html\z/

    # The ASCII core of the empty page's own "Não existem cantigas cujo
    # título…" notice — the honest-empty marker a linkless index must carry.
    EMPTY_MARKER = "existem cantigas"

    # Seconds between HTTP requests (sequential, polite — a university
    # institute's host; ~1,700 requests ≈ 29 minutes at 1 req/s).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses; 500 IS here deliberately — upstream answers
    # invalid ids with 500, so a 500 on a listed id is a real (possibly
    # transient) failure to retry, and fatal when persistent. 404 is NOT
    # here — a missing listed page is censused (P47-i1), never retried.
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; fetching under the " \
                 "Projeto Littera attribution grant, G. V. Lopes 2026-07-27; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count, :missing)

    # Miss-rate ceiling before the crawl calls the indexes broken: a
    # fraction of the manifest, floored so tiny manifests (tests) don't
    # abort on one hole.
    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    # The per-cantiga page URL: semanotacoes=true (clean verse, metadata
    # kept), no pv (cosmetic no-op) — both scout-verified 2026-07-31.
    def self.record_url(base_url, id)
      "#{base_url}/cantiga.asp?cdcant=#{id}&semanotacoes=true"
    end

    def self.index_url(base_url, letter)
      "#{base_url}/listacantigas.asp?letra=#{letter}"
    end

    def self.record_filename(id)
      "cantiga-#{id}.html"
    end

    def self.index_filename(letter)
      "listacantigas-#{letter}.html"
    end

    # Is +filename+ a crawled cantiga page? Index sidecars and the state
    # file never match the record shape.
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

    # Phase 1 — the 23 index GETs only; live tree untouched. Extracts the
    # deduped id set, runs the honest-empty/shape defenses, computes the
    # doomed set.
    def prepare!
      LETTERS.each do |letter|
        @progress&.call("Cantigas index letra=#{letter}…\n")
        body = fetch_index(letter)
        @index_bodies[letter] = body
        harvest_ids!(letter, body)
      end
      @ids = @ids.uniq.sort_by { |id| Integer(id, 10) }
      @manifest_count = @ids.size
      defend_census!
      @doomed = doomed_relpaths
    end

    # Absolute live-tree page files no letter index lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land the index sidecars, crawl the
    # missing pages, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(@dir)
      @index_bodies.each { |letter, body| write!(self.class.index_filename(letter), body) }
      crawl_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the letter manifests ---------------------------------------------------

    def fetch_index(letter)
      get_with_retry(self.class.index_url(@base_url, letter), id: "letra=#{letter}")
    end

    # Ids scan and marker check run on the RAW bytes (the pattern and the
    # marker core are pure ASCII) — the Windows-1252 decode boundary stays
    # in the parser, never here.
    def harvest_ids!(letter, body)
      ids = body.b.scan(/cantiga\.asp\?cdcant=(\d+)/n).flatten.map { |id| id.force_encoding(Encoding::UTF_8) }
      if ids.empty? && !body.b.include?(EMPTY_MARKER.b)
        raise Error,
              "index letra=#{letter} lists no cantigas AND carries no honest-empty marker " \
              "(#{EMPTY_MARKER.inspect}) — a maintenance page or a reshaped index; abort before any write"
      end

      @ids.concat(ids)
    end

    def defend_census!
      return if @ids.any?

      raise Error, "all #{LETTERS.size} letter indexes answered with zero cantiga ids — " \
                   "the index scheme moved upstream; check #{self.class.index_url(@base_url, 'A')} by hand"
    end

    # -- the page crawl ---------------------------------------------------------

    def crawl_records!
      @ids.each_with_index do |id, index|
        name = self.class.record_filename(id)
        if File.file?(File.join(@dir, name))
          @cached += 1
          next
        end

        @progress&.call("Cantigas page #{index + 1}/#{@ids.size} (cdcant=#{id})…\n") if (index % 25).zero?
        body = get_with_retry(self.class.record_url(@base_url, id), id: id, missing_ok: true)
        if body.nil?
          # P47-i1 posture kept: a listed-but-404 page — census, skip, keep
          # crawling. (Upstream 500s invalid ids; a 500 is handled as a real
          # retriable failure above, never censused.)
          @missing << id
          @progress&.call("Cantigas page cdcant=#{id}: 404 (listed by the index — censused, crawl continues)\n")
          next
        end
        write!(name, body)
        @fetched += 1
      end
      cap = [(@ids.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@ids.size} listed cantiga ids 404 — a systemic miss, not " \
                   "holes: the page URL scheme or the indexes themselves have moved upstream " \
                   "(first missing: #{@missing.first(3).join(', ')})"
    end

    # One GET: 200 wins; a 404 returns nil when the caller censuses it
    # (listed pages, P47-i1) and raises when it cannot (a letter index —
    # 23 known-present pages, absence is real breakage); 5xx — including
    # the 500 an invalid id answers — AND transport-level failures (P47-i2)
    # retry with the same exponential backoff, then fail loudly.
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

          raise Error, "HTTP 404 for #{url} — the letter index promises #{id} but the page is missing"
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
    # The index sidecars stay out — live-rendered bytes, not corpus content.
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
                "records" => @ids.size, "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    # On-disk page files whose cdcant no letter index lists. Index sidecars
    # are infrastructure, never doomed.
    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      keep = @ids.to_set { |id| self.class.record_filename(id) }
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
