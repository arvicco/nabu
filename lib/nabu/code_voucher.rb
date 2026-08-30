# frozen_string_literal: true

require "time"

module Nabu
  # P89-1 (№R-54 (b)): can git vouch that a set of code files carries the
  # same bytes it did at a given moment? The `--trust-derivations` bridge
  # asks this per source before re-stamping WITHOUT replay: a yes means the
  # source's parser closure provably predates its stamp, so the only thing
  # that drifted is shared-core code the owner attests is content-neutral.
  #
  # Refusal paths (each an under-rebuild guard, each answered with a quiet
  # false so the caller falls through to an honest replay):
  # - the watched tree (lib/nabu/adapters by default) has uncommitted edits
  #   or untracked files — HEAD does not name the bytes on disk;
  # - a file was DELETED under the watched tree after the moment — deletions
  #   change closure membership invisibly (the per-file check below cannot
  #   see a file that is gone), so any post-stamp deletion refuses;
  # - a queried file's last commit is newer than the moment, or the file was
  #   never committed at all.
  # Git failures (not a repo, git missing) also read as false — trust is an
  # optimization, never a requirement.
  class CodeVoucher
    def initialize(repo_root: File.expand_path("../..", __dir__), watch_dir: nil)
      @repo_root = repo_root
      @watch_dir = watch_dir || File.join(repo_root, "lib", "nabu", "adapters")
      @commit_times = {}
    end

    # +files+ are absolute paths inside the repo; +since+ a Time (or its
    # string form, as SQLite hands timestamps back).
    def vouches?(files:, since:)
      moment = since.is_a?(Time) ? since : Time.parse(since.to_s)
      return false unless clean?
      return false if deleted_after?(moment)

      files.all? { |file| (time = last_commit_time(file)) && time <= moment }
    rescue Shell::Error, ArgumentError
      false
    end

    # PUBLIC preflight (2026-08-30, after a dirty tree silently disabled
    # trust for a whole multi-hour run): can this voucher vouch for
    # ANYTHING right now? False when the watched tree has uncommitted
    # changes — the caller should say so loudly BEFORE hours of replay.
    def able?
      clean?
    rescue Shell::Error
      false
    end

    private

    def clean?
      Shell.run("git", "-C", @repo_root, "status", "--porcelain", "--", @watch_dir).strip.empty?
    end

    # Newest-first log of deletions under the watched tree; the first line
    # is the latest deletion, if any ever happened.
    def deleted_after?(moment)
      latest = Shell.run("git", "-C", @repo_root, "log", "--diff-filter=D",
                         "--format=%cI", "--", @watch_dir).lines.first&.strip
      !latest.nil? && Time.parse(latest) > moment
    end

    def last_commit_time(file)
      @commit_times.fetch(file) do
        out = Shell.run("git", "-C", @repo_root, "log", "-1", "--format=%cI", "--", file).strip
        @commit_times[file] = out.empty? ? nil : Time.parse(out)
      end
    end
  end
end
