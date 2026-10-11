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
  # The WP-JSON crawl for eLektire (lektire.skole.hr — CARNET's school
  # reading portal, books produced by Bulaja naklada; P117-2, Q104;
  # architecture §8). A crawl sibling of ScriptaBulgaricaFetch, deliberately
  # mirrored rather than extracted.
  #
  # The portal's reader pages ask for a login, but the WordPress REST API
  # is public and so are the uploaded book files: /wp-json/wp/v2/djela
  # enumerates the works (378 censused 2026-10-11) with their taxonomy
  # term ids, the taxonomy endpoints name the terms, and
  # /wp-json/wp/v2/media?parent=<work id> lists each work's attachments —
  # the EPUB (and a PDF twin, not fetched) under /wp-content/uploads/.
  #
  # Layout (canonical/elektire/):
  #   index/djela-<page>.json        the works listing pages, as served
  #   index/<taxonomy>-<page>.json   the term listings (six taxonomies)
  #   index/media-<work id>.json     each fetched work's attachment list
  #   epub/<work slug>.epub          the book, bytes as served
  #
  # Scope: only works in the Croatian-literature term
  # (knjizevnost = hrvatska-knjizevnost) are taken further than the
  # listing — the canon is the source; translations of foreign literature
  # are out by rule (their text is a translator's, and its dating and lect
  # would mislead). Per-work rights are judged at discovery, not here: the
  # fetch is license-blind inside the cone (the aozora shape), so a work's
  # admission can change with its impressum without a re-crawl.
  #
  # A work whose attachments hold several EPUBs keeps the most recently
  # modified one (re-uploads are corrections). Resume at the file grain:
  # an EPUB already on disk with the same URL + modified stamp is not
  # re-downloaded. Retention via attic + the caller's mass-deletion
  # breaker; the fetch pin is the aggregate sha over the EPUB files.
  class ElektireFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".elektire-fetch.json"
    INDEX_DIR = "index"
    EPUB_DIR = "epub"
    API = "/wp-json/wp/v2"

    # The listing fields kept (WordPress _fields) — identity, title and the
    # taxonomy term ids the adapter mines.
    # const: the portal's REST field names, not a corpus claim
    WORK_FIELDS = %w[id slug link title modified stoljece_nastanka autor knjizevna_vrsta knjizevni_zanr
                     knjizevnost epohe lektira].freeze
    # const: the portal's taxonomy endpoints, not a corpus claim
    TAXONOMIES = %w[knjizevnost stoljece_nastanka knjizevna_vrsta knjizevni_zanr epohe lektira].freeze
    CANON_TAXONOMY = "knjizevnost"
    CANON_TERM = "hrvatska-knjizevnost"
    EPUB_RECORD = %r{\Aepub/([a-z0-9-]+)\.epub\z}

    # const: crawl politeness pause, not a corpus claim (~240 API calls +
    # ~230 downloads ≈ 8 minutes at 1 s)
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze
    # const: pagination runaway guard — the works listing is 4 pages today
    MAX_PAGES = 50

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; public-domain works only; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :works, :manifest_count, :without_epub)

    def self.sync!(base_url:, dir:, attic_dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil,
                   guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, http: http, delay: delay,
                  progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched, cached: fetch.cached,
                 works: fetch.works, manifest_count: fetch.manifest_count, without_epub: fetch.without_epub)
    end

    def self.epub_relpath(slug) = "#{EPUB_DIR}/#{slug}.epub"

    def initialize(base_url:, dir:, attic_dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @pages = {}
      @epubs = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @without_epub = []
    end

    attr_reader :atticked, :sha, :fetched, :cached, :manifest_count, :without_epub

    def works = @epubs.size

    # Phase 1 — the listings and the per-work attachment lists; the live
    # tree is untouched.
    def prepare!
      works = paged("djela", "_fields=#{WORK_FIELDS.join(',')}")
      raise Error, "the works listing is empty — a maintenance page or a reshaped API" if works.empty?

      terms = TAXONOMIES.to_h { |tax| [tax, paged(tax, "_fields=id,slug,name")] }
      canon = terms.fetch(CANON_TAXONOMY).find { |t| t["slug"] == CANON_TERM } or
        raise Error, "the #{CANON_TAXONOMY} taxonomy has no #{CANON_TERM} term — the vocabulary changed"

      cone = works.select { |w| Array(w[CANON_TAXONOMY]).include?(canon["id"]) }
      @manifest_count = cone.size
      cone.each_with_index do |work, index|
        @progress&.call("eLektire attachments #{index + 1}/#{cone.size}…\n") if (index % 25).zero?
        body = get_with_retry("#{@base_url}#{API}/media?parent=#{work['id']}&per_page=100" \
                              "&_fields=id,source_url,modified,mime_type", id: work["slug"])
        @pages["#{INDEX_DIR}/media-#{work['id']}.json"] = body
        epub = pick_epub(parse_json(body, work["slug"]))
        if epub
          @epubs[work["slug"]] = { "url" => epub["source_url"], "modified" => epub["modified"] }
        else
          @without_epub << work["slug"]
        end
      end
      @doomed = doomed_relpaths
    end

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    # Phase 2 — attic the vanished, land the listings, download the books.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      stale_index_pages.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      @pages.each { |rel, body| write!(rel, body) }
      download_epubs!
      @sha = aggregate_sha
      write_state!
    end

    private

    # Every page of a WordPress collection, by its X-WP-TotalPages header;
    # each page body lands as index/<name>-<n>.json.
    def paged(name, query)
      items = []
      page = 1
      loop do
        raise Error, "#{name}: more than #{MAX_PAGES} pages — the API shape changed" if page > MAX_PAGES

        response = request("#{@base_url}#{API}/#{name}?per_page=100&page=#{page}&#{query}", id: "#{name} p#{page}")
        body = response.body.to_s
        @pages["#{INDEX_DIR}/#{name}-#{page}.json"] = body
        items.concat(parse_json(body, name))
        total = response.headers["x-wp-totalpages"].to_i
        break if page >= total

        page += 1
      end
      items
    end

    def parse_json(body, id)
      data = JSON.parse(body)
      raise Error, "#{id}: expected a JSON array, got #{data.class}" unless data.is_a?(Array)

      data
    rescue JSON::ParserError => e
      raise Error, "#{id}: unparseable JSON (#{e.message})"
    end

    def pick_epub(media)
      media.select { |m| m["source_url"].to_s.end_with?(".epub") }.max_by { |m| m["modified"].to_s }
    end

    def download_epubs!
      previous = state.fetch("epubs", {})
      @epubs.each_with_index do |(slug, meta), index|
        rel = self.class.epub_relpath(slug)
        if File.file?(File.join(@dir, rel)) && previous[slug] == meta
          @cached += 1
          next
        end

        @progress&.call("eLektire book #{index + 1}/#{@epubs.size} (#{slug})…\n") if (index % 10).zero?
        body = get_with_retry(meta["url"], id: slug)
        magic = body.b[0, 4]
        raise Error, "#{slug}: #{meta['url']} is not a zip (EPUB) — got #{magic.inspect}" unless magic.start_with?("PK")

        write!(rel, body)
        @fetched += 1
      end
    end

    def get_with_retry(url, id:) = request(url, id: id).body.to_s

    def request(url, id:)
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

        response
      rescue RetriableFailure => e
        raise Error, "#{id}: #{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

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
      lines = epub_relpaths_on_disk.sort.map do |rel|
        "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def write_state!
      payload = { "url" => @base_url, "fetched_at" => Time.now.utc.iso8601, "last_modified" => nil,
                  "sha256" => @sha, "manifest_count" => @manifest_count, "works" => @epubs.size,
                  "fetched" => @fetched, "cached" => @cached, "without_epub" => @without_epub,
                  "epubs" => @epubs }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(payload))
    end

    def epub_relpaths_on_disk
      dir = File.join(@dir, EPUB_DIR)
      return [] unless Dir.exist?(dir)

      Dir.children(dir).sort.map { |name| "#{EPUB_DIR}/#{name}" }.grep(EPUB_RECORD)
    end

    def doomed_relpaths
      keep = @epubs.keys.to_set { |slug| self.class.epub_relpath(slug) }
      epub_relpaths_on_disk.reject { |rel| keep.include?(rel) }
    end

    # Listing pages from an earlier, longer crawl (a page count that
    # shrank, a work that left the cone) — rewritten listings only.
    def stale_index_pages
      dir = File.join(@dir, INDEX_DIR)
      return [] unless Dir.exist?(dir)

      Dir.children(dir).sort.map { |name| "#{INDEX_DIR}/#{name}" }.reject { |rel| @pages.key?(rel) }
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
      pin = state["sha256"] || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
