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
  # CONVENIENCE (default-on, `--skip-derived` omits): the derived dbs
  # (catalog + fulltext + lects) — a cheap file copy beats hours of
  # `nabu rebuild` on restore — and the ledger (db/history.sqlite3),
  # operational LOG whose loss costs history and guard baselines, never
  # library data (№R-21; restore.md names the consequences).
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
  #
  # == WAL sidecars (P17-7)
  #
  # The dbs run journal_mode=WAL (Store, architecture §5), so while any
  # connection is open a `<db>-wal` holds recently committed transactions the
  # main file does not yet contain (plus a `<db>-shm` index). A db file
  # section therefore copies its LIVE sidecars along with the db — the main
  # file alone would be a stale (or, mid-write, torn) snapshot — and prunes
  # sidecars at the target whose source counterpart is gone (checkpointed
  # away): restoring an OUTDATED -wal next to a NEWER main file would make
  # SQLite replay old frames over newer data. Usually (idle corpus, nightly
  # timing) the -wal is checkpointed away and this is a no-op; a backup taken
  # while a writer is mid-transaction can still tear ACROSS files, exactly as
  # it could pre-WAL — the drill (`rake ops:drill`) is the proof either way.
  class Backup
    # Raised when the backup cannot safely proceed (no target configured, or the
    # mount-point guard tripped). Loud on purpose — a refused backup is a
    # feature, a silent one is a disaster.
    class Error < Nabu::Error; end

    # One member of the backup set. +delete+ scopes `rsync --delete` to this
    # subdir; +directory+ distinguishes a contents-copy (canonical/, config/)
    # from a single-file copy (a db).
    Section = Data.define(:name, :source, :dest, :delete, :directory)

    # A WAL db's sidecar suffixes (class doc above): copied while live,
    # pruned at the target once the source checkpoints them away.
    SIDECAR_SUFFIXES = ["-wal", "-shm"].freeze

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
      # P71 — THE THREE-FOLDER CONTRACT (owner rulings 2026-08-10/11):
      # canonical/ (the asset) + config/ (the project definition) +
      # local/ (the instance: owner rulings, grants, profile, the ledger,
      # acquisitions) are the WHOLE permanent set. Everything under db/
      # is derived (the lect journal and links re-mint at rebuild). The
      # optional derived sections remain a convenience (restoring a 75 GB
      # catalog beats hours of rebuild) — never a necessity. The ledger
      # rides INSIDE local/ (the dir copy carries its WAL sidecars and
      # prunes stale ones via --delete); the file section survives only
      # for a pre-P71 box whose ledger still sits under db/.
      list = [
        dir_section("canonical", @config.canonical_dir, File.join(@target, "canonical")),
        dir_section("config", @config.config_dir, File.join(@target, "config")),
        dir_section("local", @config.local_dir, File.join(@target, "local")),
        # №R-22 (owner-ruled 2026-08-11): .docs/ — the steering record
        # (decision register, plan docs, surveys) — is owner input with no
        # other copy anywhere. Non-contract (db/ derives from the three
        # folders alone) but backed up by default; absent dir = clean skip.
        dir_section("docs", docs_dir, File.join(@target, ".docs"))
      ]
      unless @skip_derived
        list << file_section("catalog", @config.catalog_path)
        list << file_section("fulltext", @config.fulltext_path)
        list << file_section("lects", @config.lects_journal_path)
        list << file_section("links", @config.links_path)
        list << file_section("ledger", @config.history_path) unless ledger_home?
      end
      list
    end

    # The gitignored owner-steering directory at the tree root.
    def docs_dir
      File.expand_path("../.docs", @config.config_dir)
    end

    # Has the ledger moved to its local/ home? (Then the local dir section
    # carries it and a db/-style file section would be a stale duplicate.)
    def ledger_home?
      File.dirname(@config.history_path) == @config.local_dir
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
      prune_stale_sidecars(section) unless @dry_run
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
      argv.concat(rsync_sources(section)) << section.dest
      argv
    end

    # A directory section copies its CONTENTS (trailing slash); a file section
    # copies the file itself into the db dir, plus any live WAL sidecars
    # (class doc: the -wal holds commits the main file lacks).
    def rsync_sources(section)
      return [File.join(section.source, "")] if section.directory

      [section.source, *sidecars(section.source)]
    end

    # The WAL sidecars of +path+ that exist right now.
    def sidecars(path)
      SIDECAR_SUFFIXES.map { |suffix| "#{path}#{suffix}" }.select { |sidecar| File.exist?(sidecar) }
    end

    # File sections copy without --delete (must not sweep sibling dbs), so a
    # sidecar an EARLIER backup copied lingers at the target after the source
    # checkpoints it away — and a stale -wal would be replayed over the newer
    # main file on restore. Prune exactly those two names, nothing else.
    def prune_stale_sidecars(section)
      return if section.directory

      SIDECAR_SUFFIXES.each do |suffix|
        next if File.exist?("#{section.source}#{suffix}")

        FileUtils.rm_f(File.join(section.dest, "#{File.basename(section.source)}#{suffix}"))
      end
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
      return measure_tree(section.source) if section.directory

      files = [section.source, *sidecars(section.source)]
      [files.size, files.sum { |path| safe_size(path) }]
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
