# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "version"

module Nabu
  # Non-destructive fetch of a CENSUSED page list from the Izbornyk static
  # site (P117, 02-sources row 252) — litopys.org.ua with its own mirror
  # izbornyk.org.ua. The TitusFetch mirror for an upstream whose page set is
  # not discoverable by a walk but by EDITION TRIAGE: the adapter hands in
  # the exact relative paths it admitted (the site's own directory layout,
  # "ipatlet/ipat01.htm"), and this class GETs each one.
  #
  # == Plain HTTP, honestly
  #
  # The site's HTTPS endpoint presents a certificate whose subject names do
  # not match litopys.org.ua (curl: "no alternative certificate subject name
  # matches target host name", verified 2026-10-11); izbornyk.org.ua's HTTPS
  # 301s back to plain http. Both hosts serve the site over PLAIN HTTP as
  # their primary address (every in-site link is http://). So the fetch
  # speaks http:// by design — it never disables certificate verification;
  # there is simply no TLS layer to verify. Integrity rides the per-page
  # sha256 pins in the state file instead.
  #
  # == The mirror fallback
  #
  # Each page is GET-ted from the primary host; a transport error or a
  # non-200 falls back to the mirror (izbornyk.org.ua — the site's own
  # "дзеркало", byte-identical text with host-specific chrome: the mirror's
  # stylesheet/link URLs name its own host). A page that fails on both hosts
  # fails the fetch (Error → the adapter's FetchError). Which host served
  # each page is recorded in the state file.
  #
  # == The retention contract (TitusFetch's phases)
  #
  #   prepare!   GET every listed page (polite: DELAY between requests, a
  #              nabu User-Agent); doomed = local *.htm pages no longer
  #              listed. The live tree is untouched.
  #   [guard]    the caller's mass-deletion breaker.
  #   complete!  attic the doomed (GitFetch manifest shape), delete them,
  #              write every page whose bytes changed (tmp+rename), write
  #              the state file.
  #
  # Bytes are stored VERBATIM (the site serves windows-1251; decoding is the
  # parser's job at the adapter boundary). The pin is the sha256 of the
  # sorted page → body-sha map.
  class LitopysFetch
    class Error < Nabu::Error; end

    STATE_FILE = ".litopys-fetch.json"

    HOSTS = ["http://litopys.org.ua/", "http://izbornyk.org.ua/"].freeze

    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :changed, :page_count, :mirrored)

    def self.sync!(pages:, dir:, attic_dir:, http: ZipFetch.default_http, hosts: HOSTS,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(pages: pages, dir: dir, attic_dir: attic_dir, http: http, hosts: hosts,
                  delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, changed: fetch.changed,
                 page_count: fetch.page_count, mirrored: fetch.mirrored)
    end

    def initialize(pages:, dir:, attic_dir:, http: ZipFetch.default_http, hosts: HOSTS,
                   delay: DELAY, progress: nil)
      raise ArgumentError, "no pages to fetch" if pages.empty?

      @rels = pages.map(&:to_s)
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @hosts = hosts
      @delay = delay
      @progress = progress
      @pages = {} # rel => { body:, sha:, host: }
      @doomed = []
      @changed = []
      @atticked = []
      @requests = 0
    end

    attr_reader :atticked, :sha

    def page_count = @pages.size
    def changed = @changed.size
    def mirrored = @pages.reject { |_rel, page| page[:host] == @hosts.first }.keys.sort

    # Phase 1 — GET every listed page; live tree untouched.
    def prepare!
      @rels.each do |rel|
        body, host = get_with_fallback(rel)
        @pages[rel] = { body: body, sha: Digest::SHA256.hexdigest(body), host: host }
      end
      @sha = Digest::SHA256.hexdigest(JSON.generate(@pages.sort.to_h { |rel, page| [rel, page[:sha]] }))
      @changed = @pages.reject { |rel, page| unchanged?(rel, page) }.keys
      @doomed = doomed_relpaths
    end

    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the delisted, then write every changed page.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      @changed.each do |rel|
        page = @pages.fetch(rel)
        target = File.join(@dir, rel)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", page[:body])
        File.rename("#{target}.tmp", target)
      end
      write_state!
    end

    private

    def unchanged?(rel, page)
      path = File.join(@dir, rel)
      File.file?(path) && Digest::SHA256.file(path).hexdigest == page[:sha]
    end

    def get_with_fallback(rel)
      failures = []
      @hosts.each do |host|
        return [get(URI.join(host, rel).to_s), host]
      rescue Error => e
        failures << e.message
      end
      raise Error, "#{rel}: every host failed — #{failures.join('; ')}"
    end

    # Live *.htm pages (outside the attic) the list no longer names.
    def doomed_relpaths
      return [] unless Dir.exist?(@dir)

      Dir.glob("**/*.htm", base: @dir).sort.reject do |rel|
        rel.start_with?(".") || rel.split("/").any? { |part| part.start_with?(".") } || @pages.key?(rel)
      end
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
      record_manifest! unless @atticked.empty?
    end

    def record_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      @atticked.each { |rel| manifest[rel] ||= @sha }
      File.write(path, JSON.pretty_generate(manifest))
    end

    def write_state!
      FileUtils.mkdir_p(@dir)
      state = { "last_modified" => nil, "sha256" => @sha, "url" => @hosts.first,
                "pages" => @pages.sort.to_h { |rel, page| [rel, { "sha256" => page[:sha], "host" => page[:host] }] } }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # One throttled, UA-identified GET; the body as raw bytes (BINARY).
    def get(url)
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
      @progress&.call("Fetching #{url}…\n")
      response, = RedirectFollow.get(url, http: @http, error: Error,
                                          headers: { "User-Agent" => USER_AGENT })
      response.body.to_s.b
    end
  end
end
