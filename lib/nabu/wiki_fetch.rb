# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"

module Nabu
  # Non-destructive MediaWiki api.php category crawl — the wiki-family
  # fetch path (P29-3; the ZipFetch/FileFetch mirror for the Vienna wiki
  # pair, lexlep.univie.ac.at / tir.univie.ac.at). No git repo, no zip:
  # upstream is a living wiki whose entity pages hang off categories
  # (Inscription, Object, Site, Word), so the crawl is two stages —
  #
  #   Stage 1 (the map): every configured category's members via
  #   generator=categorymembers + prop=info (500 per request, gcmcontinue
  #   pagination) — title, pageid, lastrevid per member. Written to
  #   map/<Category>.json; the sha256 of the whole member map (titles →
  #   revids, sorted) is the fetch pin.
  #
  #   Stage 2 (the pages): members whose local page file is missing OR
  #   whose stored revid differs from upstream's lastrevid are fetched in
  #   batches of 50 titles via prop=revisions&rvprop=content|ids|timestamp
  #   &rvslots=main — ONE request per 50 pages, the API's own batch shape,
  #   far kinder to the host than per-page GETs — and split into per-page
  #   envelope files pages/<Category>/<encoded title>.json holding
  #   {title, pageid, ns, revid, timestamp, wikitext}: the wikitext
  #   byte-verbatim as api.php served it, the envelope our own stable
  #   on-disk shape (titles carry "·", "/", "?" — the encoded filename is
  #   percent-escaped UTF-8, deterministic and collision-free).
  #
  # == The retention contract (ZipFetch's phases, verbatim)
  #
  #   prepare!   fetch the member map; doomed = local page files of the
  #              crawled categories whose title upstream no longer lists.
  #              The live tree is untouched.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic the doomed files (GitFetch manifest shape, first
  #              copy wins, sha = the member-map pin they vanished at),
  #              delete them, write the map files, crawl changed/missing
  #              pages (tmp+rename writes — a page crawl only ever adds or
  #              replaces), write the state file.
  #
  # Change detection is REVID-driven, not Last-Modified: api.php serves no
  # useful Last-Modified, but every page fetch carries its revid and the
  # member map carries upstream's lastrevid — an unchanged page is never
  # re-downloaded, an edited one always is. Resumable at the page grain: a
  # killed crawl leaves the fetched files valid; the next run fetches only
  # what is still missing or stale.
  #
  # Requests are throttled (+delay+ seconds between HTTP requests, riig's
  # polite-crawl precedent) and carry a User-Agent identifying nabu — the
  # wikis are small FWF-funded university projects; we are guests.
  class WikiFetch
    # HTTP/API-level failure. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".wiki-fetch.json"
    MAP_DIRNAME = "map"
    PAGES_DIRNAME = "pages"

    # api.php limits: 500 category members per list request (the anonymous
    # cap), 50 titles per revisions-content request.
    MEMBER_LIMIT = 500
    CONTENT_BATCH = 50

    # Seconds between HTTP requests (sequential, polite).
    DELAY = 1.0

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :member_count)

    # One-shot choreography for a single-wiki source. +guard+ receives the
    # absolute doomed paths between prepare! and complete!.
    def self.sync!(api_url:, categories:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(api_url: api_url, categories: categories, dir: dir, attic_dir: attic_dir,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked,
                 fetched: fetch.fetched, cached: fetch.cached, member_count: fetch.member_count)
    end

    def initialize(api_url:, categories:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      @api_url = api_url
      @categories = categories
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @members = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
    end

    attr_reader :sha, :atticked, :fetched, :cached

    def member_count
      @members.values.sum(&:size)
    end

    # Stage 1 — the member map; live tree untouched.
    def prepare!
      @members = @categories.to_h { |category| [category, category_members(category)] }
      @sha = Digest::SHA256.hexdigest(JSON.generate(member_pin))
      @doomed = doomed_relpaths
    end

    # Absolute live-tree paths of page files upstream no longer lists.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Stage 2 — attic + delete the vanished, then write maps and crawl.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_maps!
      @members.each { |category, members| crawl_category!(category, members) }
      write_state!
    end

    # The deterministic filename for a page title: percent-escaped UTF-8
    # over a conservative safe set — unique, stable, filesystem-clean
    # ("Bozen / Bolzano" → "Bozen%20%2F%20Bolzano").
    def self.encode_title(title)
      title.gsub(/[^0-9A-Za-z._-]/) do |char|
        char.bytes.map { |byte| format("%%%02X", byte) }.join
      end
    end

    # The inverse — an encoded page filename back to its title.
    def self.decode_title(encoded)
      encoded.gsub(/(?:%[0-9A-Fa-f]{2})+/) do |run|
        [run.delete("%")].pack("H*").force_encoding(Encoding::UTF_8)
      end
    end

    private

    # -- stage 1: members ------------------------------------------------------

    # All members of Category:<category> (pagination followed): title →
    # { "pageid", "revid" }.
    def category_members(category)
      members = {}
      continue = {}
      loop do
        response = get_json(member_params(category).merge(continue))
        pages = response.dig("query", "pages") || {}
        pages.each_value do |page|
          members[page.fetch("title")] = { "pageid" => page["pageid"], "revid" => page["lastrevid"] }
        end
        continue = response["continue"] or break
      end
      members
    end

    def member_params(category)
      { "action" => "query", "format" => "json", "generator" => "categorymembers",
        "gcmtitle" => "Category:#{category}", "gcmlimit" => MEMBER_LIMIT.to_s, "prop" => "info" }
    end

    # The pin content: category → sorted title → revid.
    def member_pin
      @members.sort.to_h do |category, members|
        [category, members.keys.sort.to_h { |title| [title, members[title]["revid"]] }]
      end
    end

    def doomed_relpaths
      @members.flat_map do |category, members|
        expected = members.keys.to_set { |title| "#{self.class.encode_title(title)}.json" }
        pages_dir = File.join(@dir, PAGES_DIRNAME, category)
        next [] unless Dir.exist?(pages_dir)

        Dir.children(pages_dir).select { |name| name.end_with?(".json") && !expected.include?(name) }
                               .map do |name|
          File.join(PAGES_DIRNAME, category,
                    name)
        end
      end
    end

    # -- stage 2: pages --------------------------------------------------------

    def crawl_category!(category, members)
      stale = members.reject { |title, info| stored_revid(category, title) == info["revid"] }
      @cached += members.size - stale.size
      return if stale.empty?

      @progress&.call("Fetching #{stale.size} #{category} page(s) (#{members.size - stale.size} cached)…")
      stale.keys.each_slice(CONTENT_BATCH) { |titles| crawl_batch!(category, titles) }
    end

    def crawl_batch!(category, titles)
      response = get_json(
        "action" => "query", "format" => "json", "prop" => "revisions",
        "rvprop" => "content|ids|timestamp", "rvslots" => "main", "titles" => titles.join("|")
      )
      pages = response.dig("query", "pages") || {}
      pages.each_value do |page|
        revision = page.dig("revisions", 0) or next
        write_page!(category, page, revision)
        @fetched += 1
      end
    end

    def write_page!(category, page, revision)
      envelope = {
        "title" => page.fetch("title"), "pageid" => page["pageid"], "ns" => page["ns"] || 0,
        "revid" => revision["revid"], "timestamp" => revision["timestamp"],
        "wikitext" => revision.dig("slots", "main", "*").to_s
      }
      dir = File.join(@dir, PAGES_DIRNAME, category)
      FileUtils.mkdir_p(dir)
      target = File.join(dir, "#{self.class.encode_title(envelope['title'])}.json")
      File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
      File.rename("#{target}.tmp", target)
    end

    def stored_revid(category, title)
      path = File.join(@dir, PAGES_DIRNAME, category, "#{self.class.encode_title(title)}.json")
      return nil unless File.file?(path)

      JSON.parse(File.read(path))["revid"]
    rescue JSON::ParserError
      nil # a corrupt page file is refetched, never trusted
    end

    # -- bookkeeping -----------------------------------------------------------

    def write_maps!
      @members.each do |category, members|
        rows = members.sort.map do |title, info|
          { "title" => title, "pageid" => info["pageid"], "revid" => info["revid"] }
        end
        dir = File.join(@dir, MAP_DIRNAME)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{category}.json"),
                   "#{JSON.pretty_generate({ 'category' => category, 'members' => rows })}\n")
      end
    end

    def write_state!
      FileUtils.mkdir_p(@dir)
      state = { "last_modified" => nil, "sha256" => @sha, "url" => @api_url }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # First copy wins; the manifest records the member-map pin the page
    # vanished at (GitFetch's exact format, so the adapter base class's
    # attic rediscovery reads it generically).
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
      record_manifest! unless @atticked.empty?
    end

    def record_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      @atticked.each { |rel| manifest[rel] ||= @sha } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end

    # -- HTTP ------------------------------------------------------------------

    # One throttled, UA-identified api.php GET, JSON-parsed; an API-level
    # error payload is as fatal as a transport one.
    def get_json(params)
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
      url = "#{@api_url}?#{URI.encode_www_form(params)}"
      response, = RedirectFollow.get(url, http: @http, error: Error,
                                          headers: { "User-Agent" => USER_AGENT })
      payload = JSON.parse(response.body.to_s)
      raise Error, "api.php error for #{@api_url}: #{payload['error']}" if payload.key?("error")

      payload
    rescue JSON::ParserError => e
      raise Error, "api.php returned unparseable JSON for #{@api_url}: #{e.message}"
    end
  end
end
