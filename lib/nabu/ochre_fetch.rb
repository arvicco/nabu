# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"
require_relative "adapters/ochre_json_parser"

module Nabu
  # Polite two-stage crawl of an OCHRE publication-set tree (P55-2; first
  # consumer: rsti) — the ElephantineFetch sibling for the U. Chicago
  # persistent-identifier resolver. Every item is one GET of
  #
  #   https://pi.lib.uchicago.edu/1001/org/ochre/<uuid>&format=json
  #
  # (NOTE the literal `&format=json` with NO `?` — the granted, working
  # form; the `?`-form serves XML).
  #
  # == The two stages
  #
  #   stage 1  the menu set (one uuid) + every set it lists — REFRESHED on
  #            every sync (the inventory listing is the corpus census; ~36
  #            small GETs, seconds). Each lands as canonical JSON:
  #            menu.json + sets/<uuid>.json, tmp+rename, validated as JSON
  #            with the expected ochre envelope BEFORE any write.
  #   stage 2  one GET per associated_uuid the set files carry (the
  #            text-side records) → texts/<uuid>.json, RESUMABLE at the
  #            file grain: a uuid already on disk is never re-fetched, so
  #            the ~90-minute first crawl resumes where it stopped and a
  #            re-sync costs stage 1 plus only the NEW uuids.
  #
  # `{"result":[]}` with HTTP 200 is the API's well-defined "not published"
  # answer (~99% of text uuids — the inventory-first verdict). It is
  # PERSISTED AS-IS: a tombstone the parse side reads honestly and the next
  # sync skips. NEVER an error.
  #
  # == Retention posture (accumulate, no attic — deliberate)
  #
  # Text detail files only ACCUMULATE (immutable per uuid, the Trismegistos
  # stance); menu/set files refresh in place. An upstream inventory shrink
  # therefore surfaces as load-time withdrawals, guarded by SyncRunner's
  # mass-withdrawal breaker — per-record attic retention is deferred until
  # churn is actually witnessed (upstream is a stable published inventory;
  # set publicationDateTimes span 2021-2025).
  #
  # Errors: HTTP failure or a malformed envelope raises OchreFetch::Error
  # (adapters wrap it in Nabu::FetchError). A 404 on a set-promised text
  # uuid is censused and skipped (the P47-i1 lesson: one upstream hole must
  # not abort a polite 90-minute crawl) — a SYSTEMIC miss rate still
  # aborts. 5xx/timeouts retry 3× with exponential backoff. Sequential
  # throughout, ≥1s between requests, honest User-Agent naming the grant.
  class OchreFetch
    # HTTP failure or a malformed/unexpected response envelope. Adapters
    # wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    RESOLVER_BASE = "https://pi.lib.uchicago.edu/1001/org/ochre/"

    STATE_FILE = ".ochre-fetch.json"
    MENU_FILE = "menu.json"
    SETS_DIRNAME = "sets"
    TEXTS_DIRNAME = "texts"

    # Seconds between HTTP requests (sequential, polite — a library
    # resolver under a personal grant).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # Attempts per GET before a 5xx/timeout becomes fatal.
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Retriable statuses; 404 is deliberately NOT here (censused on text
    # details, hard on menu/sets).
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # Miss-rate ceiling before censused text-detail 404s mean the resolver
    # or the export moved (the ElephantineFetch mold).
    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 20

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; RSTI data under grant " \
                 "№23, M. Prosser / U. Chicago CORPUS-OCHRE, 2026-07-27; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :sets, :texts_fetched, :texts_cached, :missing)

    # The one URL shape (class note): uuid + literal "&format=json".
    def self.item_url(uuid)
      "#{RESOLVER_BASE}#{uuid}&format=json"
    end

    # The API's "not published" body — {"result":[]} exactly. Served with
    # HTTP 404 on the live wire (2026-07-31); the body, not the status, is
    # the truth.
    def self.tombstone?(body)
      JSON.parse(body) == { "result" => [] }
    rescue JSON::ParserError
      false
    end

    # One-shot choreography: stage 1 then stage 2, ledger pinned at the end.
    def self.sync!(menu_uuid:, dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      new(menu_uuid: menu_uuid, dir: dir, http: http, delay: delay, progress: progress).sync!
    end

    def initialize(menu_uuid:, dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @menu_uuid = menu_uuid
      @dir = dir
      @http = http
      @delay = delay
      @progress = progress
      @requests = 0
      @sets = []
      @texts_fetched = 0
      @texts_cached = 0
      @missing = []
    end

    def sync!
      FileUtils.mkdir_p(File.join(@dir, SETS_DIRNAME))
      FileUtils.mkdir_p(File.join(@dir, TEXTS_DIRNAME))
      fetch_menu!
      fetch_sets!
      fetch_texts!
      sha = aggregate_sha
      write_state!(sha)
      Result.new(sha: sha, sets: @sets.size, texts_fetched: @texts_fetched,
                 texts_cached: @texts_cached, missing: @missing)
    end

    private

    # -- stage 1: menu + sets ---------------------------------------------------

    def fetch_menu!
      @progress&.call("OCHRE menu #{@menu_uuid}…\n")
      body = get!(self.class.item_url(@menu_uuid), context: "menu #{@menu_uuid}")
      menu = parse_envelope!(body, context: "menu #{@menu_uuid}")
      @sets = Adapters::OchreJsonParser.wrap(menu.dig("ochre", "set", "items", "set"))
                                       .filter_map { |set| set["uuid"] }
      raise Error, "menu #{@menu_uuid} lists no sets — the publication tree moved upstream" if @sets.empty?

      write!(MENU_FILE, body)
    end

    def fetch_sets!
      @sets.each_with_index do |uuid, index|
        @progress&.call("OCHRE set #{index + 1}/#{@sets.size} (#{uuid})…\n")
        body = get!(self.class.item_url(uuid), context: "set #{uuid}")
        parse_envelope!(body, context: "set #{uuid}")
        write!(File.join(SETS_DIRNAME, "#{uuid}.json"), body)
      end
    end

    # -- stage 2: text details --------------------------------------------------

    def fetch_texts!
      uuids = text_uuids
      uuids.each_with_index do |uuid, index|
        if File.file?(File.join(@dir, TEXTS_DIRNAME, "#{uuid}.json"))
          @texts_cached += 1
          next
        end

        @progress&.call("OCHRE text detail #{index + 1}/#{uuids.size} (#{uuid})…\n") if (index % 25).zero?
        body = get!(self.class.item_url(uuid), context: "text #{uuid}", missing_ok: true)
        if body.nil?
          @missing << uuid
          @progress&.call("OCHRE text #{uuid}: 404 (set-promised — censused, crawl continues)\n")
          next
        end
        write!(File.join(TEXTS_DIRNAME, "#{uuid}.json"), body)
        @texts_fetched += 1
      end
      defend_systemic_miss!(uuids.size)
    end

    # Every associated_uuid the on-disk set files carry, sorted — read from
    # disk (not the in-flight bodies) so an interrupted stage 2 resumes
    # against exactly what stage 1 landed.
    def text_uuids
      Dir.glob(File.join(@dir, SETS_DIRNAME, "*.json")).flat_map do |path|
        set = JSON.parse(File.read(path))
        Adapters::OchreJsonParser.wrap(set.dig("ochre", "set", "items", "spatialUnit"))
                                 .filter_map { |record| Adapters::OchreJsonParser.uuid_of(record["associated_uuid"]) }
      end.uniq.sort
    end

    def defend_systemic_miss!(total)
      cap = [(total * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{total} set-promised text uuids 404 — a systemic miss, " \
                   "not holes: the resolver or the publication tree moved upstream " \
                   "(first missing: #{@missing.first(3).join(', ')})"
    end

    # -- HTTP -------------------------------------------------------------------

    # One GET with the retry/backoff loop. 200 wins; on 404 the BODY decides
    # for text details (+missing_ok+): the live wire (first real sync
    # 2026-07-31) answers unpublished uuids with HTTP 404 CARRYING the
    # {"result":[]} tombstone — that is the API's honest "not published"
    # and is returned for persisting, so a resync never re-probes it; a
    # 404 with any other body is a real miss (nil, censused). Menu/sets
    # 404s raise; 5xx and transport failures retry MAX_ATTEMPTS× with
    # exponential backoff.
    def get!(url, context:, missing_ok: false)
      attempt = 0
      begin
        attempt += 1
        pause
        response = attempt_get(url)
        case response.status
        when 200 then response.body.to_s
        when 404
          if missing_ok
            body = response.body.to_s
            return body if self.class.tombstone?(body)

            return nil
          end

          raise Error, "HTTP 404 for #{url} (#{context}) — the resolver no longer serves it"
        else
          raise RetriableFailure, "HTTP #{response.status} for #{url} (#{context})"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    def attempt_get(url)
      RedirectFollow.get(url, http: @http, error: TransportFailure,
                              headers: { "User-Agent" => USER_AGENT },
                              accept: [200, 404, *RETRIABLE_STATUSES]).first
    rescue TransportFailure => e
      raise RetriableFailure, e.message
    end

    # A menu/set body must be JSON carrying the ochre envelope — a resolver
    # error page must never land in canonical.
    def parse_envelope!(body, context:)
      parsed = JSON.parse(body)
      raise Error, "#{context}: response carries no ochre envelope" unless parsed.is_a?(Hash) && parsed.key?("ochre")

      parsed
    rescue JSON::ParserError => e
      raise Error, "#{context}: response is not JSON: #{e.message}"
    end

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

    # Content pin: sorted (relpath, body-sha256) over menu + sets + texts —
    # the reproducible identity of the whole canonical tree (the
    # ElephantineFetch mold).
    def aggregate_sha
      names = [MENU_FILE] +
              Dir.glob(File.join(SETS_DIRNAME, "*.json"), base: @dir) +
              Dir.glob(File.join(TEXTS_DIRNAME, "*.json"), base: @dir)
      lines = names.select { |name| File.file?(File.join(@dir, name)) }.sort.map do |name|
        "#{name}\0#{Digest::SHA256.file(File.join(@dir, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!(sha)
      state = { "url" => self.class.item_url(@menu_uuid), "fetched_at" => Time.now.utc.iso8601,
                "last_modified" => nil, "sha256" => sha, "sets" => @sets.size,
                "texts_fetched" => @texts_fetched, "texts_cached" => @texts_cached,
                "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # Internal markers for the retry loop; never escape #get!.
    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure
  end
end
