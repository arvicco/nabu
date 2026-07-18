# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "faraday"

require_relative "redirect_follow"

module Nabu
  # Index-driven named-file fetch (P30-3; architecture §8) — the fetch shape
  # for Sefaria's restructured export, where upstream is TWO surfaces: a
  # lightweight monthly-regenerated INDEX (books.json in the Sefaria-Export
  # git repo — 19,705 version entries naming every file in the bucket) and a
  # ~26 GB public GCS BUCKET that must never be fetched wholesale. One sync:
  #
  #   1. conditional GET of the index (If-Modified-Since on the stored pin;
  #      304 → the tree is byte-untouched and the sync is over);
  #   2. the caller's +select+ callable picks the in-scope version entries
  #      (the Targum shelf — scope is an adapter decision, not fetch logic);
  #   3. exactly those named files are GET (each with its own per-file
  #      Last-Modified pin, so an unchanged shelf re-sync moves ~no bytes);
  #   4. index + files land in canonical — the pinned index IS the
  #      reproducibility artifact: the fetched scope can always be re-derived
  #      from the bytes on disk.
  #
  # The GitFetch/ZipFetch/FileFetch retention contract holds verbatim: the
  # caller's guard runs on any would-be deletions (files leaving the selected
  # scope or vanishing from the index) BEFORE the tree mutates, deletions are
  # preserved under the attic with a GitFetch-format manifest (first copy
  # wins; the manifest records the index sha the file vanished at), and any
  # HTTP failure aborts with the tree byte-unchanged (version files are
  # staged in memory and written only after every GET succeeded — the whole
  # selected shelf is ~16 MB, well within staging). The fetch pin
  # (FetchReport sha) is the INDEX body's sha256 — the one hash that names
  # the whole fetched scope.
  #
  # Bucket keys contain spaces, commas and (one versionTitle) a trailing
  # space; the wire URL percent-encodes each path segment while the on-disk
  # relpath keeps upstream's exact bytes.
  class SefariaFetch
    # HTTP-level failure or a malformed/inconsistent index. Adapters wrap it
    # in Nabu::FetchError.
    class Error < Nabu::Error; end

    INDEX_FILE = "books.json"
    STATE_FILE = ".sefaria-fetch.json"

    # What one completed sync did: the index sha256 (the pin), the relative
    # paths newly copied into the attic, whether the index said 304, and how
    # many version files actually moved bytes (the rest were per-file 304s).
    Result = Data.define(:sha, :atticked, :not_modified, :downloaded)

    # The shared cert-hardened Faraday connection (ZipFetch's, by reference).
    def self.default_http
      ZipFetch.default_http
    end

    # One-shot sync. +select+ is called with each index book entry (a Hash)
    # and returns truthy for in-scope versions; +guard+, when given, receives
    # the absolute live-tree paths this sync would delete — BEFORE any tree
    # mutation — and may raise (Nabu::SyncAborted) to abort.
    def self.sync!(index_url:, dir:, attic_dir:, select:, http: default_http, progress: nil, guard: nil)
      fetch = new(index_url: index_url, dir: dir, attic_dir: attic_dir,
                  select: select, http: http, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked,
                 not_modified: fetch.not_modified?, downloaded: fetch.downloaded)
    end

    def initialize(index_url:, dir:, attic_dir:, select:, http: self.class.default_http, progress: nil)
      @index_url = index_url
      @dir = dir
      @attic_dir = attic_dir
      @select = select
      @http = http
      @progress = progress
      @selected = {}
      @doomed_relpaths = []
      @atticked = []
      @downloaded = 0
      @not_modified = false
    end

    attr_reader :atticked, :sha, :downloaded

    def not_modified?
      @not_modified
    end

    # Phase 1 — GET the index, resolve the selected scope, compute the doomed
    # set. The live tree is untouched; no version file has been requested.
    def prepare!
      response = get(@index_url, conditional: index_conditional_headers)
      if response.status == 304
        @not_modified = true
        @sha = state.dig("index", "sha256")
        return
      end

      @index_body = response.body.to_s.b
      @index_last_modified = response.headers["last-modified"]
      @sha = Digest::SHA256.hexdigest(@index_body)
      @selected = selected_relpaths(parse_index(@index_body))
      @doomed_relpaths = live_relpaths - @selected.keys - [INDEX_FILE]
    end

    # Absolute live-tree paths this sync would delete: previously fetched
    # files that left the selected scope (or the index). Empty on 304 and on
    # every ordinary repeat sync.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — download the selected files (all staged in memory before any
    # write, so a mid-flight failure leaves the tree byte-unchanged), then
    # attic the doomed, land everything, pin the state.
    def complete!
      return if @not_modified

      staged = download_selected
      attic_doomed!
      write_tree!(staged)
      @doomed_relpaths.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_state!(staged)
    end

    private

    # rel path (upstream bytes, the on-disk key) => bucket url. A selected
    # entry whose json_url is missing, outside the index's own base_url, or
    # path-traversing is an index inconsistency — loud, never guessed around.
    def selected_relpaths(index)
      base = index["base_url"]
      raise Error, "#{@index_url}: index carries no base_url" unless base.is_a?(String) && !base.empty?

      index.fetch("books").each_with_object({}) do |entry, map|
        next unless entry.is_a?(Hash) && @select.call(entry)

        map[relpath!(entry, base)] = entry["json_url"]
      end
    end

    def relpath!(entry, base)
      url = entry["json_url"]
      unless url.is_a?(String) && url.start_with?("#{base}/")
        raise Error, "#{@index_url}: selected entry #{entry['title'].inspect}/" \
                     "#{entry['versionTitle'].inspect} has json_url #{url.inspect} outside base_url #{base}"
      end

      rel = url.delete_prefix("#{base}/")
      if rel.empty? || rel.start_with?("/") || rel.split("/").include?("..")
        raise Error, "#{@index_url}: unsafe bucket path #{rel.inspect}"
      end

      rel
    end

    def parse_index(body)
      parsed = JSON.parse(body)
      unless parsed.is_a?(Hash) && parsed["books"].is_a?(Array)
        raise Error, "#{@index_url}: index is not an object with a books list"
      end

      parsed
    rescue JSON::ParserError => e
      raise Error, "#{@index_url}: malformed index JSON: #{e.message}"
    end

    # rel => [body, last_modified] for files upstream said changed; a
    # per-file 304 keeps the on-disk copy and its pin.
    def download_selected
      pins = state.fetch("files", {})
      @selected.each_with_object({}) do |(rel, url), staged|
        response = get(encode(url), conditional: file_conditional_headers(rel, pins))
        next if response.status == 304

        staged[rel] = [response.body.to_s.b, response.headers["last-modified"]]
        @downloaded += 1
      end
    end

    def write_tree!(staged)
      FileUtils.mkdir_p(@dir)
      File.binwrite(File.join(@dir, INDEX_FILE), @index_body)
      staged.each do |rel, (body, _last_modified)|
        path = File.join(@dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, body)
      end
    end

    # The new pin set: the index pin plus one entry per SELECTED file —
    # fresh downloads pin their new Last-Modified/sha, per-file 304s carry
    # their stored pin forward, and files that left the scope drop out.
    def write_state!(staged)
      old = state.fetch("files", {})
      files = @selected.keys.to_h do |rel|
        pin = if staged.key?(rel)
                body, last_modified = staged[rel]
                { "last_modified" => last_modified, "sha256" => Digest::SHA256.hexdigest(body) }
              else
                old.fetch(rel, {})
              end
        [rel, pin]
      end
      state_json = {
        "index" => { "url" => @index_url, "last_modified" => @index_last_modified, "sha256" => @sha },
        "files" => files
      }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state_json))
    end

    def get(url, conditional:)
      @progress&.call("Downloading #{url}…")
      response, = RedirectFollow.get(url, http: @http, error: Error,
                                          headers: conditional, accept: [200, 304])
      response
    end

    def index_conditional_headers
      last_modified = state.dig("index", "last_modified")
      return {} unless last_modified && File.file?(File.join(@dir, INDEX_FILE))

      { "If-Modified-Since" => last_modified }
    end

    def file_conditional_headers(rel, pins)
      last_modified = pins.dig(rel, "last_modified")
      return {} unless last_modified && File.file?(File.join(@dir, rel))

      { "If-Modified-Since" => last_modified }
    end

    # The wire form of a bucket url: every path segment percent-encoded
    # (spaces, commas, upstream's trailing space), scheme://host untouched.
    def encode(url)
      scheme, rest = url.split("://", 2)
      return url if rest.nil?

      host, path = rest.split("/", 2)
      return url if path.nil?

      encoded = path.split("/", -1).map { |segment| CGI.escapeURIComponent(segment) }.join("/")
      "#{scheme}://#{host}/#{encoded}"
    end

    def state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    # Live files this sync could delete: everything under +dir+ except the
    # index, the state file and (when nested inside) the attic.
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

    # First copy wins — the text as first fetched is the retained asset —
    # and the manifest records the index sha each file vanished at (first
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
