# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

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
  # == Attic-and-reset on a diverged upstream (owner ruling 2026-11-12)
  #
  # An upstream history REWRITE (force-push, re-rooted branch, rollback)
  # leaves FETCH_HEAD unreachable from HEAD, so the ff-only merge can never
  # succeed. By default that stays a hard stop (the merge's Shell::Error):
  # an ordinary source never leaves its line unasked. A caller that opts in
  # (+reset_on_divergence+; the kanripo wave, where ~17% of the text repos
  # diverged — almost all rewrite-only with an identical tree) gets the
  # ruled policy instead, decided in prepare! by
  # `merge-base --is-ancestor HEAD FETCH_HEAD`:
  #
  #   zero delta   HEAD^{tree} == FETCH_HEAD^{tree} (one rev-parse of two
  #                tree ids — no diff, no status, no file read): nothing
  #                to attic, nothing for the guard; complete! moves the
  #                branch with `reset --soft` (index and working tree are
  #                already that tree), so the dominant kanripo case costs
  #                three cheap ref-level git calls beyond the fetch
  #                (ancestry, rev-parse, reset --soft), writes only the
  #                event log line and touches no tracked file.
  #   with delta   the tracked tree must be clean (`status --porcelain
  #                --untracked-files=no`; a local edit is refused with
  #                FetchError, never clobbered). The guard sees the same
  #                find-renames deletion list an ff would — the breaker
  #                stays in front of the reset, and a trip leaves tree,
  #                HEAD and attic untouched. complete! then attics every
  #                file the reset deletes OR changes in place (M/T —
  #                the abandoned history is no longer there to recover
  #                old bytes from), same relative path, first copy wins,
  #                `.attic.json` vanished-at sha = FETCH_HEAD exactly as on
  #                the ff path, and only THEN `reset --hard FETCH_HEAD`.
  #                Renames stay non-scrapping, as on the ff path.
  #
  # Either way the event is appended to <attic_dir>/.attic-resets.json
  # (UTC time, abandoned head, new head, zero_delta, atticked count — the
  # abandoned sha lives only here once git gc's the old line) and reported
  # as Result#reset. A modified file's attic copy shares its live path, so
  # live-wins rediscovery supersedes it until upstream ever deletes the path
  # — at which point first-copy-wins keeps the pre-reset bytes, the same
  # ruled semantics as a delete → reappear → delete cycle.
  #
  # All git invocations go through Nabu::Shell (argv semantics, Shell::Error
  # on nonzero exit); adapters wrap that in Nabu::FetchError as before.
  class GitFetch
    ATTIC_MANIFEST = ".attic.json"
    # The append-only reset event log beside the manifest (class note).
    RESET_LOG = ".attic-resets.json"

    # What one completed sync did: the new HEAD, the relative paths newly
    # copied into the attic this time (empty on fresh clones, up-to-date
    # pulls, zero-delta resets, and re-deletions of already-atticked
    # paths), and the Reset event when the sync took the divergence path
    # (nil otherwise).
    Result = Data.define(:sha, :atticked, :reset)

    # One attic-and-reset: the abandoned head, the upstream head reset to,
    # how many files were newly atticked, and whether the trees were
    # identical (the fast path).
    Reset = Data.define(:from, :to, :atticked, :zero_delta)

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
    #
    # +sparse+ (P26-0) scopes the checkout to the given path prefixes: the
    # fresh clone runs --filter=blob:none --no-checkout, declares the
    # sparse-checkout cone, then materializes it — so only the cone's blobs
    # transfer (DCS: dcs/data/conllu, 844 MB of a ~1.7 GB research repo).
    # Pulls scope the deletion diff to the cone too — files outside it were
    # never this source's retained assets, so they are neither guarded nor
    # atticked. Local-path clones ignore --filter with a warning (git's
    # local-transport rule) — harmless: the sparse cone still governs the
    # working tree, which is the contract under test.
    #
    # +reset_on_divergence+ (owner ruling 2026-11-12) opts into
    # attic-and-reset when upstream is not fast-forwardable (class note);
    # off, a diverged upstream stays the merge's hard stop.
    def self.sync!(repo_url:, dir:, attic_dir:, progress: nil, guard: nil, ref: nil, sparse: nil,
                   reset_on_divergence: false)
      pull = new(repo_url: repo_url, dir: dir, attic_dir: attic_dir, progress: progress, ref: ref,
                 sparse: sparse, reset_on_divergence: reset_on_divergence)
      pull.prepare!
      guard&.call(pull.doomed_paths)
      pull.complete!
      Result.new(sha: pull.head_sha, atticked: pull.atticked, reset: pull.reset)
    end

    def initialize(repo_url:, dir:, attic_dir:, progress: nil, ref: nil, sparse: nil,
                   reset_on_divergence: false)
      @repo_url = repo_url
      @dir = dir
      @attic_dir = attic_dir
      @progress = progress
      @ref = ref
      @sparse = sparse&.then { |paths| Array(paths) }
      @reset_on_divergence = reset_on_divergence
      @doomed_relpaths = []
      @changed_relpaths = []
      @atticked = []
      @cloned = false
      @diverged_from = nil
      @reset = nil
    end

    # Relative paths copied into the attic by complete! (first copies only).
    attr_reader :atticked

    # The Reset event complete! performed (nil unless the sync diverged).
    attr_reader :reset

    # Phase 1 — objects only, working tree untouched. A fresh dir is cloned
    # ATOMICALLY (P44-i1, owner ruling "sync should be atomic": clone +
    # materialize into a sibling .partial staging dir, then one rename —
    # an interrupt leaves only staging debris, swept + announced on the
    # next run, never a half-canonical tree that a resume could mistake
    # for a finished clone; --depth 1 stays the house budget); an existing
    # repo is `git fetch`ed and the upstream deletions recorded for the
    # guard/attic.
    def prepare!
      sweep_stale_staging!
      if Dir.exist?(File.join(@dir, ".git"))
        git_fetch
        if @reset_on_divergence && diverged?
          plan_reset!
        else
          @doomed_relpaths = deleted_relpaths
        end
      else
        atomic_clone!
        @cloned = true
      end
      exclude_attic!
    end

    # Absolute working-tree paths the pending merge would delete. Empty for
    # fresh clones. The caller's breaker predicts from these.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.expand_path(File.join(@dir, rel)) }
    end

    # Phase 2 — attic the doomed files, then ff-merge FETCH_HEAD (or, on a
    # planned divergence, attic-and-reset — class note). A no-op after a
    # fresh clone (already at the remote head).
    def complete!
      return if @cloned

      if @diverged_from
        complete_reset!
      else
        attic_doomed!
        Shell.run("git", "-C", @dir, "merge", "--ff-only", "--quiet", "FETCH_HEAD")
      end
      widen_sparse_cone!
    end

    def head_sha
      Shell.run("git", "-C", @dir, "rev-parse", "HEAD").strip
    end

    private

    # The staging sibling for atomic fresh clones (P44-i1).
    def staging_dir
      "#{@dir}.partial"
    end

    # Debris from an interrupted earlier clone: announced, removed. Safe by
    # construction — the staging dir is ours alone and never canonical.
    def sweep_stale_staging!
      return unless Dir.exist?(staging_dir)

      @progress&.call("removing interrupted clone staging #{staging_dir}…\n")
      FileUtils.remove_entry_secure(staging_dir)
    end

    # Clone + materialize into staging, verify, then ONE rename into place.
    # ANY failure (including the verify) sweeps staging — a failed
    # acquisition leaves neither a canonical tree nor debris.
    def atomic_clone!
      real_dir = @dir
      staging = staging_dir
      @dir = staging
      begin
        git_clone
        verify_materialized!
      rescue StandardError
        FileUtils.rm_rf(staging)
        raise
      ensure
        @dir = real_dir
      end
      File.rename(staging, real_dir)
    end

    # A sparse cone that materialized NOTHING is a failed acquisition, never
    # a silent success (the P44-i1 zero-discovery lie): loud, with the cone
    # named. Non-sparse clones always carry their tree.
    def verify_materialized!
      return unless @sparse

      # Cone entries may be plain paths OR sparse-checkout glob patterns
      # (cards/*/files/*.zip) — a pattern materialized iff it globs to
      # anything, a path iff itself or anything beneath it exists.
      materialized = @sparse.any? do |entry|
        Dir.glob(File.join(@dir, entry)).any? || Dir.glob(File.join(@dir, entry, "**", "*")).any?
      end
      return if materialized

      raise Nabu::FetchError, "sparse clone materialized nothing for cone #{@sparse.join(', ')} in #{@dir}"
    end

    def git_clone
      pin = @ref ? ["--branch", @ref] : []
      return sparse_clone(pin) if @sparse

      unless @progress
        Shell.run("git", "clone", "--depth", "1", *pin, @repo_url, @dir)
        return
      end
      @progress.call("Cloning #{@repo_url}…\n")
      Shell.stream("git", "clone", "--progress", "--depth", "1", *pin, @repo_url, @dir) { |line| @progress.call(line) }
    end

    # The sparse recipe (class note): blobless no-checkout clone, declare the
    # cone, materialize it — only the cone's blobs ever transfer.
    def sparse_clone(pin)
      args = ["clone", "--depth", "1", "--filter=blob:none", "--no-checkout", *pin, @repo_url, @dir]
      if @progress
        @progress.call("Cloning #{@repo_url} (sparse: #{@sparse.join(', ')})…\n")
        Shell.stream("git", *args.insert(1, "--progress")) { |line| @progress.call(line) }
      else
        Shell.run("git", *args)
      end
      Shell.run("git", "-C", @dir, "sparse-checkout", "set", "--no-cone", *@sparse)
      # The cone materialization fetches every blob it needs on demand —
      # on a corpus-sized cone this is the LONG step (minutes), and it used
      # to run in captured silence that read as a hang (P44-i1). Announce.
      @progress&.call("materializing #{@sparse.join(', ')} (first clone fetches the cone's blobs — " \
                      "this can take minutes)…\n")
      Shell.run("git", "-C", @dir, "checkout", "--quiet")
    end

    # Fetch exactly the pinned ref — or, unpinned, the branch the clone
    # tracks — so FETCH_HEAD is a single unambiguous ref for both the diff
    # and the merge. Submodules are NEVER recursed (--recurse-submodules=no
    # overrides git's on-demand default and any box config): adapters treat
    # a gitlink as an empty dir, and an upstream submodule whose gitlink
    # commit was never pushed failed a whole sync (tamilex, 2026-10-29,
    # "Could not access submodule 'lib'"). Clones need no flag — `git clone`
    # recurses only when asked.
    def git_fetch
      target = @ref || Shell.run("git", "-C", @dir, "rev-parse", "--abbrev-ref", "HEAD").strip
      unless @progress
        Shell.run("git", "-C", @dir, "fetch", "--quiet", NO_SUBMODULES, "origin", target)
        return
      end
      @progress.call("Pulling #{@repo_url}…\n")
      Shell.stream("git", "-C", @dir, "fetch", "--progress", NO_SUBMODULES, "origin", target) do |line|
        @progress.call(line)
      end
    end

    NO_SUBMODULES = "--recurse-submodules=no"
    private_constant :NO_SUBMODULES

    # Files the merge would delete: status D between HEAD and FETCH_HEAD.
    # --find-renames is explicit so a rename always reports as R (not D+A)
    # regardless of the user's diff.renames setting; -z gives raw NUL-split
    # paths (git would otherwise quote non-ASCII names, and corpora have them).
    # A sparse repo scopes the diff to its cone (class note): deletions
    # outside it are not this source's assets.
    def deleted_relpaths
      Shell.run("git", "-C", @dir, "diff", "--name-only", "--diff-filter=D",
                "--find-renames", "-z", "HEAD", "FETCH_HEAD", *cone_pathspec).split("\0")
    end

    # The cone as a diff pathspec. Sparse-checkout patterns admit a
    # root-anchoring "/" ("/lexicon.xml" = the file at the repo root); a
    # diff PATHSPEC does not — a leading slash is fatal there. Same cone,
    # two grammars: translate at this boundary (the ONCOJ owner repro,
    # 2026-07-20).
    def cone_pathspec
      @sparse ? ["--", *@sparse.map { |path| path.delete_prefix("/") }] : []
    end

    # A source may GROW its sparse cone across releases (P34-4: tls added
    # notes/doc + notes/swl for the attestation crosswalk), and clone-time
    # `sparse-checkout set` never re-runs on the pull path — so an existing
    # checkout reconciles here, AFTER the merge (the new paths materialize
    # at the merged head). The re-declared cone is the UNION of the current
    # patterns and the declared ones: widening only, never narrowing — an
    # owner-widened checkout keeps its extra paths, and a FULL checkout
    # (sparse-checkout list exits 128) is never sparsified, because hiding
    # materialized canonical files is the destructive-fetch sin (class
    # note). Same no-cone pattern grammar as sparse_clone, so list output
    # and declared paths compare directly.
    def widen_sparse_cone!
      return unless @sparse
      return unless (current = sparse_cone_patterns)

      union = current | @sparse
      return if union == current

      Shell.run("git", "-C", @dir, "sparse-checkout", "set", "--no-cone", *union)
    end

    # The checkout's current sparse patterns, nil for a full (non-sparse)
    # checkout — `sparse-checkout list` exits 128 there.
    def sparse_cone_patterns
      Shell.run("git", "-C", @dir, "sparse-checkout", "list").split("\n").map(&:strip).reject(&:empty?)
    rescue Shell::Error
      nil
    end

    # -- attic-and-reset (class note) -----------------------------------------

    # HEAD is not an ancestor of FETCH_HEAD: `merge-base --is-ancestor`
    # exits 1 for "no"; any other failure is git's own and propagates.
    def diverged?
      Shell.run("git", "-C", @dir, "merge-base", "--is-ancestor", "HEAD", "FETCH_HEAD")
      false
    rescue Shell::Error => e
      raise unless e.status == 1

      true
    end

    # Decide the reset BEFORE the guard. Identical trees (two tree ids, one
    # call) need no file work at all; otherwise the clean-tree check, the
    # guard's deletion list and the in-place changes the attic must keep.
    def plan_reset!
      head, fetched, head_tree, fetched_tree =
        Shell.run("git", "-C", @dir, "rev-parse", "HEAD", "FETCH_HEAD", "HEAD^{tree}", "FETCH_HEAD^{tree}").split
      @diverged_from = head
      @reset_to = fetched
      @zero_delta = head_tree == fetched_tree
      return if @zero_delta

      refuse_local_modifications!
      @doomed_relpaths = deleted_relpaths
      @changed_relpaths = changed_relpaths
    end

    # A reset --hard would silently discard local edits to tracked files;
    # canonical trees carry none, so any is an anomaly to stop on.
    def refuse_local_modifications!
      dirty = Shell.run("git", "-C", @dir, "status", "--porcelain", "--untracked-files=no")
      return if dirty.strip.empty?

      raise Nabu::FetchError, "#{@dir}: upstream history was rewritten but the tracked tree has local " \
                              "modifications; refusing to reset over them:\n#{dirty}"
    end

    # Files present at HEAD whose bytes (or type) change in place at
    # FETCH_HEAD — scoped to the sparse cone like the deletion diff.
    def changed_relpaths
      Shell.run("git", "-C", @dir, "diff", "--name-only", "--diff-filter=MT", "--no-renames", "-z",
                "HEAD", "FETCH_HEAD", *cone_pathspec).split("\0")
    end

    def complete_reset!
      if @zero_delta
        Shell.run("git", "-C", @dir, "reset", "--soft", "--quiet", "FETCH_HEAD")
      else
        attic_doomed!((@doomed_relpaths | @changed_relpaths).sort)
        Shell.run("git", "-C", @dir, "reset", "--hard", "--quiet", "FETCH_HEAD")
      end
      @reset = Reset.new(from: @diverged_from, to: @reset_to, atticked: @atticked.size, zero_delta: @zero_delta)
      record_reset!
      @progress&.call("upstream history rewritten: reset #{@diverged_from[0, 12]}..#{@reset_to[0, 12]}" \
                      "#{@zero_delta ? ' (identical tree)' : ", atticked #{@atticked.size} file(s)"}\n")
    end

    # Append the event to the attic's reset log (first write creates it).
    def record_reset!
      path = File.join(@attic_dir, RESET_LOG)
      log = File.exist?(path) ? JSON.parse(File.read(path)) : []
      log << { "at" => Time.now.utc.iso8601, "from" => @reset.from, "to" => @reset.to,
               "zero_delta" => @reset.zero_delta, "atticked" => @reset.atticked }
      FileUtils.mkdir_p(@attic_dir)
      File.write(path, JSON.pretty_generate(log))
    end

    # Copy each doomed file into the attic — first copy wins — and record the
    # upstream sha it vanished at in the attic manifest.
    def attic_doomed!(relpaths = @doomed_relpaths)
      relpaths.each do |rel|
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
