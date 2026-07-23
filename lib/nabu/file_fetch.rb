# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "faraday"

require_relative "redirect_follow"

module Nabu
  # Non-destructive single-file HTTP download — ZipFetch's sibling for
  # upstreams that serve ONE plain file (P12-2; architecture §8). OTA serves
  # the whole ASPR corpus as a single 2.2 MB XML over plain HTTP (no git
  # repo, no zip), so neither GitFetch nor ZipFetch applies — but their
  # shared retention contract does, verbatim: conditional GET on the stored
  # Last-Modified (304 → tree untouched), sha256 body pin in a state file,
  # the caller's guard running on any would-be deletions BEFORE the tree
  # mutates, and attic retention with a GitFetch-format manifest.
  #
  # Deliberately NOT a mode of ZipFetch: that class is irreducibly zip-shaped
  # (system unzip, single-top-dir tree root, a staged multi-file tree whose
  # set-difference is the doomed list). Here the "staged tree" is one file.
  # What CAN be doomed: a live file under +dir+ that is not the fetch target
  # — in practice only a stale, differently-named previous download after a
  # FILENAME migration (upstream cannot delete siblings it never served). A
  # CHANGED body is an update, never an attic case — exactly as the git
  # adapters treat modified files. The one piece of genuinely shared infra,
  # ZipFetch.default_http (the vendored-cert Faraday connection), is reused
  # by reference.
  #
  # == The GitFetch/ZipFetch phase mirror
  #
  #   prepare!     conditional GET; on 200 the body is held in memory (the
  #                pin is its sha256) and the doomed set is computed; the
  #                live tree is untouched. On 304 nothing else happens.
  #   [guard]      the caller's breaker runs between the phases: raising here
  #                aborts with the tree byte-unchanged (no attic writes).
  #   complete!    attic the doomed files (first copy wins, manifest records
  #                the body sha they vanished at), write the fetched file,
  #                delete the doomed, write the state file.
  #
  # State file (.file-fetch.json, same JSON shape as ZipFetch's): the
  # Last-Modified replayed as If-Modified-Since, the body sha256 (the
  # FetchReport pin), and the url. The remote-health probe reads the same
  # last_modified pin for drift (Health::RemoteProbe via HttpProbeTarget's
  # state_file).
  #
  # The GET follows redirects (RedirectFollow, the ZipFetch doctrine):
  # If-Modified-Since rides every hop, a 304 is honored pre-redirect or from
  # the mirror, and the state file keys off the ORIGINAL url — never the
  # rotating redirect target.
  class FileFetch
    # HTTP-level failure (non-200/304, transport error). Adapters wrap it in
    # Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".file-fetch.json"

    # What one completed sync did: the body's sha256 (the pin), the relative
    # paths newly copied into the attic, and whether upstream said 304 (sha
    # then repeats the stored pin; nothing was touched).
    Result = Data.define(:sha, :atticked, :not_modified)

    # The shared cert-hardened Faraday connection (system trust store PLUS
    # the vendored intermediates) — genuine common infrastructure, one
    # reference, no dual-mode plumbing.
    def self.default_http
      ZipFetch.default_http
    end

    # One-shot fetch. +guard+, when given, is called with the absolute
    # live-tree paths this fetch would delete — BEFORE any tree mutation —
    # and may raise (Nabu::SyncAborted) to abort.
    def self.sync!(url:, dir:, filename:, attic_dir:, http: default_http, progress: nil, guard: nil)
      fetch = new(url: url, dir: dir, filename: filename, attic_dir: attic_dir, http: http, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, not_modified: fetch.not_modified?)
    end

    def initialize(url:, dir:, filename:, attic_dir:, http: self.class.default_http, progress: nil)
      @url = url
      @dir = dir
      @filename = filename
      @attic_dir = attic_dir
      @http = http
      @progress = progress
      @doomed_relpaths = []
      @atticked = []
      @body = nil
      @not_modified = false
    end

    # Relative paths copied into the attic by complete! (first copies only).
    attr_reader :atticked

    # The sha256 of the fetched body; on a 304 the previously stored pin.
    attr_reader :sha

    # The md5 of the fetched body (P41-2 — Zenodo publishes md5 checksums,
    # the OpenITI TSV pin); nil on a 304.
    attr_reader :md5

    def not_modified?
      @not_modified
    end

    # Phase 1 — download; live tree untouched.
    def prepare!
      response = get_file
      if response.status == 304
        @not_modified = true
        @sha = state["sha256"]
        return
      end

      @body = response.body.to_s.b
      @sha = Digest::SHA256.hexdigest(@body)
      @md5 = Digest::MD5.hexdigest(@body)
      @new_last_modified = response.headers["last-modified"]
      @doomed_relpaths = live_relpaths - [@filename]
    end

    # Absolute live-tree paths this fetch would delete. Empty on 304, on a
    # fresh fetch, and on every ordinary repeat sync.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the doomed files, then write the fetched body.
    def complete!
      return if @not_modified

      attic_doomed!
      FileUtils.mkdir_p(@dir)
      File.binwrite(File.join(@dir, @filename), @body)
      @doomed_relpaths.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_state!
    end

    private

    # Redirects followed (the DSpace/figshare mirror shape); a 304 — first
    # hop or post-redirect — is a terminal answer, not an error.
    def get_file(headers = conditional_headers)
      @progress&.call("Downloading #{@url}…\n")
      response, = RedirectFollow.get(@url, http: @http, error: Error,
                                           headers: headers, accept: [200, 304])
      response
    end

    # If-Modified-Since only when a previous fetch stored Last-Modified AND
    # the file is actually on disk (a wiped tree must re-download).
    def conditional_headers
      last_modified = state["last_modified"]
      return {} unless last_modified && File.file?(File.join(@dir, @filename))

      { "If-Modified-Since" => last_modified }
    end

    def state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def write_state!
      state = { "last_modified" => @new_last_modified, "sha256" => @sha, "url" => @url }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # Live files this fetch could delete: everything under +dir+ except the
    # target file itself, the state file and (when nested inside) the attic.
    def live_relpaths
      return [] unless Dir.exist?(@dir)

      attic_prefix = attic_relprefix
      Dir.glob("**/*", File::FNM_DOTMATCH, base: @dir)
         .reject { |rel| rel.end_with?(".") }
         .select { |rel| File.file?(File.join(@dir, rel)) }
         .reject { |rel| rel == STATE_FILE || (attic_prefix && rel.start_with?(attic_prefix)) }
    end

    def attic_relprefix
      dir = File.expand_path(@dir)
      attic = File.expand_path(@attic_dir)
      return nil unless attic.start_with?("#{dir}#{File::SEPARATOR}")

      "#{attic.delete_prefix("#{dir}#{File::SEPARATOR}")}#{File::SEPARATOR}"
    end

    # First copy wins — the text as first scrapped is the retained asset —
    # and the manifest records the body sha each file vanished at (first
    # record wins too), in GitFetch's exact format so the adapter base
    # class's attic rediscovery reads it generically.
    def attic_doomed!
      @doomed_relpaths.each do |rel|
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
  end
end
