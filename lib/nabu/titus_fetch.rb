# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"
require "nokogiri"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"

module Nabu
  # Non-destructive sequential page-walk over a TITUS frame-based text edition
  # (P43-2, the TITUS Avestan Corpus) — the ZipFetch/FileFetch/WikiFetch mirror
  # for an upstream that is neither a git repo nor a zip nor an API, but a chain
  # of static HTML pages (avest001.htm → avest002.htm → …) linked by a "Next
  # part" arrow. No manifest lists the pages; the walk itself IS the map.
  #
  # == The walk
  #
  #   From the frameset entry (avest.htm) follow its text frame to the first
  #   page, then follow each page's "Next part" link until there is none. A page
  #   already on disk is read from disk (its Next-part link still steers the
  #   walk) and NOT re-fetched — the edition is a frozen "preliminary" one and
  #   the crawl is resumable at the page grain. A missing page is GET-ted
  #   (polite: ≥2s between HTTP requests, a nabu User-Agent — TITUS is a guest's
  #   host) and held in memory until complete!.
  #
  # == The retention contract (ZipFetch's phases, verbatim)
  #
  #   prepare!   walk the site; doomed = local avestNNN.htm files the walk no
  #              longer reaches. The live tree is untouched.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with the
  #              tree byte-unchanged (no writes, no attic).
  #   complete!  attic the doomed (GitFetch manifest shape, first copy wins,
  #              sha = the page-set pin they vanished at), delete them, write the
  #              newly-fetched pages (tmp+rename), write the state file.
  #
  # The fetch pin is the sha256 of the reachable page set (name → body sha256,
  # sorted) — a stable identity for "what the edition currently is."
  class TitusFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".titus-fetch.json"

    # Seconds between HTTP requests (sequential, polite — the grant is a guest's).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 2.0

    # A defensive ceiling so a mislinked "Next part" cycle can never crawl
    # forever. The Avesta is a few hundred pages; 5000 is unreachably generous.
    # const: loop breaker, not a corpus claim
    MAX_PAGES = 5000

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :fetched, :cached, :page_count)

    # One-shot choreography. +guard+ receives the absolute doomed paths between
    # prepare! and complete!.
    def self.sync!(entry_url:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(entry_url: entry_url, dir: dir, attic_dir: attic_dir,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, fetched: fetch.fetched,
                 cached: fetch.cached, page_count: fetch.page_count)
    end

    def initialize(entry_url:, dir:, attic_dir:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      @entry_url = entry_url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @delay = delay
      @progress = progress
      @pages = {} # filename => { body:, sha:, on_disk: }
      @doomed = []
      @atticked = []
      @requests = 0
    end

    attr_reader :atticked, :sha

    def page_count = @pages.size
    def fetched = @pages.count { |_name, page| !page[:on_disk] }
    def cached = @pages.count { |_name, page| page[:on_disk] }

    # Phase 1 — walk the chain; live tree untouched.
    def prepare!
      url = first_page_url
      seen = {}
      while url && @pages.size < MAX_PAGES
        name = page_filename(url)
        break if seen[name] # a Next-part cycle — stop cleanly

        seen[name] = true
        html = page_html(name, url)
        sha = Digest::SHA256.hexdigest(html.b)
        @pages[name] = { body: html, sha: sha, on_disk: File.file?(page_path(name)) }
        url = next_part_url(html, url)
      end
      raise Error, "no text pages reached from #{@entry_url}" if @pages.empty?

      @sha = Digest::SHA256.hexdigest(JSON.generate(@pages.sort.to_h { |name, p| [name, p[:sha]] }))
      @doomed = doomed_relpaths
    end

    # Absolute live-tree page files the walk no longer reaches.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the vanished, then write every fetched page.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      FileUtils.mkdir_p(@dir)
      @pages.each do |name, page|
        next if page[:on_disk] # unchanged cached page — leave it

        target = page_path(name)
        File.binwrite("#{target}.tmp", page[:body].b)
        File.rename("#{target}.tmp", target)
      end
      write_state!
    end

    private

    # The first text page: the frameset's text frame, else the first <frame>.
    def first_page_url
      html = get(@entry_url)
      doc = Nokogiri::HTML(html)
      frame = doc.at_xpath('//frame[@name="etatext"]') || doc.at_xpath("//frame[@src]")
      raise Error, "no text frame in frameset #{@entry_url}" unless frame&.[]("src")

      URI.join(@entry_url, frame["src"]).to_s
    end

    # A page's html — from disk when present (no re-fetch), else GET.
    def page_html(name, url)
      path = page_path(name)
      return File.read(path, encoding: "UTF-8") if File.file?(path)

      get(url)
    end

    # The absolute URL of the "Next part" arrow, or nil at the end of the chain.
    def next_part_url(html, base_url)
      doc = Nokogiri::HTML(html)
      img = doc.at_xpath('//img[@alt="Next part"]')
      anchor = img&.ancestors("a")&.first
      href = anchor && anchor["href"]
      href.nil? ? nil : URI.join(base_url, href).to_s
    end

    def page_filename(url)
      File.basename(URI.parse(url).path)
    end

    def page_path(name)
      File.join(@dir, name)
    end

    # Live avestNNN.htm files the walk did not reach (renumbered/withdrawn pages).
    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      Dir.children(@dir)
         .select { |name| name.match?(Nabu::Adapters::TitusAvestan::PAGE_RE) && !@pages.key?(name) }
    end

    # First copy wins; the manifest records the page-set pin each file vanished
    # at, in GitFetch's exact format so the adapter base class rediscovers the
    # attic generically.
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

    def write_state!
      state = { "last_modified" => nil, "sha256" => @sha, "url" => @entry_url,
                "pages" => @pages.size }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # One throttled, UA-identified GET (redirects followed, the ZipFetch
    # doctrine). Returns the body as a UTF-8 String.
    def get(url)
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
      @progress&.call("Fetching #{url}…\n")
      response, = RedirectFollow.get(url, http: @http, error: Error,
                                          headers: { "User-Agent" => USER_AGENT })
      response.body.to_s.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
