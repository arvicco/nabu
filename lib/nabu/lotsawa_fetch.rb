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
  # Paced, resumable catalog crawl for Lotsawa House (lotsawahouse.org) —
  # the OtdoFetch sibling for a site with NO bulk export, NO sitemap
  # (/sitemap.xml 404) and per-language catalog pages instead of one table.
  # The site's own terms license crawling "for indexing (subject to
  # reasonable network usage constraints)": one sequential request per
  # second, a nabu-identifying User-Agent, robots.txt honored (it disallows
  # only /app/, /search, /<lang>/search and /Cgi — none of which this
  # crawl touches).
  #
  # == The catalog walk (per language in scope)
  #
  #   1. the language's explore page (EXPLORE[lang]) — every author
  #      listing link (<pre>/tibetan-masters/<a>/, <pre>/indian-masters/<a>/)
  #      plus any text linked directly (the nl and zh pages list texts);
  #   2. the language's Words of the Buddha page (<pre>/words-of-the-buddha/);
  #   3. every author listing page — the texts AVAILABLE IN THAT LANGUAGE
  #      (cross-filed texts — a prayer FOR a master listed on his page —
  #      dedupe by URL);
  #   4. every text page not yet on disk.
  #
  # en is unprefixed on the site; every other language is /<lang>/. Listing
  # pages are re-fetched on every sync and persisted under catalog/<lang>/
  # (the catalog grain, provenance only — the adapter skips them by rule);
  # text pages land at pages/<lang>/<path>.html and are NOT re-fetched while
  # on disk (resume at the file grain — an interrupted crawl continues where
  # it stopped; refreshing a revised page means deleting its file).
  #
  # == Defenses
  #
  # An explore page yielding no links at all (a maintenance page, a
  # reshaped site) aborts BEFORE any write. A 404 on a listing or text page
  # is CENSUSED and skipped (the P47-i1 lesson); a systemic text-page miss
  # rate (> the cap) aborts. 5xx and transport failures retry 3× with
  # exponential backoff (P47-i2).
  #
  # == Retention (the house contract)
  #
  #   prepare!   the catalog walk only (steps 1–3); the live tree untouched;
  #              doomed = on-disk text pages of an in-scope language the walk
  #              no longer lists.
  #   [guard]    the caller's mass-deletion breaker.
  #   complete!  attic the doomed (GitFetch manifest shape), delete them,
  #              land the catalog pages, crawl the missing text pages, pin
  #              the ledger (an aggregate sha over the text-page files).
  #
  # DELIBERATELY MIRRORED from OtdoFetch (itself mirrored from
  # ElephantineFetch): the retry/attic/ledger machinery line-for-line, the
  # catalog acquisition this site's own. Third HTML-crawl sibling — the
  # extraction signal OtdoFetch named; extraction is its own change.
  class LotsawaFetch
    class Error < Nabu::Error; end

    BASE_URL = "https://www.lotsawahouse.org"
    STATE_FILE = ".lotsawa-fetch.json"
    PAGES_DIR = "pages"
    CATALOG_DIR = "catalog"

    # The site's nine languages; en has no URL prefix.
    # const: the site's own language set (the language switcher), not a corpus count
    LANGUAGES = %w[bo en de es fr it nl pt zh].freeze

    # Each language's explore page (the nl/zh pages carry their own names).
    EXPLORE = Hash.new { |_hash, lang| "/#{lang}/free-translations-tibetan-buddhist-texts" }.merge(
      "en" => "/free-translations-tibetan-buddhist-texts",
      "nl" => "/nl/vertalingen-in-het-nederlands",
      "zh" => "/zh/translations-in-chinese"
    ).freeze

    # const: the site's two author-collection path segments (URL grammar), not a corpus count
    COLLECTIONS = %w[tibetan-masters indian-masters].freeze
    SCRIPTURE = "words-of-the-buddha"
    SLUG = "[a-z0-9][a-z0-9._-]*"

    # const: crawl politeness pause (the site's "reasonable network usage"), not a corpus claim
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze
    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :listings, :missing, :languages)

    # The URL path prefix of +lang+ ("" for en).
    def self.prefix(lang) = lang == "en" ? "" : "/#{lang}"

    # pages/<lang>/<path>.html for a site path relative to the language
    # ("tibetan-masters/mipham/acala-sadhana").
    def self.page_relpath(lang, path) = File.join(PAGES_DIR, lang, "#{path}.html")

    def self.sync!(dir:, attic_dir:, languages: LANGUAGES, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(dir: dir, attic_dir: attic_dir, languages: languages, base_url: base_url,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched, cached: fetch.cached,
                 records: fetch.records, listings: fetch.listings, missing: fetch.missing,
                 languages: languages)
    end

    def initialize(dir:, attic_dir:, languages: LANGUAGES, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      unknown = languages - LANGUAGES
      raise Error, "unknown Lotsawa House language(s): #{unknown.join(', ')}" unless unknown.empty?

      @dir = dir
      @attic_dir = attic_dir
      @languages = languages
      @base_url = base_url
      @http = http
      @delay = delay
      @progress = progress
      @texts = {}    # lang => sorted site paths
      @catalog = {}  # catalog relpath => body
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :missing

    def records = @texts.values.sum(&:size)
    def listings = @catalog.size

    # Phase 1 — the catalog walk; live tree untouched.
    def prepare!
      @languages.each { |lang| @texts[lang] = walk(lang) }
      @doomed = doomed_relpaths
    end

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    # Phase 2 — attic the vanished, land the catalog, crawl the text pages.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      @catalog.each { |rel, body| write!(rel, body) }
      crawl_texts!
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the catalog walk -------------------------------------------------------

    def walk(lang)
      pre = self.class.prefix(lang)
      explore = get_listing(lang, EXPLORE[lang], "index") or
        raise Error, "#{lang}: the explore page #{EXPLORE[lang]} is missing (404)"
      authors = author_paths(explore, pre)
      texts = text_paths(explore, pre)
      if authors.empty? && texts.empty?
        raise Error, "#{lang}: the explore page #{EXPLORE[lang]} lists no authors and no texts — " \
                     "a maintenance page or a reshaped site; nothing written"
      end

      scripture = get_listing(lang, "#{pre}/#{SCRIPTURE}/", SCRIPTURE)
      texts.merge(text_paths(scripture, pre)) if scripture
      authors.each_with_index do |author, index|
        if (index % 50).zero?
          @progress&.call("Lotsawa House #{lang} listing #{index + 1}/#{authors.size} (#{author})…\n")
        end
        listing = get_listing(lang, "#{pre}/#{author}/", author) or next
        texts.merge(text_paths(listing, pre))
      end
      texts.to_a.sort
    end

    # Author listing paths ("tibetan-masters/mipham") on a page.
    def author_paths(html, pre)
      html.scan(%r{href="#{Regexp.escape(pre)}/((?:#{COLLECTIONS.join('|')})/#{SLUG})/"}).flatten.uniq.sort
    end

    # Text paths on a page, relative to the language prefix.
    def text_paths(html, pre)
      pattern = %r{href="#{Regexp.escape(pre)}/((?:#{COLLECTIONS.join('|')})/#{SLUG}/#{SLUG}|#{SCRIPTURE}/#{SLUG})"}
      html.scan(pattern).flatten.to_set
    end

    # GET a listing page, held for complete! under catalog/<lang>/<name>.html;
    # nil (censused) on 404.
    def get_listing(lang, path, name)
      body = get_with_retry("#{@base_url}#{path}", missing_ok: true)
      if body.nil?
        @missing << "#{lang}:#{path}"
        return nil
      end
      @catalog[File.join(CATALOG_DIR, lang, "#{name}.html")] = body
      body
    end

    # -- the text crawl -----------------------------------------------------------

    def crawl_texts!
      total = records
      done = 0
      text_misses = 0
      @texts.each do |lang, paths|
        paths.each do |path|
          done += 1
          rel = self.class.page_relpath(lang, path)
          if File.file?(File.join(@dir, rel))
            @cached += 1
            next
          end

          @progress&.call("Lotsawa House page #{done}/#{total} (#{lang} #{path})…\n") if (done % 25).zero?
          body = get_with_retry("#{@base_url}#{self.class.prefix(lang)}/#{path}", missing_ok: true)
          if body.nil?
            @missing << "#{lang}:#{path}"
            text_misses += 1
            next
          end
          write!(rel, body)
          @fetched += 1
        end
      end
      cap = [(total * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if text_misses <= cap

      raise Error, "#{text_misses} of #{total} listed text pages 404 — a systemic miss, not holes: the " \
                   "URL scheme has moved upstream (first missing: #{@missing.first(3).join(', ')})"
    end

    def get_with_retry(url, missing_ok: false)
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

          raise Error, "HTTP 404 for #{url}"
        else
          raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    class RetriableFailure < StandardError; end
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

    def page_files
      @languages.flat_map do |lang|
        root = File.join(@dir, PAGES_DIR, lang)
        Dir.glob("**/*.html", base: root).map { |rel| File.join(PAGES_DIR, lang, rel) }
      end.sort
    end

    # Content pin over the in-scope text pages; the catalog pages stay out.
    def aggregate_sha
      lines = page_files.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601, "last_modified" => nil,
                "sha256" => @sha, "languages" => @languages,
                "records" => records, "per_language" => @texts.transform_values(&:size),
                "listings" => listings, "fetched" => @fetched, "cached" => @cached, "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention --------------------------------------------------------------

    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      keep = @texts.flat_map { |lang, paths| paths.map { |path| self.class.page_relpath(lang, path) } }.to_set
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
      pin = previous_sha || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      FileUtils.mkdir_p(@attic_dir)
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
