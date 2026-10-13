# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "normalize"
require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"
require_relative "adapters/bu_ajami_item_parser"

module Nabu
  # The polite walk over Boston University's NEH Ajami collection
  # (sites.bu.edu/nehajami; P124-1). The site is WordPress: its REST
  # listing (wp-json/wp/v2/pages, 111 pages at the 2026-10-13 census, two
  # listing pages at per_page=100, X-WP-TotalPages says how many) names
  # every page with its id, link, slug and "modified" stamp. The 80 item
  # pages are the links shaped
  #
  #   /nehajami/the-four-languages/<lang>/<lang>-manuscripts/<slug>/
  #
  # for lang ∈ fula, hausa, mandinka, wolof (20 each). Each item page is
  # held verbatim at items/<lang>/<slug>.html, and the ONE transcription
  # PDF it links (Nabu::Adapters::BuAjamiItemParser) at
  # files/<the path under /nehajami/files/>, NFC-named on disk (upstream
  # serves a few files under NFD names — the request carries upstream's
  # bytes, percent-encoded; the disk name is the NFC form). The
  # translations and manuscript-image PDFs are NOT fetched (their URLs ride
  # document metadata).
  #
  # == Incremental posture
  #
  # The listing is read on every sync. An item page is re-fetched only
  # when its listed "modified" stamp differs from the held one (state file
  # .bu-ajami-fetch.json) or the file is absent; a transcription PDF only
  # when absent (a changed upstream file name is a new path). Nothing is
  # ever deleted: an item that leaves the listing keeps its held files and
  # stays in the library (no mass-deletion breaker is needed — there is
  # no deletion).
  #
  # == Failures
  #
  # The site answers bursts with 503 (censused 2026-10-13: 16 of 80 PDF
  # GETs at 0.7 s pacing; every one landed on a slower retry), so each GET
  # retries up to ATTEMPTS times with a growing pause. An item still
  # unreachable is reported and retried next sync; the sync proceeds with
  # what landed. A listing that fails or names no item page aborts (Error)
  # before anything is written.
  class BuAjamiFetch
    class Error < Nabu::Error; end

    BASE = "https://sites.bu.edu"
    LIST_PATH = "/nehajami/wp-json/wp/v2/pages"
    FILES_PREFIX = "/nehajami/files/"
    ITEMS_DIR = "items"
    FILES_DIR = "files"
    STATE_FILE = ".bu-ajami-fetch.json"
    # census: the four language sections of the site (2026-10-13 — 20
    # items each, 80 in all); a new section is a reshaped site.
    LANGUAGES = %w[fula hausa mandinka wolof].freeze
    ITEM_LINK = %r{\Ahttps://sites\.bu\.edu/nehajami/the-four-languages/(fula|hausa|mandinka|wolof)/
                   \1-manuscripts/([a-z0-9-]+)/\z}x

    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    ATTEMPTS = 5
    # const: listing pagination guard, not a corpus claim
    MAX_LIST_PAGES = 20

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :listed, :pages_fetched, :pdfs_fetched, :held, :failed)

    def self.list_url(page)
      "#{BASE}#{LIST_PATH}?per_page=100&page=#{page}&_fields=id,link,slug,modified"
    end

    # The request URL for an upstream href: every byte outside the
    # unreserved set and "/" percent-encoded (NFD names travel as their
    # own bytes).
    def self.request_url(href)
      "#{BASE}#{href.b.gsub(%r{[^A-Za-z0-9._~/-]}n) { |byte| format('%%%02X', byte.ord) }}"
    end

    # Where a transcription href lands on disk (NFC name). Raises Error on
    # an href outside /nehajami/files/ or carrying a dot segment.
    def self.local_pdf_path(dir, href)
      rest = href.to_s.delete_prefix(FILES_PREFIX)
      if rest == href.to_s || rest.split("/").any? { |seg| seg.empty? || seg.start_with?(".") }
        raise Error, "transcription href outside #{FILES_PREFIX}: #{href.inspect}"
      end

      File.join(dir, FILES_DIR, Normalize.nfc(rest))
    end

    def self.item_page_path(dir, lang, slug) = File.join(dir, ITEMS_DIR, lang, "#{slug}.html")

    def self.sync!(dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      new(dir: dir, http: http, delay: delay, progress: progress).sync!
    end

    def initialize(dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      @dir = dir
      @http = http
      @delay = delay
      @progress = progress
    end

    def sync!
      items = listed_items
      FileUtils.mkdir_p(@dir)
      state = read_state
      counts = { pages: 0, pdfs: 0 }
      failed = []
      items.each do |item|
        sync_item(item, state, counts)
      rescue Error, Nabu::ParseError => e
        failed << item[:key]
        @progress&.call("#{item[:key]}: unreachable this sync (#{e.message})\n")
      end
      write_state(state)
      held = held_items(items)
      raise Error, "no item held after the walk (#{failed.first(3).join(', ')})" if held.zero?

      Result.new(sha: tree_sha, listed: items.size, pages_fetched: counts[:pages], pdfs_fetched: counts[:pdfs],
                 held: held, failed: failed)
    end

    private

    # Every item row of the REST listing, in listing order.
    def listed_items
      rows = []
      total = 1
      page = 1
      while page <= total
        response = get(self.class.list_url(page))
        total = Integer(response.headers["x-wp-totalpages"] || 1, exception: false) || 1
        raise Error, "listing reports #{total} pages (over the #{MAX_LIST_PAGES} guard)" if total > MAX_LIST_PAGES

        batch = JSON.parse(response.body.to_s)
        raise Error, "listing page #{page} is not a JSON array" unless batch.is_a?(Array)

        rows.concat(batch)
        page += 1
      end
      items = rows.filter_map { |row| item_row(row) }
      raise Error, "the listing names no manuscript item page (#{rows.size} rows) — site reshaped?" if items.empty?

      items
    rescue JSON::ParserError => e
      raise Error, "listing is not JSON: #{e.message}"
    end

    def item_row(row)
      return nil unless row.is_a?(Hash)

      match = ITEM_LINK.match(row["link"].to_s) or return nil
      { key: "#{match[1]}/#{match[2]}", lang: match[1], slug: match[2], link: row["link"],
        modified: row["modified"].to_s }
    end

    def sync_item(item, state, counts)
      path = self.class.item_page_path(@dir, item[:lang], item[:slug])
      held = state[item[:key]] || {}
      if !File.file?(path) || held["modified"] != item[:modified]
        write_atomically(path, get(item[:link]).body.to_s.b)
        counts[:pages] += 1
      end
      href = Adapters::BuAjamiItemParser.parse_file(path).transcription_href
      pdf = self.class.local_pdf_path(@dir, href)
      unless File.file?(pdf)
        write_atomically(pdf, get(self.class.request_url(href)).body.to_s.b)
        counts[:pdfs] += 1
      end
      state[item[:key]] = { "modified" => item[:modified], "transcription" => href }
    end

    def get(url)
      attempt = 0
      begin
        attempt += 1
        sleep(@delay * attempt * attempt) if @delay.positive?
        @progress&.call("GET #{url}\n") if attempt == 1
        response, = RedirectFollow.get(url, http: @http, error: Error, headers: { "User-Agent" => USER_AGENT })
        response
      rescue Error
        raise if attempt >= ATTEMPTS

        retry
      end
    end

    def write_atomically(path, body)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite("#{path}.part", body)
      File.rename("#{path}.part", path)
    end

    def state_path = File.join(@dir, STATE_FILE)

    def read_state
      return {} unless File.file?(state_path)

      data = JSON.parse(File.read(state_path))
      data.is_a?(Hash) ? (data["items"] || {}) : {}
    rescue JSON::ParserError
      {}
    end

    def write_state(state)
      write_atomically(state_path, JSON.pretty_generate({ "items" => state.sort.to_h }))
    end

    def held_items(items)
      items.count do |item|
        path = self.class.item_page_path(@dir, item[:lang], item[:slug])
        next false unless File.file?(path)

        href = Adapters::BuAjamiItemParser.parse_file(path).transcription_href
        File.file?(self.class.local_pdf_path(@dir, href))
      rescue Error, Nabu::ParseError
        false
      end
    end

    # The tree's identity: sha256 over every held item page and PDF
    # (relative path + body sha), in path order. The state file is
    # bookkeeping, not content — excluded.
    def tree_sha
      files = Dir.glob(File.join(@dir, "{#{ITEMS_DIR},#{FILES_DIR}}", "**", "*")).select { |p| File.file?(p) }
      rows = files.reject { |p| p.end_with?(".part") }.map do |p|
        "#{p.delete_prefix("#{@dir}/")}\t#{Digest::SHA256.file(p).hexdigest}"
      end
      Digest::SHA256.hexdigest(rows.sort.join("\n"))
    end
  end
end
