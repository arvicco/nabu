# frozen_string_literal: true

require "fileutils"
require "json"

module Nabu
  # Non-destructive git clone/pull — the ONE shared fetch path behind every
  # git-based adapter (P5-2, architecture §3/§8).
  #
  # == Why a plain `git pull` is forbidden here
  #
  # The working tree under canonical/<slug>/ IS the permanent asset, and the
  # derived db is a pure function of it (`nabu rebuild`). A plain pull deletes
  # working-tree files that upstream scrapped, so the next rebuild would
  # silently lose those documents — exactly what the retention contract
  # forbids. The pull is therefore split into two phases:
  #
  #   prepare!     clone (fresh dir) or `git fetch` (objects only — the
  #                working tree is untouched). For pulls, the upstream
  #                deletions are computed from `diff HEAD FETCH_HEAD`.
  #   [guard]      the caller's mass-deletion breaker runs between the
  #                phases: raising here aborts with the canonical tree
  #                byte-unchanged (no merge, no attic writes).
  #   complete!    copy each doomed file into the attic, then
  #                `git merge --ff-only FETCH_HEAD`.
  #
  # Single-repo adapters use the one-shot ::sync!; multi-repo adapters (UD)
  # drive the phases themselves so ALL repos are prepared and guarded before
  # ANY repo merges.
  #
  # == The attic
  #
  # Upstream-deleted files are copied to <attic_dir>/<same relative path>
  # before the merge removes them, so the adapter's own discover sees the
  # same shapes under .attic as under the live tree. First copy wins: an
  # existing attic file is NEVER overwritten (the text as first scrapped is
  # the retained asset; later upstream churn cannot degrade it). Each attic
  # dir carries a `.attic.json` manifest mapping relative path → the upstream
  # sha (FETCH_HEAD) the file vanished at — first record wins too — which is
  # how the loader's "retired" provenance gets its sha even on a rebuild
  # years later (the manifest lives inside canonical/, so db = f(canonical)
  # holds sha and all).
  #
  # Renames are NOT scrapping: the diff runs with --find-renames (explicit,
  # so user git config cannot flip it), and a rename reports as R, never D —
  # the content survives at its new path, nothing is atticked. Adapters whose
  # urns are content-derived rediscover the same document; adapters whose
  # urns are path-derived withdraw the old urn (text kept in the catalog, as
  # ever) while the content lives on under the new urn.
  #
  # When the attic sits inside the repo's working tree (the single-repo
  # layout), it is written to .git/info/exclude so `git status` stays clean
  # and pulls never see it as noise. Upstream corpora do not track ".attic"
  # paths; if one ever did, git itself would refuse the merge loudly
  # ("untracked working tree files would be overwritten") rather than
  # silently corrupt either side — an acceptable failure mode for a
  # theoretical collision.
  #
  # All git invocations go through Nabu::Shell (argv semantics, Shell::Error
  # on nonzero exit); adapters wrap that in Nabu::FetchError as before.
  class GitFetch
    ATTIC_MANIFEST = ".attic.json"

    # What one completed sync did: the new HEAD and the relative paths
    # newly copied into the attic this time (empty on fresh clones,
    # up-to-date pulls, and re-deletions of already-atticked paths).
    Result = Data.define(:sha, :atticked)

    # One-shot clone-or-pull for a single repo. +guard+, when given, is
    # called with the absolute working-tree paths upstream deleted — BEFORE
    # any tree mutation — and may raise (Nabu::SyncAborted) to abort.
    #
    # +ref+ (P17-1) PINS the sync to a tag (or branch) instead of the
    # clone's default branch: fresh clones use `--branch <ref>`, pulls fetch
    # exactly that ref into FETCH_HEAD — so a "versioned" upstream (Coptic
    # Scriptorium's semiannual releases) never tracks its moving master, and
    # an owner re-pin to a later release tag fast-forwards through the same
    # attic/breaker contract as any pull.
    def self.sync!(repo_url:, dir:, attic_dir:, progress: nil, guard: nil, ref: nil)
      pull = new(repo_url: repo_url, dir: dir, attic_dir: attic_dir, progress: progress, ref: ref)
      pull.prepare!
      guard&.call(pull.doomed_paths)
      pull.complete!
      Result.new(sha: pull.head_sha, atticked: pull.atticked)
    end

    def initialize(repo_url:, dir:, attic_dir:, progress: nil, ref: nil)
      @repo_url = repo_url
      @dir = dir
      @attic_dir = attic_dir
      @progress = progress
      @ref = ref
      @doomed_relpaths = []
      @atticked = []
      @cloned = false
    end

    # Relative paths copied into the attic by complete! (first copies only).
    attr_reader :atticked

    # Phase 1 — objects only, working tree untouched. A fresh dir is cloned
    # (--depth 1, the house budget for multi-GB corpora; nothing local exists
    # to protect); an existing repo is `git fetch`ed and the upstream
    # deletions recorded for the guard/attic.
    def prepare!
      if Dir.exist?(File.join(@dir, ".git"))
        git_fetch
        @doomed_relpaths = deleted_relpaths
      else
        git_clone
        @cloned = true
      end
      exclude_attic!
    end

    # Absolute working-tree paths the pending merge would delete. Empty for
    # fresh clones. The caller's breaker predicts from these.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.expand_path(File.join(@dir, rel)) }
    end

    # Phase 2 — attic the doomed files, then ff-merge FETCH_HEAD. A no-op
    # after a fresh clone (already at the remote head).
    def complete!
      return if @cloned

      attic_doomed!
      Shell.run("git", "-C", @dir, "merge", "--ff-only", "--quiet", "FETCH_HEAD")
    end

    def head_sha
      Shell.run("git", "-C", @dir, "rev-parse", "HEAD").strip
    end

    private

    def git_clone
      pin = @ref ? ["--branch", @ref] : []
      unless @progress
        Shell.run("git", "clone", "--depth", "1", *pin, @repo_url, @dir)
        return
      end
      @progress.call("Cloning #{@repo_url}…")
      Shell.stream("git", "clone", "--progress", "--depth", "1", *pin, @repo_url, @dir) { |line| @progress.call(line) }
    end

    # Fetch exactly the pinned ref — or, unpinned, the branch the clone
    # tracks — so FETCH_HEAD is a single unambiguous ref for both the diff
    # and the merge.
    def git_fetch
      target = @ref || Shell.run("git", "-C", @dir, "rev-parse", "--abbrev-ref", "HEAD").strip
      unless @progress
        Shell.run("git", "-C", @dir, "fetch", "--quiet", "origin", target)
        return
      end
      @progress.call("Pulling #{@repo_url}…")
      Shell.stream("git", "-C", @dir, "fetch", "--progress", "origin", target) { |line| @progress.call(line) }
    end

    # Files the merge would delete: status D between HEAD and FETCH_HEAD.
    # --find-renames is explicit so a rename always reports as R (not D+A)
    # regardless of the user's diff.renames setting; -z gives raw NUL-split
    # paths (git would otherwise quote non-ASCII names, and corpora have them).
    def deleted_relpaths
      Shell.run("git", "-C", @dir, "diff", "--name-only", "--diff-filter=D",
                "--find-renames", "-z", "HEAD", "FETCH_HEAD").split("\0")
    end

    # Copy each doomed file into the attic — first copy wins — and record the
    # upstream sha it vanished at in the attic manifest.
    def attic_doomed!
      @doomed_relpaths.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next unless File.file?(source)
        next if File.exist?(destination) # first copy wins: never overwrite

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
      record_manifest! unless @atticked.empty?
    end

    def record_manifest!
      path = File.join(@attic_dir, ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      vanished_at = Shell.run("git", "-C", @dir, "rev-parse", "FETCH_HEAD").strip
      @atticked.each { |rel| manifest[rel] ||= vanished_at } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end

    # Keep the attic out of git's sight when it lives inside this repo's
    # working tree (.git/info/exclude is local-only, never pushed). Idempotent.
    def exclude_attic!
      dir = File.expand_path(@dir)
      attic = File.expand_path(@attic_dir)
      return unless attic.start_with?("#{dir}#{File::SEPARATOR}")

      pattern = "/#{attic.delete_prefix("#{dir}#{File::SEPARATOR}")}/"
      exclude = File.join(dir, ".git", "info", "exclude")
      return if File.exist?(exclude) && File.readlines(exclude, chomp: true).include?(pattern)

      FileUtils.mkdir_p(File.dirname(exclude))
      File.open(exclude, "a") { |io| io.puts(pattern) }
    end
  end
end
