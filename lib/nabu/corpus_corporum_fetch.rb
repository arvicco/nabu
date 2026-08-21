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
  # Polite catalog-walk crawl for Corpus Córporum (mlat.uzh.ch, Univ. of
  # Zurich; P80-2, architecture §8) — the ElephantineFetch sibling for an
  # upstream that is neither a git repo nor a zip nor a bulk dump but a
  # de-facto XML API (both endpoints re-verified live 2026-08-19):
  #
  #   GET <base>/php_modules/navigate.php?path=/            corpora listing
  #   GET <base>/php_modules/navigate.php?path=/<c>         author listing
  #   GET <base>/php_modules/navigate.php?path=/<c>/<a>     work listing
  #   GET <base>/php_modules/navigate.php?path=/<c>/<a>/<w> text idnos
  #   GET <base>/php_modules/download.php?idno=<i>&type=file-xml  one TEI
  #
  # (namespace http://mlat.uzh.ch/2.0; path segments are cc idnos, NOT the
  # display "nr" — Patrologia Latina is nr 2 but idno 38). The v1 scope is
  # the PL corpus: 5,277 texts / 85.5M words (census 2026-08-19); the walk is
  # corpus-generic, so widening scope is a constant, not a rewrite.
  #
  # == Politeness + volume
  #
  # A full PL walk is ~6,700 catalog GETs + 5,277 downloads. Sequential, one
  # request per DELAY second, house User-Agent (robots.txt: Allow /). The
  # measured latency is ~0.5 s/request → a first full sync is an
  # owner-initiated multi-hour crawl, which is why resumability is TWO-GRAIN:
  #
  # - texts resume by file existence (the TitusFetch/Elephantine mold);
  # - the walked catalog is CHECKPOINTED into the state file before the
  #   download phase, keyed per author by the corpus listing's texts_count —
  #   a re-sync re-walks only authors whose count drifted. PL is a closed
  #   print corpus (Migne 1844–1864), so the steady-state re-sync costs two
  #   catalog GETs; a text whose CONTENT churns upstream without a count
  #   drift is refreshed by deleting its file (the Elephantine posture).
  #
  # == The refusal body (a recorded skip)
  #
  # Restricted/missing texts return a polite plain-text refusal ("We are
  # sorry, this XML file doesn't exist or can't be downloaded.") with HTTP
  # 200. That is a RECORDED skip: censused in the result + state, no file
  # lands, the crawl continues, and the next sync re-attempts (upstream may
  # unlock a text). A SYSTEMIC refusal rate (> REFUSED_CAP) aborts — that
  # shape means the download endpoint moved, not a restricted tail. A 200
  # body that is neither TEI nor the refusal is retried with backoff
  # (P80-r2 — the live crawl died at hour 9 on ONE transient garbage body;
  # the same idno served valid TEI on re-probe); a PERSISTENT wrong shape
  # is a recorded malformed skip counted against the same systemic cap.
  #
  # == The truncation defense
  #
  # The corpus listing carries per-author texts_count; the walked text set
  # must reach at least (1 - TRUNCATION_TOLERANCE) of their sum or the sync
  # aborts BEFORE any write — a partial walk must never masquerade as an
  # upstream mass-deletion and feed the attic.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the catalog walk only — live tree untouched; doomed =
  #              on-disk texts/<idno>.xml the walk no longer lists.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged.
  #   complete!  attic the doomed (GitFetch manifest shape), checkpoint the
  #              catalog, download missing texts (skip-on-disk, refusals
  #              censused), pin the ledger (aggregate sha over texts/).
  class CorpusCorporumFetch
    # HTTP failure, catalog shape drift, a truncated walk, or a systemic
    # refusal rate. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".corpus-corporum-fetch.json"

    # Where per-text TEI lands: texts/<idno>.xml (idnos are globally unique
    # upstream — the download endpoint is keyed on them alone).
    TEXTS_DIR = "texts"

    # Patrologia Latina's cc idno (NOT its display nr 2) — the v1 scope.
    PL_CORPUS_IDNO = "38"
    DEFAULT_CORPUS_IDNOS = [PL_CORPUS_IDNO].freeze

    # Seconds between HTTP requests (sequential, polite — a university
    # server; measured ~0.5 s/response, so 1 req/s dominates the crawl).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # Wrong-shape 200 re-asks before the body counts as malformed (P80-r2).
    # const: retry ceiling, not a corpus claim
    SHAPE_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    # The refusal body's stable opening (re-verified 2026-08-19).
    REFUSAL_PREFIX = "We are sorry"

    # Checkpoint schema: 2 = the P81-1 dating capture (per-author
    # born/died + per-work work_composition years ride the catalog rows).
    # A checkpoint from an earlier schema is never reused — see
    # #previous_catalog.
    # const: a state-file format version, not a corpus claim
    CATALOG_SCHEMA = 2

    # Refusal-rate ceiling before the crawl calls the endpoint moved
    # (the Elephantine MISSING_CAP mold).
    # const: abort threshold, not a corpus claim
    REFUSED_CAP_FRACTION = 0.01
    REFUSED_CAP_FLOOR = 20

    # Walked-vs-promised shortfall the walk tolerates (upstream count
    # drift); anything worse is a truncated walk, not a corpus change.
    # const: abort threshold, not a corpus claim
    TRUNCATION_TOLERANCE = 0.01

    Result = Data.define(:sha, :atticked, :fetched, :cached, :refused,
                         :malformed, :inaccessible, :texts, :corpora)

    def self.navigate_url(base_url, path)
      "#{base_url}/php_modules/navigate.php?path=#{path}"
    end

    def self.download_url(base_url, idno)
      "#{base_url}/php_modules/download.php?idno=#{idno}&type=file-xml"
    end

    def self.text_relpath(idno)
      File.join(TEXTS_DIR, "#{idno}.xml")
    end

    # One-shot choreography. +guard+ receives the absolute doomed paths
    # between prepare! and complete!.
    def self.sync!(base_url:, dir:, attic_dir:, corpus_idnos: DEFAULT_CORPUS_IDNOS,
                   http: ZipFetch.default_http, delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir,
                  corpus_idnos: corpus_idnos, http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, refused: fetch.refused, malformed: fetch.malformed,
                 inaccessible: fetch.inaccessible, texts: fetch.texts, corpora: fetch.corpora)
    end

    def initialize(base_url:, dir:, attic_dir:, corpus_idnos: DEFAULT_CORPUS_IDNOS,
                   http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @corpus_idnos = corpus_idnos.map(&:to_s)
      @http = http
      @delay = delay
      @progress = progress
      @corpora = []
      @catalog = {} # author idno => {"texts_count" =>, "texts" => [{"idno" =>, "accessible" =>}]}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @refused = []
      @malformed = []
      @requests = 0
    end

    attr_reader :atticked, :sha, :fetched, :cached, :refused, :malformed, :corpora

    def texts = walked_texts.size

    def inaccessible = walked_texts.count { |text| !text["accessible"] }

    # Phase 1 — the catalog walk only; live tree untouched. Reuses the
    # previous checkpoint per author (texts_count match), defends against a
    # truncated walk, computes the doomed set.
    def prepare!
      previous = previous_catalog
      walk_corpora!(previous)
      defend_truncation!
      @doomed = doomed_relpaths
    end

    # Absolute live-tree text files the walked catalog no longer lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, checkpoint the catalog (BEFORE the long
    # download phase, so an interrupted crawl resumes without re-walking),
    # download missing texts, pin the ledger.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(File.join(@dir, TEXTS_DIR))
      write_state!(sha: nil)
      download_texts!
      @sha = aggregate_sha
      write_state!(sha: @sha)
    end

    private

    # -- the catalog walk -------------------------------------------------------

    def walk_corpora!(previous)
      listed = corpora_listing
      @corpus_idnos.each do |corpus_idno|
        corpus = listed[corpus_idno] or
          raise Error, "corpus idno #{corpus_idno} is not in the navigate.php root listing — " \
                       "the catalog shape or the corpus set moved upstream"
        @corpora << corpus
        walk_corpus!(corpus, previous)
      end
    end

    def corpora_listing
      xml = navigation(path: "/")
      rows = xml.xpath("//contents/corpus").map do |node|
        { "idno" => child_text(node, "idno"), "name" => child_text(node, "name"),
          "texts_count" => Integer(child_text(node, "texts_count"), 10),
          "words_count" => Integer(child_text(node, "words_count"), 10) }
      end
      raise Error, "navigate.php root listing carries no corpora — upstream page shape changed" if rows.empty?

      rows.to_h { |row| [row["idno"], row] }
    end

    def walk_corpus!(corpus, previous)
      authors = author_rows(corpus)
      @progress&.call("corpus-corporum catalog: corpus #{corpus['idno']} (#{corpus['name']}) — " \
                      "#{authors.size} authors…\n")
      authors.each_with_index do |author, index|
        if (index % 25).zero? && index.positive?
          @progress&.call("corpus-corporum catalog: author #{index + 1}/#{authors.size} (#{author['idno']})…\n")
        end
        @catalog[author["idno"]] =
          reusable(previous, author) || walk_author(corpus_idno: corpus["idno"], author: author)
      end
    end

    def author_rows(corpus)
      xml = navigation(path: "/#{corpus['idno']}")
      rows = xml.xpath("//contents/author").map do |node|
        { "idno" => child_text(node, "idno"),
          "texts_count" => Integer(child_text(node, "texts_count"), 10) }
      end
      rows.sort_by { |row| row["idno"].to_i }
    end

    # The checkpoint reuse rule: an author whose corpus-listing texts_count
    # matches the previous walk keeps its text set — no requests.
    def reusable(previous, author)
      row = previous[author["idno"]]
      row if row && row["texts_count"] == author["texts_count"]
    end

    def walk_author(corpus_idno:, author:)
      author_path = "/#{corpus_idno}/#{author['idno']}"
      author_page = navigation(path: author_path)
      born, died = author_years(author_page)
      texts = author_page.xpath("//contents/work/idno").map(&:text).flat_map do |work_idno|
        work_page = navigation(path: "#{author_path}/#{work_idno}")
        composition = work_composition(work_page)
        work_page.xpath("//contents/text").map do |node|
          { "idno" => child_text(node, "idno"),
            "accessible" => child_text(node, "accessible") == "1",
            "work_composition" => composition }
        end
      end
      { "texts_count" => author["texts_count"], "born" => born, "died" => died, "texts" => texts }
    end

    # -- the dating capture (P81-1) ---------------------------------------------
    #
    # The walked author/work pages carry <time_data> the crawl previously
    # discarded — per-author born/died events, per-work work_composition
    # years. Both pages are already requested, so the capture costs zero
    # extra GETs; it rides the checkpoint, where the TEI parser side reads
    # it at parse time (the state file IS canonical/<slug> content).

    # born envelopes to its EARLIEST year, died to its LATEST (a
    # certainty="between" event carries date1+date2) — the honest life
    # band. An absent event stays nil, never guessed.
    def author_years(page)
      [event_years(page, "born")&.min, event_years(page, "died")&.max]
    end

    def work_composition(page)
      event_years(page, "work_composition")&.minmax
    end

    def event_years(page, what)
      years = page.xpath("//last_step//time_data/event[@what='#{what}']//year").filter_map do |node|
        text = node.text.strip
        Integer(text, 10) if /\A-?\d+\z/.match?(text)
      end
      years.empty? ? nil : years
    end

    def walked_texts
      @catalog.values.flat_map { |row| row["texts"] }
    end

    # A partial walk must never read as an upstream mass-deletion: the
    # walked text set must reach the corpus listings' own per-author sum.
    def defend_truncation!
      promised = @catalog.values.sum { |row| row["texts_count"] }
      walked = walked_texts.size
      return if promised.zero? || walked >= promised * (1 - TRUNCATION_TOLERANCE)

      raise Error, "catalog walk is TRUNCATED: the corpus listing promises #{promised} texts " \
                   "but the walk found #{walked} of #{promised} — navigate.php's shape moved, " \
                   "or the walk was cut; aborting before any write"
    end

    # -- the download phase -----------------------------------------------------

    def download_texts!
      # uniq: a text listed under two authors (shared works) downloads once.
      planned = walked_texts.select { |text| text["accessible"] }.uniq { |text| text["idno"] }
      planned.each_with_index do |text, index|
        idno = text["idno"]
        if File.file?(File.join(@dir, self.class.text_relpath(idno)))
          @cached += 1
          next
        end

        @progress&.call("corpus-corporum text #{index + 1}/#{planned.size} (idno #{idno})…\n") if (index % 50).zero?
        fetch_text!(idno)
      end
      cap = [(planned.size * REFUSED_CAP_FRACTION).ceil, REFUSED_CAP_FLOOR].max
      skipped = @refused.size + @malformed.size
      return if skipped <= cap

      raise Error, "#{skipped} of #{planned.size} downloads refused or malformed — a systemic " \
                   "rate, not a restricted tail: download.php moved upstream " \
                   "(first: #{(@refused.first(3) + @malformed.first(3)).first(3).join(', ')})"
    end

    def fetch_text!(idno)
      body = text_body_with_shape_retry(idno)
      if body.lstrip.start_with?(REFUSAL_PREFIX)
        @refused << idno
        @progress&.call("corpus-corporum text #{idno}: refused upstream " \
                        "(\"#{REFUSAL_PREFIX}…\" — recorded skip, crawl continues)\n")
        return
      end
      unless body.include?("<TEI")
        @malformed << idno
        @progress&.call("corpus-corporum text #{idno}: 200 body neither TEI nor the refusal " \
                        "after #{SHAPE_ATTEMPTS} attempts — recorded skip, re-attempted next sync\n")
        return
      end

      write_text!(idno, body)
      @fetched += 1
    end

    # A wrong-shape 200 re-asks with backoff before it counts (P80-r2):
    # gateways flake, and one garbage body among thousands is a flake
    # until it persists.
    def text_body_with_shape_retry(idno)
      url = self.class.download_url(@base_url, idno)
      body = get_with_retry(url)
      attempt = 1
      until attempt >= SHAPE_ATTEMPTS || expected_shape?(body)
        sleep(@delay * (2**attempt)) if @delay.positive?
        body = get_with_retry(url)
        attempt += 1
      end
      body
    end

    def expected_shape?(body)
      body.include?("<TEI") || body.lstrip.start_with?(REFUSAL_PREFIX)
    end

    # -- HTTP -------------------------------------------------------------------

    def navigation(path:)
      body = get_with_retry(self.class.navigate_url(@base_url, path))
      xml = Nokogiri::XML(body.dup.force_encoding(Encoding::UTF_8))
      xml.remove_namespaces!
      unless xml.root&.name == "navigation"
        raise Error, "navigate.php?path=#{path} did not return a <navigation> document — " \
                     "the catalog shape moved upstream"
      end

      xml
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

    def child_text(node, name)
      text = node.at_xpath(name)&.text
      raise Error, "navigate.php listing row lacks <#{name}> — the catalog shape moved upstream" if text.nil?

      text
    end

    # -- landing / ledger -------------------------------------------------------

    def write_text!(idno, body)
      target = File.join(@dir, self.class.text_relpath(idno))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    # Content pin: sorted (filename, body-sha256) over texts/ on disk —
    # a reproducible content identity, the non-git ledger mold.
    def aggregate_sha
      texts_dir = File.join(@dir, TEXTS_DIR)
      names = Dir.exist?(texts_dir) ? Dir.children(texts_dir).grep(/\A\d+\.xml\z/).sort : []
      lines = names.map do |name|
        "#{name}\0#{Digest::SHA256.file(File.join(texts_dir, name)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!(sha:)
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601,
                "sha256" => sha, "catalog_schema" => CATALOG_SCHEMA,
                "corpora" => @corpora, "catalog" => @catalog,
                "refused" => @refused.sort, "malformed" => @malformed.sort, "texts" => texts,
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

    # A checkpoint written by an earlier catalog schema is NOT reused: the
    # P81-1 dating capture must reach every author once, and PL is a
    # closed corpus whose texts_count never drifts — reuse would keep the
    # dating lane dark forever. One full re-walk (~6,700 GETs, owner-fired)
    # pays for it; thereafter the count-match reuse rule applies as before.
    def previous_catalog
      state = previous_state
      return {} unless state["catalog_schema"] == CATALOG_SCHEMA

      state.fetch("catalog", {})
    end

    # -- retention --------------------------------------------------------------

    # On-disk text files whose idno the walked catalog no longer lists.
    def doomed_relpaths
      texts_dir = File.join(@dir, TEXTS_DIR)
      return [] unless Dir.exist?(texts_dir)

      keep = walked_texts.to_set { |text| "#{text['idno']}.xml" }
      Dir.children(texts_dir).sort
         .select { |name| /\A\d+\.xml\z/.match?(name) && !keep.include?(name) }
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
