# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Nabu
  # Git LFS materialization for GitFetch-managed repos (P31-2, the cdli
  # data repo). HONEST DESIGN NOTE: `git lfs` is a separate binary this
  # machine does not carry, and GitFetch's clone/pull leaves LFS files as
  # 134-byte POINTER stubs ("version https://git-lfs.github.com/spec/v1" +
  # oid sha256 + size) whenever the extension is absent. Rather than
  # depend on an uninstalled tool, this class speaks the LFS protocol
  # directly — the standard Batch API every LFS server exposes at
  # <repo>.git/info/lfs/objects/batch (verified live against github.com/
  # cdli-gh/data anonymously, 2026-07-19): POST the pointer's oid+size,
  # GET the returned href, sha256-verify AGAINST THE POINTER'S OWN OID,
  # rename into place. A machine WITH git-lfs installed smudges payloads
  # at clone time; materialize! then finds no pointers and reports the
  # files present — both worlds behave identically downstream.
  #
  # == The pull cycle (why restore_pointers! exists)
  #
  # A materialized payload differs from the committed pointer blob, so the
  # working tree is dirty in git's eyes and a later `git merge --ff-only`
  # would refuse to update that file. Before a pull, each RECORDED
  # materialized payload steps aside into the oid-keyed cache
  # (.lfs-cache/<oid>) and its pointer is restored via `git checkout --`;
  # after the merge, materialize! re-reads the (possibly new) pointers and
  # reuses the cache on an oid hit — an unchanged upstream costs one
  # rename, never a re-download. Cache and state file are written to
  # .git/info/exclude (local-only), mirroring GitFetch's attic exclusion.
  #
  # State (.lfs-fetch.json: relpath → oid) records what THIS class
  # materialized; a payload smudged by real git-lfs is left alone.
  class LfsFetch
    class Error < Nabu::Error; end

    POINTER_PREFIX = "version https://git-lfs.github.com/spec/v1"
    # Pointer files are ~130 bytes; anything past this is payload.
    POINTER_MAX_BYTES = 512

    STATE_FILE = ".lfs-fetch.json"
    CACHE_DIRNAME = ".lfs-cache"

    BATCH_MEDIA_TYPE = "application/vnd.git-lfs+json"

    # Is the file at +path+ an LFS pointer stub (not a materialized payload)?
    def self.pointer?(path)
      return false unless File.file?(path) && File.size(path) <= POINTER_MAX_BYTES

      File.read(path, POINTER_PREFIX.bytesize) == POINTER_PREFIX
    end

    # { oid:, size: } from a pointer file; raises Error on a malformed one.
    def self.parse_pointer(path)
      content = File.read(path)
      oid = content[/^oid sha256:(\h{64})$/, 1]
      size = content[/^size (\d+)$/, 1]
      raise Error, "#{path}: malformed LFS pointer" if oid.nil? || size.nil?

      { oid: oid, size: Integer(size) }
    end

    def initialize(repo_url:, dir:, paths:, http: ZipFetch.default_http)
      @repo_url = repo_url
      @dir = dir
      @paths = paths
      @http = http
    end

    # Pre-pull: move each recorded materialized payload into the oid cache
    # and restore its committed pointer, so the merge sees the tree git
    # expects. A no-op on fresh dirs, empty state, or already-pointer files.
    def restore_pointers!
      return unless Dir.exist?(File.join(@dir, ".git"))

      state = read_state
      return if state.empty?

      state.each do |relpath, oid|
        path = File.join(@dir, relpath)
        next unless File.file?(path) && !self.class.pointer?(path)

        FileUtils.mkdir_p(cache_dir)
        FileUtils.mv(path, cache_path(oid))
        Shell.run("git", "-C", @dir, "checkout", "--quiet", "--", relpath)
      end
      write_state({})
    end

    # Post-merge: turn every pointer among +paths+ into its payload —
    # cache hit by oid, else Batch-API download, always sha256-verified.
    # Returns a human note ("lfs: cdli_cat.csv=2e3232f7 (154,768,722 B,
    # downloaded) · …") or nil when there was nothing to do.
    def materialize!(progress: nil)
      exclude_locals!
      notes = @paths.filter_map do |relpath|
        path = File.join(@dir, relpath)
        next unless File.file?(path)
        next "#{relpath} present (smudged upstream of us)" unless self.class.pointer?(path)

        pointer = self.class.parse_pointer(path)
        progress&.call("Materializing #{relpath} (#{pointer[:size]} bytes)…\n")
        how = materialize_one(path, pointer)
        record_state(relpath, pointer[:oid])
        "#{relpath}=#{pointer[:oid][0, 8]} (#{pointer[:size]} B, #{how})"
      end
      notes.empty? ? nil : "lfs: #{notes.join(' · ')}"
    end

    private

    def materialize_one(path, pointer)
      cached = cache_path(pointer[:oid])
      if File.file?(cached) && File.size(cached) == pointer[:size]
        FileUtils.mv(cached, path)
        return "cached"
      end

      download_to(path, pointer)
      "downloaded"
    end

    def download_to(path, pointer)
      body = fetch_payload(pointer)
      digest = Digest::SHA256.hexdigest(body)
      unless digest == pointer[:oid] && body.bytesize == pointer[:size]
        raise Error, "#{path}: LFS payload verification failed " \
                     "(sha256 #{digest[0, 12]}… vs pointer oid #{pointer[:oid][0, 12]}…, " \
                     "#{body.bytesize} vs #{pointer[:size]} bytes)"
      end

      File.binwrite("#{path}.lfs-tmp", body)
      File.rename("#{path}.lfs-tmp", path)
    end

    def fetch_payload(pointer)
      href = batch_download_href(pointer)
      response = @http.get(href)
      raise Error, "LFS download HTTP #{response.status} for oid #{pointer[:oid][0, 12]}…" unless
        response.status == 200

      response.body.to_s
    rescue Faraday::Error => e
      raise Error, "LFS transport error: #{e.message}"
    end

    # The standard Batch API exchange (class note).
    def batch_download_href(pointer)
      response = @http.post(batch_url) do |request|
        request.headers["Accept"] = BATCH_MEDIA_TYPE
        request.headers["Content-Type"] = BATCH_MEDIA_TYPE
        request.body = JSON.generate(
          operation: "download", transfers: ["basic"],
          objects: [{ oid: pointer[:oid], size: pointer[:size] }]
        )
      end
      raise Error, "LFS batch API HTTP #{response.status} at #{batch_url}" unless response.status == 200

      object = JSON.parse(response.body.to_s).fetch("objects", []).first || {}
      error = object["error"]
      raise Error, "LFS batch API: #{error['message']} (oid #{pointer[:oid][0, 12]}…)" if error

      object.dig("actions", "download", "href") or
        raise Error, "LFS batch API returned no download action for oid #{pointer[:oid][0, 12]}…"
    rescue Faraday::Error => e
      raise Error, "LFS transport error: #{e.message}"
    rescue JSON::ParserError => e
      raise Error, "LFS batch API returned unparseable JSON: #{e.message}"
    end

    def batch_url
      "#{@repo_url.delete_suffix('/').delete_suffix('.git')}.git/info/lfs/objects/batch"
    end

    # -- state + cache --------------------------------------------------------

    def state_path = File.join(@dir, STATE_FILE)
    def cache_dir = File.join(@dir, CACHE_DIRNAME)
    def cache_path(oid) = File.join(cache_dir, oid)

    def read_state
      return {} unless File.file?(state_path)

      JSON.parse(File.read(state_path))
    rescue JSON::ParserError
      {}
    end

    def record_state(relpath, oid)
      write_state(read_state.merge(relpath => oid))
    end

    def write_state(state)
      File.write(state_path, JSON.pretty_generate(state))
    end

    # Keep cache + state out of git's sight (GitFetch attic precedent);
    # idempotent, silent on non-git dirs (tests exercise bare tmpdirs).
    def exclude_locals!
      exclude = File.join(@dir, ".git", "info", "exclude")
      return unless Dir.exist?(File.join(@dir, ".git"))

      patterns = ["/#{CACHE_DIRNAME}/", "/#{STATE_FILE}"]
      existing = File.exist?(exclude) ? File.readlines(exclude, chomp: true) : []
      missing = patterns - existing
      return if missing.empty?

      FileUtils.mkdir_p(File.dirname(exclude))
      File.open(exclude, "a") { |io| missing.each { |pattern| io.puts(pattern) } }
    end
  end
end
