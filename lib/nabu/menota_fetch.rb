# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Polite session-based crawl for the Menota archive (P82-1, queue Q42 /
  # grant of 2026-08-20) — the CorpusCorporumFetch sibling for the Corpuscle
  # (korpuskel) REST API behind the catalogue SPA at
  # clarino.uib.no/menota/catalogue/menota (all endpoints verified live
  # 2026-08-23; the InessFetch cousin — same CLARINO house, same ephemeral
  # session):
  #
  #   GET <base>/rest?command=get-session                     {"sessionId": …}
  #   GET <base>/rest?command=list-catalogue-documents
  #       &session-id=<s>&corpus=menota&start=<a>&end=<b>     {"documents": […],
  #                                                            "documentCount": 91}
  #   GET <base>/rest?command=download-document
  #       &session-id=<s>&corpus=menota&document-id=<id>      {"data": "<TEI …>"}
  #
  # plus ONE stable public asset: https://www.menota.org/menota-entities.txt,
  # the MUFI entity table every text's DOCTYPE pulls — landed beside texts/
  # so parses stay f(canonical), fetched only when missing.
  #
  # == The blessing (why a crawl at all)
  #
  # clarino.uib.no's robots.txt reads `User-agent: * / Disallow: /`, but the
  # crawl is explicitly upstream-blessed: Stegmann (2026-08-20, the grant
  # grant) — "we will not keep you from scraping 😉" until their bulk
  # endpoint lands. When a bulk endpoint appears, this crawler RETIRES.
  # The thank-you's promises are requirements: sequential requests one
  # DELAY apart, the honest house User-Agent, once-per-text caching (a
  # text on disk is never re-requested; refresh = delete its file, the
  # Elephantine posture).
  #
  # == Volume
  #
  # 91 documents (census 2026-08-23): a full first sync is ~95 requests —
  # minutes at 1 req/s, not hours. Steady-state re-sync: session + one
  # catalogue page, then skip-on-disk.
  #
  # == Error envelopes
  #
  # The API answers errors as HTTP-200 JSON {"error": …}. On get-session or
  # the catalogue that aborts (nothing to walk); on a download it is a
  # RECORDED skip after one session refresh (sessions expire; a refreshed
  # retry heals that case) — censused in result + state, no file lands,
  # re-attempted next sync. A SYSTEMIC skip rate aborts: that shape means
  # the endpoint moved, not a restricted tail.
  #
  # == The truncation defense
  #
  # The catalogue's own documentCount rules the walk: the paged rows must
  # reach it exactly or the sync aborts BEFORE any write — a partial walk
  # must never masquerade as an upstream mass-deletion and feed the attic.
  #
  # == Retention (the house contract)
  #
  #   prepare!   session + catalogue walk only — live tree untouched;
  #              doomed = texts/<id>.xml the catalogue no longer lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape), checkpoint the
  #              catalogue, land the entity table if missing, download
  #              missing texts (skip-on-disk, error envelopes censused),
  #              pin the ledger (aggregate sha over texts/).
  class MenotaFetch
    # HTTP failure, envelope-shape drift, a truncated walk, or a systemic
    # skip rate. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".menota-fetch.json"

    # Where per-document Menota-TEI lands: texts/<documentId>.xml
    # (documentIds are catalogue-unique and filename-safe — censused
    # 2026-08-23: 91/91 match /\A[A-Za-z0-9._-]+\z/, unique downcased).
    TEXTS_DIR = "texts"

    # The MUFI entity table's landing name (the DOCTYPE dependency).
    ENTITIES_FILE = "menota-entities.txt"

    # The main archive corpus — the granted scope. The five Corpuscle
    # siblings (menota-test, menota-rune, menota-lln, menota-diploma,
    # menota-trans) stay deliberately out of v1.
    CORPUS = "menota"

    # Catalogue page size (91 documents censused — one page today; the
    # loop still pages so growth never truncates silently).
    # const: request-batching grain, not a corpus claim
    PAGE_SIZE = 200

    # Seconds between HTTP requests (sequential, polite — the grant
    # promise; a university server).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    # Skip-rate ceiling before the crawl calls the endpoint moved (the
    # CorpusCorporum/Elephantine cap mold, floored low — 91 docs total).
    # const: abort threshold, not a corpus claim
    SKIP_CAP_FRACTION = 0.02
    SKIP_CAP_FLOOR = 3

    Result = Data.define(:sha, :atticked, :fetched, :cached, :refused,
                         :malformed, :documents)

    def self.rest_url(base_url, command, params = {})
      query = params.map { |key, value| "&#{key}=#{URI.encode_uri_component(value.to_s)}" }.join
      "#{base_url}/rest?command=#{command}#{query}"
    end

    def self.text_relpath(document_id)
      File.join(TEXTS_DIR, "#{document_id}.xml")
    end

    # One-shot choreography. +guard+ receives the absolute doomed paths
    # between prepare! and complete!.
    def self.sync!(base_url:, entities_url:, dir:, attic_dir:,
                   http: ZipFetch.default_http, delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, entities_url: entities_url, dir: dir,
                  attic_dir: attic_dir, http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, refused: fetch.refused, malformed: fetch.malformed,
                 documents: fetch.documents)
    end

    def initialize(base_url:, entities_url:, dir:, attic_dir:,
                   http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @base_url = base_url
      @entities_url = entities_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @catalogue = []
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @refused = []
      @malformed = []
      @requests = 0
    end

    attr_reader :atticked, :sha, :fetched, :cached, :refused, :malformed

    def documents = @catalogue.size

    # Phase 1 — session + the catalogue walk only; live tree untouched.
    def prepare!
      @session_id = fresh_session
      @catalogue = walk_catalogue!
      @doomed = doomed_relpaths
    end

    # Absolute live-tree text files the catalogue no longer lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, checkpoint the catalogue (BEFORE the
    # download phase, so an interrupted crawl records what it walked), land
    # the entity table if missing, download missing texts, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(File.join(@dir, TEXTS_DIR))
      write_state!(sha: nil)
      fetch_entities!
      download_texts!
      @sha = aggregate_sha
      write_state!(sha: @sha)
    end

    private

    # -- the session ------------------------------------------------------------

    def fresh_session
      envelope = json_envelope(self.class.rest_url(@base_url, "get-session"),
                               context: "get-session")
      envelope["sessionId"].to_s.then do |id|
        raise Error, "get-session returned no sessionId (keys: #{envelope.keys.join(', ')})" if id.empty?

        id
      end
    end

    # -- the catalogue walk -----------------------------------------------------

    def walk_catalogue!
      rows = []
      promised = nil
      loop do
        page = catalogue_page(start: rows.size)
        promised ||= page["documentCount"]
        page_rows = page["documents"]
        rows.concat(page_rows)
        break if rows.size >= promised.to_i
        next unless page_rows.empty?

        raise Error, "catalogue walk is TRUNCATED: list-catalogue-documents promises " \
                     "#{promised} documents but paging stalled at #{rows.size} — the envelope " \
                     "shape moved, or the walk was cut; aborting before any write"
      end
      @progress&.call("menota catalogue: #{rows.size} documents listed\n")
      rows
    end

    def catalogue_page(start:)
      url = self.class.rest_url(@base_url, "list-catalogue-documents",
                                "session-id" => @session_id, "corpus" => CORPUS,
                                "start" => start, "end" => start + PAGE_SIZE - 1)
      page = json_envelope(url, context: "list-catalogue-documents")
      unless page["documents"].is_a?(Array) && page["documentCount"].is_a?(Integer)
        raise Error, "list-catalogue-documents did not return documents+documentCount " \
                     "(keys: #{page.keys.join(', ')}) — the envelope shape moved upstream"
      end

      page
    end

    # -- the entity table -------------------------------------------------------

    # Fetched ONCE — the table is a slow-moving published asset; refresh =
    # delete the file (the once-per-asset cache promise).
    def fetch_entities!
      target = File.join(@dir, ENTITIES_FILE)
      return if File.file?(target)

      body = get_with_retry(@entities_url)
      unless body.include?("<!ENTITY")
        raise Error, "#{@entities_url} did not return an entity table (no <!ENTITY declarations)"
      end

      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
      @progress&.call("menota entity table landed (#{ENTITIES_FILE})\n")
    end

    # -- the download phase -----------------------------------------------------

    def download_texts!
      planned = @catalogue.uniq { |row| row["documentId"] }
      planned.each_with_index do |row, index|
        id = row["documentId"]
        if File.file?(File.join(@dir, self.class.text_relpath(id)))
          @cached += 1
          next
        end

        @progress&.call("menota text #{index + 1}/#{planned.size} (#{id})…\n") if (index % 10).zero?
        fetch_text!(id)
      end
      cap = [(planned.size * SKIP_CAP_FRACTION).ceil, SKIP_CAP_FLOOR].max
      skipped = @refused.size + @malformed.size
      return if skipped < cap

      raise Error, "#{skipped} of #{planned.size} downloads refused or malformed — a systemic " \
                   "rate, not a restricted tail: download-document moved upstream " \
                   "(first: #{(@refused.first(3) + @malformed.first(3)).first(3).join(', ')})"
    end

    def fetch_text!(id)
      data = download_data(id)
      if data.nil?
        @refused << id
        @progress&.call("menota text #{id}: error envelope after a session refresh — " \
                        "recorded skip, re-attempted next sync\n")
        return
      end
      unless data.include?("<TEI")
        @malformed << id
        @progress&.call("menota text #{id}: data field is not Menota-TEI — recorded skip\n")
        return
      end

      write_text!(id, data)
      @fetched += 1
    end

    # The data string, or nil for a persistent error envelope. Sessions
    # expire mid-crawl: ONE refresh heals that case before the skip is
    # recorded.
    def download_data(id)
      envelope = download_envelope(id)
      if envelope.key?("error")
        @session_id = fresh_session
        envelope = download_envelope(id)
        return nil if envelope.key?("error")
      end
      envelope["data"].to_s
    end

    def download_envelope(id)
      json_envelope(self.class.rest_url(@base_url, "download-document",
                                        "session-id" => @session_id, "corpus" => CORPUS,
                                        "document-id" => id),
                    context: "download-document #{id}")
    end

    # -- HTTP -------------------------------------------------------------------

    def json_envelope(url, context:)
      body = get_with_retry(url)
      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "#{context} did not return JSON (body starts: #{body.to_s[0, 80].inspect}) — " \
                   "the API shape moved upstream"
    end

    def get_with_retry(url)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure,
                                  headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        raise RetriableFailure, "HTTP #{response.status} for #{url}" unless response.status == 200

        response.body.to_s
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Internal markers; never escape get_with_retry.
    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    # -- landing / ledger -------------------------------------------------------

    def write_text!(id, data)
      target = File.join(@dir, self.class.text_relpath(id))
      File.binwrite("#{target}.tmp", data.encode(Encoding::UTF_8).b)
      File.rename("#{target}.tmp", target)
    end

    # Content pin: sorted (filename, body-sha256) over texts/ on disk —
    # a reproducible content identity, the non-git ledger mold.
    def aggregate_sha
      texts_dir = File.join(@dir, TEXTS_DIR)
      names = Dir.exist?(texts_dir) ? Dir.children(texts_dir).grep(/\.xml\z/).sort : []
      lines = names.map do |name|
        "#{name}\0#{Digest::SHA256.file(File.join(texts_dir, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    # The catalogue rows ride the ledger VERBATIM: per-document license
    # (the quotable BY-SA record), language, origDate, wordCount, the
    # facs/dipl/norm availability flags — the census the gate quotes.
    def write_state!(sha:)
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "sha256" => sha, "corpus" => CORPUS,
                "documents" => documents, "catalogue" => @catalogue,
                "refused" => @refused.sort, "malformed" => @malformed.sort,
                "fetched" => @fetched, "cached" => @cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    def previous_state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    # -- retention --------------------------------------------------------------

    # On-disk text files whose documentId the catalogue no longer lists.
    def doomed_relpaths
      texts_dir = File.join(@dir, TEXTS_DIR)
      return [] unless Dir.exist?(texts_dir)

      keep = @catalogue.to_set { |row| "#{row['documentId']}.xml" }
      Dir.children(texts_dir).sort
         .select { |name| name.end_with?(".xml") && !keep.include?(name) }
         .map { |name| File.join(TEXTS_DIR, name) }
    end

    # First copy wins; GitFetch's manifest format so the adapter base class
    # rediscovers the attic generically.
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
      pin = previous_state["sha256"] || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
