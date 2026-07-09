# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"
require "faraday"

module Nabu
  # Non-destructive HTTP-zip download-and-unpack — the first NON-git fetch
  # path (P10-1; architecture §8). ORACC's open data ships as a per-project
  # zip over plain HTTP (no git repo holds it), so the GitFetch machinery does
  # not apply — but the retention contract does, verbatim: files present
  # locally but absent from a fresh unpack are preserved under the attic with
  # a sha manifest before the live tree changes, first copy wins, and the
  # caller's mass-deletion guard runs BETWEEN download and any tree mutation.
  #
  # == The GitFetch mirror
  #
  #   prepare!     GET the zip (conditionally — see change detection below)
  #                and unpack it into a private staging dir; the live tree is
  #                untouched. Upstream deletions are computed as the set of
  #                live files absent from the staged tree.
  #   [guard]      the caller's breaker runs between the phases: raising here
  #                aborts with the live tree byte-unchanged (no attic writes).
  #   complete!    copy each doomed file into the attic (first copy wins,
  #                manifest records the sha it vanished at), then copy the
  #                staged tree over the live one and delete the doomed files
  #                — the upstream deletion happens only AFTER retention.
  #
  # Single-project sources use the one-shot ::sync!; multi-project adapters
  # (Oracc) drive the phases themselves so ALL projects are prepared and
  # guarded before ANY project's tree changes (the UD choreography).
  #
  # == Change detection: Last-Modified, not shas
  #
  # ORACC serves `Last-Modified`; there is no upstream sha to diff against.
  # The header from each successful fetch is stored in a `.zip-fetch.json`
  # state file inside +dir+ (alongside the zip body's sha256 — the pin the
  # FetchReport carries) and replayed as `If-Modified-Since`; a 304 means the
  # tree is current and nothing is touched. The state file and the attic are
  # never treated as upstream deletions.
  #
  # == The attic manifest
  #
  # Same filename and shape as GitFetch's (GitFetch::ATTIC_MANIFEST,
  # relative path → sha, first record wins) — deliberately: the adapter base
  # class's attic rediscovery reads that manifest generically, so zip-fetched
  # sources get RETIRED_SHA_KEY annotations for free. The recorded sha is the
  # sha256 of the zip build the file vanished at (the closest analog of
  # GitFetch's FETCH_HEAD).
  #
  # Zip layout: ORACC zips carry a single top-level directory (rimanum/…);
  # when the staged unpack has exactly one entry and it is a directory, its
  # CONTENTS become the tree (the project dir maps onto +dir+ directly);
  # otherwise the unpack root itself is the tree. Unzipping goes through
  # Nabu::Shell.run + the system `unzip` (no new gem — house rule).
  class ZipFetch
    # HTTP-level failure (non-200/304, transport error). Adapters wrap it in
    # Nabu::FetchError like they wrap Shell::Error from git/unzip.
    class Error < Nabu::Error; end

    STATE_FILE = ".zip-fetch.json"

    # What one completed sync did: the zip body's sha256 (the pin), the
    # relative paths newly copied into the attic, and whether upstream said
    # 304 (sha then repeats the stored pin; nothing was touched).
    Result = Data.define(:sha, :atticked, :not_modified)

    # One-shot fetch for a single zip. +guard+, when given, is called with
    # the absolute live-tree paths the fresh unpack would delete — BEFORE any
    # tree mutation — and may raise (Nabu::SyncAborted) to abort.
    def self.sync!(url:, dir:, attic_dir:, http: Faraday, progress: nil, guard: nil)
      fetch = new(url: url, dir: dir, attic_dir: attic_dir, http: http, progress: progress)
      begin
        fetch.prepare!
        guard&.call(fetch.doomed_paths)
        fetch.complete!
      ensure
        fetch.cleanup!
      end
      Result.new(sha: fetch.sha, atticked: fetch.atticked, not_modified: fetch.not_modified?)
    end

    def initialize(url:, dir:, attic_dir:, http: Faraday, progress: nil)
      @url = url
      @dir = dir
      @attic_dir = attic_dir
      @http = http
      @progress = progress
      @doomed_relpaths = []
      @atticked = []
      @staging = nil
      @tree = nil
      @not_modified = false
    end

    # Relative paths copied into the attic by complete! (first copies only).
    attr_reader :atticked

    # The sha256 of the fetched zip body; on a 304 the previously stored pin.
    attr_reader :sha

    def not_modified?
      @not_modified
    end

    # Phase 1 — download and unpack into staging; live tree untouched.
    def prepare!
      response = get_zip
      if response.status == 304
        @not_modified = true
        @sha = state["sha256"]
        return
      end

      body = response.body.to_s.b
      @sha = Digest::SHA256.hexdigest(body)
      @new_last_modified = response.headers["last-modified"]
      unpack!(body)
      @doomed_relpaths = live_relpaths - staged_relpaths
    end

    # Absolute live-tree paths the fresh unpack would delete. Empty on 304
    # and on a fresh (no local tree) fetch.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the doomed files, then swap the staged tree in.
    def complete!
      return if @not_modified

      attic_doomed!
      copy_tree!
      @doomed_relpaths.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_state!
    end

    # Remove the staging dir. ::sync! ensure-calls this; multi-project
    # callers must too (a guard abort would otherwise leak the tmpdir).
    def cleanup!
      FileUtils.remove_entry(@staging) if @staging && Dir.exist?(@staging)
      @staging = nil
    end

    private

    def get_zip(headers = conditional_headers)
      @progress&.call("Downloading #{@url}…")
      response = @http.get(@url, nil, headers)
      raise Error, "HTTP #{response.status} for #{@url}" unless [200, 304].include?(response.status)

      response
    rescue Faraday::Error => e
      raise Error, "transport error for #{@url}: #{e.message}"
    end

    # If-Modified-Since only when a previous fetch stored Last-Modified AND
    # the tree is actually on disk (a wiped tree must re-download).
    def conditional_headers
      last_modified = state["last_modified"]
      return {} unless last_modified && Dir.exist?(@dir)

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

    def unpack!(body)
      @staging = Dir.mktmpdir("nabu-zip-fetch")
      zip_path = File.join(@staging, "download.zip")
      File.binwrite(zip_path, body)
      unpacked = File.join(@staging, "unpacked")
      Shell.run("unzip", "-q", zip_path, "-d", unpacked)
      @tree = tree_root(unpacked)
    end

    # The staged tree root: the single top-level directory when the zip
    # carries one (the ORACC shape), else the unpack root itself.
    def tree_root(unpacked)
      entries = Dir.children(unpacked)
      only = entries.size == 1 && File.join(unpacked, entries.first)
      only && File.directory?(only) ? only : unpacked
    end

    def staged_relpaths
      relative_files(@tree)
    end

    # Live files that upstream could delete: everything under +dir+ except
    # the state file and (when nested inside) the attic.
    def live_relpaths
      return [] unless Dir.exist?(@dir)

      attic_prefix = attic_relprefix
      relative_files(@dir).reject do |rel|
        rel == STATE_FILE || (attic_prefix && rel.start_with?(attic_prefix))
      end
    end

    def attic_relprefix
      dir = File.expand_path(@dir)
      attic = File.expand_path(@attic_dir)
      return nil unless attic.start_with?("#{dir}#{File::SEPARATOR}")

      "#{attic.delete_prefix("#{dir}#{File::SEPARATOR}")}#{File::SEPARATOR}"
    end

    def relative_files(root)
      Dir.glob("**/*", File::FNM_DOTMATCH, base: root)
         .reject { |rel| rel.end_with?(".") }
         .select { |rel| File.file?(File.join(root, rel)) }
    end

    # First copy wins — the text as first scrapped is the retained asset —
    # and the manifest records the zip sha each file vanished at (first
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

    def copy_tree!
      staged_relpaths.each do |rel|
        destination = File.join(@dir, rel)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(@tree, rel), destination)
      end
    end
  end
end
