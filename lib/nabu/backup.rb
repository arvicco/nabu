# frozen_string_literal: true

require "fileutils"

module Nabu
  # `nabu backup` — the concept's unmet promise made real (architecture §8,
  # P7-2): a file-level rsync snapshot of everything that is NOT re-derivable,
  # to a config-driven external-volume target.
  #
  # == The backup set (the P70 two-folder contract)
  #
  # REQUIRED — the only non-derived data:
  # - canonical/  — the permanent asset, INCLUDING every `.attic/` (files
  #   upstream scrapped that survive nowhere else). File-level rsync copies the
  #   attic for free; a per-slug git mirror would MISS it (the attic is a plain
  #   dir inside the working tree, not a branch), which is exactly why the
  #   promise is "restorable from an rsync backup", not "from the git remotes".
  # - config/ — every decision: the registries, rules/overrides/postures,
  #   lect rulings, grants, creep acceptances, the box profile.
  #
  # NOTHING UNDER db/ SHIPS, EVER (owner ruling 2026-08-16, closing
  # №R-21's convenience tier): everything under db/ regenerates via
  # `nabu rebuild` from the permanent folders — restore is
  # clone-the-repo, rsync the folders back, rebuild. The tier existed as
  # a restore-time shortcut ("a file copy beats hours of rebuild") and
  # hauled 118 GB of derived db into every backup and every drill
  # workspace; two crashed drills drained the boot disk to 100% before
  # the tier's cost was ever stated. A pre-P71 box whose ledger still
  # sits at db/history.sqlite3 (non-derivable history, no other copy) is
  # REFUSED up front — silently excluding the only copy would be the
  # disaster — and told to `nabu migrate-local` first: the ledger is a
  # local artifact and rides inside the local/ section.
  #
  # == The mount-point guard (owner-mandated 2026-07-07)
  #
  # The target is a path under a mounted external volume
  # (`/Volumes/NabuBackup/nabu`). If that volume is NOT mounted, the path is a
  # bare directory on the boot disk, and an unguarded rsync would silently
  # "back up" onto the boot disk — then the real volume, once mounted, is
  # shadowed by that stale directory. Classic, catastrophic. So before any
  # rsync we verify the target lives on a REAL mount point (its volume root's
  # device id differs from the volume root's parent — a genuine mount, not a
  # same-disk directory). `--allow-unmounted` bypasses the guard for
  # deliberately-local targets (the drill, tests, a same-disk scratch copy).
  #
  # == rsync mechanics
  #
  # Each section rsyncs into its OWN subdirectory of the target (canonical/,
  # config/, local/) — `-a --delete` is scoped to those subdirs, NEVER to the
  # volume root, so a stray file beside the target is never touched and the
  # boot-disk footgun stays contained even if the guard is bypassed.
  # `--dry-run` prints the plan and changes nothing.
  #
  # == WAL sidecars (P17-7)
  #
  # The ledger runs journal_mode=WAL (Store, architecture §5), so while a
  # connection is open a `history.sqlite3-wal` beside it holds recently
  # committed transactions the main file does not yet contain (plus a
  # `-shm` index). The local/ DIRECTORY copy carries live sidecars for
  # free and its `--delete` prunes stale ones at the target (restoring an
  # OUTDATED -wal next to a NEWER main file would make SQLite replay old
  # frames over newer data). A backup taken while a writer is
  # mid-transaction can still tear ACROSS files, exactly as it could
  # pre-WAL — the drill (`rake ops:drill`) is the proof either way.
  class Backup
    # Raised when the backup cannot safely proceed (no target configured, or the
    # mount-point guard tripped). Loud on purpose — a refused backup is a
    # feature, a silent one is a disaster.
    class Error < Nabu::Error; end

    # One member of the backup set — always a directory whose CONTENTS
    # rsync (with --delete, scoped to its own target subdir).
    Section = Data.define(:name, :source, :dest)

    # What one section's rsync did (or would do, under --dry-run).
    # status: :ok | :skipped (source absent) | :failed (rsync nonzero).
    SectionResult = Data.define(:name, :source, :dest, :status, :files, :bytes, :duration, :detail) do
      def ok? = status != :failed
      def ran? = status == :ok
    end

    # The whole run. ok? iff no section failed.
    Result = Data.define(:target, :dry_run, :sections, :duration) do
      def ok? = sections.none? { |section| section.status == :failed }
      def failed = sections.select { |section| section.status == :failed }
      def files = sections.sum(&:files)
      def bytes = sections.sum(&:bytes)
    end

    def initialize(config:, target: nil, dry_run: false,
                   allow_unmounted: false, shell: Nabu::Shell, stat: File.method(:stat))
      @config = config
      @target = (target && !target.to_s.strip.empty? ? File.expand_path(target.to_s) : config.backup_target)
      @dry_run = dry_run
      @allow_unmounted = allow_unmounted
      @shell = shell
      @stat = stat
    end

    attr_reader :target

    # Guard, then rsync each section, then summarize. Raises Backup::Error for
    # the up-front refusals (no target / not mounted); a per-section rsync
    # failure is captured in the Result (status :failed) so the report is
    # honest and the CLI can still exit nonzero.
    def run
      if @target.nil?
        raise Error,
              "backup: no target — set backup.target in local/config/settings.yml (the box overlay) or pass --to PATH"
      end

      guard_mount!
      guard_ledger_home!
      started = clock
      results = sections.map { |section| run_section(section) }
      Result.new(target: @target, dry_run: @dry_run, sections: results, duration: clock - started)
    end

    # Exposed for the CLI's pre-flight message and for direct guard tests.
    def mounted?
      MountGuard.mounted?(@target, stat: @stat)
    end

    private

    def guard_mount!
      return if @allow_unmounted
      return if mounted?

      raise Error,
            "backup: volume not mounted — refusing to back up onto the boot disk. " \
            "The target #{@target} is not on a mounted external volume. Mount it, " \
            "or pass --allow-unmounted for a deliberately-local target."
    end

    # A pre-P71 box's ledger sits at db/history.sqlite3 — non-derivable
    # history with no other copy — and NOTHING under db/ ships. Refusing
    # is the only honest move (owner ruling 2026-08-16): a backup that
    # silently omitted the only copy would be the disaster this class
    # exists to prevent.
    def guard_ledger_home!
      return if File.dirname(@config.history_path) == @config.local_dir

      raise Error,
            "backup: the ledger still lives at #{@config.history_path} (pre-P71 layout) and the " \
            "backup ships nothing under db/ — run `nabu migrate-local` to move it into local/, " \
            "then back up."
    end

    def sections
      # P71 — THE THREE-FOLDER CONTRACT (owner rulings 2026-08-10/11):
      # canonical/ (the asset) + config/ (the project definition) +
      # local/ (the instance: owner rulings, grants, profile, the ledger,
      # acquisitions) are the WHOLE permanent set. Everything under db/
      # is derived and NEVER ships (owner ruling 2026-08-16 — class doc);
      # `nabu rebuild` is the restore path for all of it. The ledger
      # rides INSIDE local/ (the dir copy carries its WAL sidecars and
      # prunes stale ones via --delete; guard_ledger_home! refuses a
      # pre-P71 box until it migrates).
      [
        Section.new(name: "canonical", source: @config.canonical_dir, dest: File.join(@target, "canonical")),
        Section.new(name: "config", source: @config.config_dir, dest: File.join(@target, "config")),
        Section.new(name: "local", source: @config.local_dir, dest: File.join(@target, "local")),
        # №R-22 (owner-ruled 2026-08-11): .docs/ — the steering record
        # (decision register, plan docs, surveys) — is owner input with no
        # other copy anywhere. Non-contract (db/ derives from the three
        # folders alone) but backed up by default; absent dir = clean skip.
        Section.new(name: "docs", source: docs_dir, dest: File.join(@target, ".docs"))
      ]
    end

    # The gitignored owner-steering directory at the tree root.
    def docs_dir
      File.expand_path("../.docs", @config.config_dir)
    end

    def run_section(section)
      started = clock
      return skipped(section, started) unless File.exist?(section.source)

      FileUtils.mkdir_p(section.dest) unless @dry_run
      @shell.run(*rsync_argv(section))
      done(section, :ok, started)
    rescue Nabu::Shell::Error => e
      SectionResult.new(name: section.name, source: section.source, dest: section.dest,
                        status: :failed, files: 0, bytes: 0, duration: clock - started,
                        detail: e.stderr.to_s.strip.empty? ? e.message : e.stderr.strip)
    end

    # The section directory's CONTENTS (trailing slash), --delete scoped
    # to its own target subdir.
    def rsync_argv(section)
      argv = ["rsync", "-a", "--delete"]
      argv << "--dry-run" if @dry_run
      argv << File.join(section.source, "") << section.dest
      argv
    end

    def skipped(section, started)
      SectionResult.new(name: section.name, source: section.source, dest: section.dest,
                        status: :skipped, files: 0, bytes: 0, duration: clock - started,
                        detail: "source absent")
    end

    # Summarize what was backed up from the SOURCE side (version-independent —
    # we never parse rsync's output, which differs between openrsync on macOS
    # and GNU rsync). files/bytes describe the snapshot's contents.
    def done(section, status, started)
      files, bytes = measure_tree(section.source)
      SectionResult.new(name: section.name, source: section.source, dest: section.dest,
                        status: status, files: files, bytes: bytes, duration: clock - started, detail: nil)
    end

    def measure_tree(root)
      files = 0
      bytes = 0
      Dir.glob("**/*", File::FNM_DOTMATCH, base: root).each do |rel|
        path = File.join(root, rel)
        next unless File.file?(path)

        files += 1
        bytes += safe_size(path)
      end
      [files, bytes]
    end

    def safe_size(path)
      File.size(path)
    rescue SystemCallError
      0
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Mount-point detection (owner-mandated). Ascends from the target's nearest
    # existing ancestor to its volume root — the first directory whose device id
    # differs from its parent's (a genuine mount point). A target on the boot
    # disk ascends all the way to "/" with no device change, so its volume root
    # IS "/", which is not an acceptable external destination. Injectable +stat+
    # keeps it unit-testable (simulate a mounted volume by stubbing the device
    # comparison — no hdiutil, no /Volumes, in the suite).
    module MountGuard
      module_function

      def mounted?(target, stat: File.method(:stat))
        mount_point(File.expand_path(target), stat) != "/"
      end

      def mount_point(path, stat)
        current = nearest_existing(path)
        current = File.dirname(current) while current != "/" && same_device?(current, File.dirname(current), stat)
        current
      end

      def nearest_existing(path)
        path = File.dirname(path) until File.exist?(path)
        File.realpath(path)
      end

      def same_device?(one, two, stat)
        stat.call(one).dev == stat.call(two).dev
      end
    end
  end
end
