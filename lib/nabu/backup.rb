# frozen_string_literal: true

require "fileutils"

module Nabu
  # `nabu backup` — the concept's unmet promise made real (architecture §8,
  # P7-2): a file-level rsync snapshot of everything that is NOT re-derivable,
  # to a config-driven external-volume target.
  #
  # == The backup set (everything canonical/ + the ledger + config)
  #
  # - canonical/  — the permanent asset, INCLUDING every `.attic/` (files
  #   upstream scrapped that survive nowhere else). File-level rsync copies the
  #   attic for free; a per-slug git mirror would MISS it (the attic is a plain
  #   dir inside the working tree, not a branch), which is exactly why the
  #   promise is "restorable from an rsync backup", not "from the git remotes".
  # - db/history.sqlite3 — the ledger (P7-1): run history, sync pins, license
  #   baselines, durable revisions. The ONLY copy; disposable it is not.
  # - config/ — nabu.yml + sources.yml (the registry that says what the corpus
  #   even is).
  # - the derived dbs (catalog + fulltext) — included by DEFAULT (a cheap file
  #   copy beats an hour of `nabu rebuild` on restore); `--skip-derived` omits
  #   them (canonical/ + a rebuild reconstitutes them exactly).
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
  # config/, db/) — `-a --delete` is scoped to those subdirs, NEVER to the
  # volume root, so a stray file beside the target is never touched and the
  # boot-disk footgun stays contained even if the guard is bypassed. Directory
  # sections use `--delete` (an upstream deletion propagates); the db files copy
  # without `--delete` (a single-file rsync must not sweep its sibling dbs).
  # `--dry-run` prints the plan and changes nothing.
  class Backup
    # Raised when the backup cannot safely proceed (no target configured, or the
    # mount-point guard tripped). Loud on purpose — a refused backup is a
    # feature, a silent one is a disaster.
    class Error < Nabu::Error; end

    # One member of the backup set. +delete+ scopes `rsync --delete` to this
    # subdir; +directory+ distinguishes a contents-copy (canonical/, config/)
    # from a single-file copy (a db).
    Section = Data.define(:name, :source, :dest, :delete, :directory)

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

    def initialize(config:, target: nil, skip_derived: false, dry_run: false,
                   allow_unmounted: false, shell: Nabu::Shell, stat: File.method(:stat))
      @config = config
      @target = (target && !target.to_s.strip.empty? ? File.expand_path(target.to_s) : config.backup_target)
      @skip_derived = skip_derived
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
      raise Error, "backup: no target — set backup.target in config/nabu.yml or pass --to PATH" if @target.nil?

      guard_mount!
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

    def sections
      list = [
        dir_section("canonical", @config.canonical_dir, File.join(@target, "canonical")),
        dir_section("config", @config.config_dir, File.join(@target, "config")),
        file_section("ledger", @config.history_path)
      ]
      unless @skip_derived
        list << file_section("catalog", @config.catalog_path)
        list << file_section("fulltext", @config.fulltext_path)
      end
      list
    end

    def dir_section(name, source, dest)
      Section.new(name: name, source: source, dest: dest, delete: true, directory: true)
    end

    # db files all land in <target>/db/; single-file copies, no --delete.
    def file_section(name, source)
      Section.new(name: name, source: source, dest: File.join(@target, "db"), delete: false, directory: false)
    end

    def run_section(section)
      started = clock
      return skipped(section, started) unless File.exist?(section.source)

      mkdir_dest(section) unless @dry_run
      @shell.run(*rsync_argv(section))
      done(section, :ok, started)
    rescue Nabu::Shell::Error => e
      SectionResult.new(name: section.name, source: section.source, dest: section.dest,
                        status: :failed, files: 0, bytes: 0, duration: clock - started,
                        detail: e.stderr.to_s.strip.empty? ? e.message : e.stderr.strip)
    end

    def rsync_argv(section)
      argv = ["rsync", "-a"]
      argv << "--delete" if section.delete
      argv << "--dry-run" if @dry_run
      argv << rsync_source(section) << section.dest
      argv
    end

    # A directory section copies its CONTENTS (trailing slash); a file section
    # copies the file itself into the db dir.
    def rsync_source(section)
      section.directory ? File.join(section.source, "") : section.source
    end

    def mkdir_dest(section)
      FileUtils.mkdir_p(section.dest)
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
      files, bytes = measure(section)
      SectionResult.new(name: section.name, source: section.source, dest: section.dest,
                        status: status, files: files, bytes: bytes, duration: clock - started, detail: nil)
    end

    def measure(section)
      if section.directory
        measure_tree(section.source)
      else
        [1, safe_size(section.source)]
      end
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
