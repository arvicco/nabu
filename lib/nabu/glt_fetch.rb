# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"
require_relative "adapters/glt_html_parser"

module Nabu
  # Paced, conditional crawl of glt.goarch.org (Adapters::Glt) — the
  # LotsawaFetch sibling for a site whose two index pages ARE the catalog
  # (no bulk archive, no sitemap, no directory listings; census in the
  # adapter's class comment).
  #
  # == The walk
  #
  #   1. GET index.html and extra.htm (both required); the crawl list = every
  #      in-site link of either to a texts/<shelf>/<page>.html page
  #      (percent-decoded on disk: "texts/Oro/Esperinos Sunday.html"),
  #      first occurrence wins. An index yielding no text links at all (a
  #      maintenance page, a reshaped site) aborts BEFORE any write.
  #   2. GET each listed page, one request per DELAY, nabu User-Agent. A
  #      page held on disk with a pinned Last-Modified is asked
  #      conditionally (If-Modified-Since): 304 = unchanged, no write.
  #
  # A 404 on a listed page is CENSUSED (upstream's own 404 page reads "File
  # is waiting to be re-formatted"), never fatal — unless the misses are
  # systemic (> the cap). 5xx and transport failures retry MAX_ATTEMPTS×
  # with exponential backoff. Every non-HTML link (the .epub twins, the
  # PDFs, the .rtf), the compiled daily services, misc/ and the mp3s are
  # never fetched.
  #
  # == Retention (the house contract)
  #
  #   prepare!   the two index pages only; the live tree untouched;
  #              doomed = on-disk texts/ pages the index no longer lists.
  #   [guard]    the caller's mass-deletion breaker.
  #   complete!  attic the doomed (GitFetch manifest shape), delete them,
  #              land the index pages, crawl (each page tmp+rename as it
  #              arrives — an interrupted crawl keeps what it landed), pin
  #              the ledger (aggregate sha over the texts/ pages) and the
  #              per-page Last-Modified in STATE_FILE.
  class GltFetch
    class Error < Nabu::Error; end

    BASE_URL = "https://glt.goarch.org/"
    STATE_FILE = ".glt-fetch.json"
    # const: the site's two catalog pages (the index and its "other services" page), not a count
    CATALOG_PAGES = %w[index.html extra.htm].freeze
    TEXT_PAGE = %r{\Atexts/[^/]+/[^/]+\.html\z}

    # const: crawl politeness pause (a small church site), not a corpus claim
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze
    # const: abort threshold for listed pages that 404, not a corpus claim
    MISSING_CAP_FRACTION = 0.05
    # const: abort-threshold floor, not a corpus claim
    MISSING_CAP_FLOOR = 5
    # const: progress-line cadence, not a corpus claim
    PROGRESS_EVERY = 25

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :listed, :fetched, :unchanged, :missing)
    Listed = Data.define(:rel, :href)

    def self.sync!(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http, delay: DELAY,
                   progress: nil, guard: nil)
      fetch = new(dir: dir, attic_dir: attic_dir, base_url: base_url, http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, listed: fetch.listed.size, fetched: fetch.fetched,
                 unchanged: fetch.unchanged, missing: fetch.missing)
    end

    # The crawl list of the two index pages' bodies (name => html): the
    # texts/ .html links, first occurrence wins, in index order.
    def self.crawl_list(catalog)
      seen = {}
      CATALOG_PAGES.each do |name|
        html = catalog.fetch(name)
        Adapters::GltHtmlParser.index_entries(html, list: name).each do |entry|
          next unless entry.rel.match?(TEXT_PAGE)

          seen[entry.rel] ||= Listed.new(rel: entry.rel, href: entry.href.sub(%r{\A(\./)+}, ""))
        end
      end
      seen.values
    end

    def initialize(dir:, attic_dir:, base_url: BASE_URL, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @dir = dir
      @attic_dir = attic_dir
      @base_url = base_url
      @http = http
      @delay = delay
      @progress = progress
      @catalog = {}
      @listed = []
      @doomed = []
      @atticked = []
      @missing = []
      @fetched = 0
      @unchanged = 0
      @requests = 0
      @pins = previous_state.fetch("pages", {})
    end

    attr_reader :atticked, :sha, :listed, :fetched, :unchanged, :missing

    # Phase 1 — the two index pages; live tree untouched.
    def prepare!
      CATALOG_PAGES.each do |name|
        response = get_with_retry("#{@base_url}#{name}")
        raise Error, "the catalog page #{name} is missing (404)" if response.nil?

        @catalog[name] = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      end
      @listed = self.class.crawl_list(@catalog)
      if @listed.empty?
        raise Error, "index.html + extra.htm list no texts/ pages — a maintenance page or a reshaped " \
                     "site; nothing written"
      end

      @doomed = doomed_relpaths
    end

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    # Phase 2 — attic the delisted, land the catalog, crawl the pages.
    def complete!
      attic_doomed!
      @doomed.each do |rel|
        FileUtils.rm_f(File.join(@dir, rel))
        @pins.delete(rel)
      end
      @catalog.each { |name, body| write!(name, body) }
      crawl!
      @sha = aggregate_sha
      write_state!
    end

    private

    def crawl!
      @listed.each_with_index do |page, index|
        if ((index + 1) % PROGRESS_EVERY).zero?
          @progress&.call("glt page #{index + 1}/#{@listed.size} (#{page.rel})…\n")
        end
        crawl_one!(page)
      end
      cap = [(@listed.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@listed.size} listed pages 404 — a systemic miss, not holes " \
                   "(first missing: #{@missing.first(3).join(', ')})"
    end

    def crawl_one!(page)
      target = File.join(@dir, page.rel)
      pin = @pins[page.rel]
      since = File.file?(target) && pin && pin["last_modified"]
      response = get_with_retry("#{@base_url}#{page.href}", since: since)
      if response.nil?
        @missing << page.rel
      elsif response.status == 304
        @unchanged += 1
      else
        body = response.body.to_s.b
        write!(page.rel, body) unless File.file?(target) && Digest::SHA256.file(target).hexdigest ==
                                                            Digest::SHA256.hexdigest(body)
        @pins[page.rel] = { "sha256" => Digest::SHA256.hexdigest(body),
                            "last_modified" => response.headers["last-modified"] }.compact
        @fetched += 1
      end
    end

    # The response (200, or 304 when +since+ is given); nil on 404.
    def get_with_retry(url, since: nil)
      attempt = 0
      headers = { "User-Agent" => USER_AGENT }
      headers["If-Modified-Since"] = since if since
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure, headers: headers,
                                  accept: [200, 304, 404, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        case response.status
        when 200, 304 then response
        when 404 then nil
        else raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    def write!(rel, body)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    def page_files
      return [] unless Dir.exist?(@dir)

      Dir.glob("texts/**/*.html", base: @dir).grep(TEXT_PAGE).sort
    end

    def aggregate_sha
      lines = page_files.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601, "last_modified" => nil,
                "sha256" => @sha, "listed" => @listed.size, "fetched" => @fetched, "unchanged" => @unchanged,
                "missing" => @missing, "pages" => @pins.sort.to_h }
      FileUtils.mkdir_p(@dir)
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    def previous_state
      path = File.join(@dir, STATE_FILE)
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    rescue JSON::ParserError
      {}
    end

    # -- retention --------------------------------------------------------------

    def doomed_relpaths
      keep = @listed.to_set(&:rel)
      page_files.reject { |rel| keep.include?(rel) }
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
      pin = previous_state["sha256"] || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      FileUtils.mkdir_p(@attic_dir)
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
