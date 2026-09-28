# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Polite pager crawl for Scripta Bulgarica (P107-8 — Q100; architecture
  # §8): the «Писмени документи» listing at /bg/manuscript?page=0..N
  # enumerates ~125 source-text pages at /bg/sources/<slug>. The FOURTH
  # HTML-crawl sibling (OtdoFetch / ElephantineFetch / CantigasFetch) —
  # deliberately mirrored, not extracted; the extraction stays its own
  # future packet, never smuggled in here.
  #
  # THE SNAPSHOT IS THE POINT (survey 2026-09-28): the upstream is a
  # Drupal 7 on PHP 5.5 serving plain HTTP only — one outage from
  # oblivion. The first fetch is the insurance copy; the mirror layout is
  #   manuscript-<page>.html    pager index sidecars (metadata rows)
  #   sources/<slug>.html       one file per source text (the records)
  #
  # Manifest = the pager walk: page 0, then ?page=N while the current
  # page lists any /bg/sources/ link (an empty page ends the walk; page 0
  # empty aborts loudly — reshape defense). Resume at the file grain (a
  # record already on disk is not re-fetched); retention via attic +
  # the caller's mass-deletion breaker; the fetch pin is the aggregate
  # sha over the record files (index sidecars stay out — live-rendered).
  class ScriptaBulgaricaFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".scripta-bulgarica-fetch.json"

    RECORD_DIR = "sources"
    RECORD_FILENAME = %r{\Asources/([a-z0-9-]+)\.html\z}
    INDEX_FILENAME = /\Amanuscript-(\d+)\.html\z/

    # const: crawl politeness pause, not a corpus claim (an academic
    # host on ancient PHP — be gentle; ~140 requests ≈ 3 minutes)
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze
    # const: pager runaway guard — the site shows 13 pages today; 100
    # means the pager markup changed shape, abort loudly
    MAX_PAGES = 100

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; fetching under the site's " \
                 "stated CC BY-NC-SA 2.0 terms; +https://github.com/arvicco/nabu; " \
                 "contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :records, :manifest_count, :missing)

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.05
    MISSING_CAP_FLOOR = 5

    def self.index_url(base_url, page)
      page.zero? ? "#{base_url}/bg/manuscript" : "#{base_url}/bg/manuscript?page=#{page}"
    end

    def self.record_url(base_url, slug)
      "#{base_url}/bg/sources/#{slug}"
    end

    def self.record_relpath(slug)
      "#{RECORD_DIR}/#{slug}.html"
    end

    def self.record?(relpath)
      RECORD_FILENAME.match?(relpath)
    end

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
      @index_bodies = []
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count, :missing

    def records = @slugs.size

    # Phase 1 — the pager walk only; live tree untouched.
    def prepare!
      page = 0
      loop do
        raise Error, "pager reached #{MAX_PAGES} pages — the listing markup changed shape" if page >= MAX_PAGES

        @progress&.call("Scripta Bulgarica listing page #{page}…\n")
        body = get_with_retry(self.class.index_url(@base_url, page), id: "page=#{page}")
        slugs = harvest_slugs(body)
        break if slugs.empty? && page.positive?
        if slugs.empty?
          raise Error, "the first listing page names no /bg/sources/ links — a maintenance page " \
                       "or a reshaped listing; abort before any write"
        end

        @index_bodies << body
        @slugs.concat(slugs)
        page += 1
      end
      @slugs = @slugs.uniq.sort
      @manifest_count = @slugs.size
      @doomed = doomed_relpaths
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, land sidecars, crawl missing records.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(File.join(@dir, RECORD_DIR))
      @index_bodies.each_with_index { |body, page| write!("manuscript-#{page}.html", body) }
      crawl_records!
      @sha = aggregate_sha
      write_state!
    end

    private

    def harvest_slugs(body)
      body.b.scan(%r{href="/bg/sources/([a-z0-9-]+)"}n)
          .flatten.map { |slug| slug.force_encoding(Encoding::UTF_8) }.uniq
    end

    def crawl_records!
      @slugs.each_with_index do |slug, index|
        rel = self.class.record_relpath(slug)
        if File.file?(File.join(@dir, rel))
          @cached += 1
          next
        end

        @progress&.call("Scripta Bulgarica text #{index + 1}/#{@slugs.size} (#{slug})…\n") if (index % 10).zero?
        body = get_with_retry(self.class.record_url(@base_url, slug), id: slug, missing_ok: true)
        if body.nil?
          @missing << slug
          @progress&.call("Scripta Bulgarica #{slug}: 404 (listed — censused, crawl continues)\n")
          next
        end
        write!(rel, body)
        @fetched += 1
      end
      cap = [(@slugs.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      return if @missing.size <= cap

      raise Error, "#{@missing.size} of #{@slugs.size} listed texts 404 — a systemic miss: the " \
                   "URL scheme moved upstream (first missing: #{@missing.first(3).join(', ')})"
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

          raise Error, "HTTP 404 for #{url} — the listing promises #{id} but the page is missing"
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

    def write!(rel, body)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    def aggregate_sha
      rels = record_relpaths_on_disk
      lines = rels.sort.map do |rel|
        "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}"
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

    def record_relpaths_on_disk
      dir = File.join(@dir, RECORD_DIR)
      return [] unless Dir.exist?(dir)

      Dir.children(dir).sort.map { |name| "#{RECORD_DIR}/#{name}" }
         .select { |rel| self.class.record?(rel) }
    end

    def doomed_relpaths
      keep = @slugs.to_set { |slug| self.class.record_relpath(slug) }
      record_relpaths_on_disk.reject { |rel| keep.include?(rel) }
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
