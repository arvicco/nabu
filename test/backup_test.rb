# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu backup` (P7-2). Backups run rsync through Nabu::Shell against tmp
# targets — never a real /Volumes mount, never hdiutil. The mount-point guard
# is exercised two ways: a real same-device tmp target (guard trips) and a
# stubbed stat function that simulates a genuine mounted volume (guard passes).
class BackupTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-backup-src")
    @target = Dir.mktmpdir("nabu-backup-dst")
    build_source_tree
  end

  def teardown
    FileUtils.remove_entry(@root)
    FileUtils.rm_rf(@target)
  end

  # -- the full backup set --------------------------------------------------

  def test_backs_up_canonical_attic_ledger_config_and_derived
    result = backup(allow_unmounted: true).run

    assert_predicate result, :ok?
    # canonical/, including the .attic file that exists nowhere else.
    assert_path_exists File.join(@target, "canonical", "corpus", "one.txt")
    assert_path_exists File.join(@target, "canonical", "corpus", ".attic", "gone.txt")
    # the ledger (the only copy) + config/ (registry).
    assert_path_exists File.join(@target, "db", "history.sqlite3")
    assert_path_exists File.join(@target, "config", "sources.yml")
    # derived dbs on by default.
    assert_path_exists File.join(@target, "db", "catalog.sqlite3")
    assert_path_exists File.join(@target, "db", "fulltext.sqlite3")

    names = result.sections.map(&:name)
    assert_equal %w[canonical config ledger catalog fulltext], names
  end

  def test_skip_derived_omits_the_derived_dbs
    result = backup(allow_unmounted: true, skip_derived: true).run

    assert_predicate result, :ok?
    assert_path_exists File.join(@target, "db", "history.sqlite3")
    refute_path_exists File.join(@target, "db", "catalog.sqlite3")
    refute_path_exists File.join(@target, "db", "fulltext.sqlite3")
    refute_includes result.sections.map(&:name), "catalog"
  end

  # -- --delete scoping -----------------------------------------------------

  def test_delete_propagates_within_the_subdir_and_touches_nothing_outside
    # A sentinel BESIDE the nabu target (in the volume root) must survive — we
    # never --delete at the volume root, only inside each section subdir.
    sentinel = File.join(@target, "unrelated.keep")
    File.write(sentinel, "precious")

    backup(allow_unmounted: true).run
    assert_path_exists File.join(@target, "canonical", "corpus", "two.txt")

    # Remove a source file, back up again: it vanishes from the target subdir.
    FileUtils.rm(File.join(@root, "canonical", "corpus", "two.txt"))
    backup(allow_unmounted: true).run

    refute_path_exists File.join(@target, "canonical", "corpus", "two.txt")
    assert_path_exists File.join(@target, "canonical", "corpus", "one.txt")
    assert_path_exists sentinel, "a file beside the target must never be swept"
    assert_equal "precious", File.read(sentinel)
  end

  # -- dry-run --------------------------------------------------------------

  def test_dry_run_changes_nothing
    before = target_snapshot

    result = backup(allow_unmounted: true, dry_run: true).run

    assert_predicate result, :ok?
    assert result.dry_run
    assert_equal before, target_snapshot, "dry-run must not write to the target"
    refute_path_exists File.join(@target, "canonical", "corpus", "one.txt")
  end

  # -- the mount-point guard ------------------------------------------------

  def test_guard_refuses_a_same_device_target_without_override
    error = assert_raises(Nabu::Backup::Error) { backup(allow_unmounted: false).run }
    assert_match(/volume not mounted/i, error.message)
    # Nothing was written — the refusal is up front, before any rsync.
    refute_path_exists File.join(@target, "canonical")
  end

  def test_allow_unmounted_bypasses_the_guard
    assert_predicate backup(allow_unmounted: true).run, :ok?
  end

  def test_a_stubbed_mounted_volume_passes_the_guard
    # Simulate the target's volume dir being a genuine mount point: its device
    # id differs from its parent's. No override needed — the guard sees a real
    # mount. (This is how a real /Volumes/NabuBackup looks vs its /Volumes parent.)
    result = Nabu::Backup.new(config: config, target: @target, allow_unmounted: false,
                              stat: stub_stat(@target => 4242)).run
    assert_predicate result, :ok?
  end

  def test_mount_guard_reports_boot_disk_as_unmounted
    refute Nabu::Backup::MountGuard.mounted?(@target),
           "a plain tmp dir is on the boot disk — not a mounted volume"
  end

  # -- no target ------------------------------------------------------------

  def test_missing_target_errors_loudly
    error = assert_raises(Nabu::Backup::Error) do
      Nabu::Backup.new(config: config, target: nil, allow_unmounted: true).run
    end
    assert_match(/no target/i, error.message)
  end

  def test_config_target_is_used_when_no_override
    cfg = config(backup_target: @target)
    result = Nabu::Backup.new(config: cfg, allow_unmounted: true).run
    assert_equal @target, result.target
    assert_path_exists File.join(@target, "canonical", "corpus", "one.txt")
  end

  # -- a failing section ----------------------------------------------------

  def test_one_failing_section_makes_the_run_nonzero_but_reports_honestly
    shell = FailingShell.new(fail_when: ->(argv) { argv.any? { |a| a.include?("config") } })
    result = Nabu::Backup.new(config: config, target: @target, allow_unmounted: true, shell: shell).run

    refute_predicate result, :ok?
    assert_equal %w[config], result.failed.map(&:name)
    # The other sections still ran and are reported.
    canonical = result.sections.find { |s| s.name == "canonical" }
    assert_predicate canonical, :ran?
  end

  # -- helpers --------------------------------------------------------------

  private

  # A Shell stand-in that fails rsync for sections matching a predicate.
  class FailingShell
    def initialize(fail_when:)
      @fail_when = fail_when
    end

    def run(*argv)
      raise Nabu::Shell::Error.new("boom", status: 23, stderr: "rsync: permission denied") if @fail_when.call(argv)

      Nabu::Shell.run(*argv)
    end
  end

  def backup(**)
    Nabu::Backup.new(config: config, target: @target, **)
  end

  def config(backup_target: nil)
    Nabu::Config.new(
      canonical_dir: File.join(@root, "canonical"),
      db_dir: File.join(@root, "db"),
      sources_path: File.join(@root, "config", "sources.yml"),
      config_path: File.join(@root, "config", "nabu.yml"),
      backup_target: backup_target
    )
  end

  # A stat function that overrides .dev for named realpaths (to simulate a
  # mount boundary), falling back to the real File.stat elsewhere.
  def stub_stat(overrides)
    resolved = overrides.transform_keys { |path| File.realpath(path) }
    lambda do |path|
      dev = resolved.fetch(File.realpath(path)) { File.stat(path).dev }
      Struct.new(:dev).new(dev)
    end
  end

  def build_source_tree
    corpus = File.join(@root, "canonical", "corpus")
    FileUtils.mkdir_p(File.join(corpus, ".attic"))
    File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\n")
    File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
    File.write(File.join(corpus, ".attic", "gone.txt"), "Scrapped\nτις\n")

    db = File.join(@root, "db")
    FileUtils.mkdir_p(db)
    %w[history.sqlite3 catalog.sqlite3 fulltext.sqlite3].each do |name|
      File.write(File.join(db, name), "SQLite format 3\0#{name}")
    end

    cfg = File.join(@root, "config")
    FileUtils.mkdir_p(cfg)
    File.write(File.join(cfg, "sources.yml"), "corpus:\n  adapter: TestAdapter\n")
    File.write(File.join(cfg, "nabu.yml"), "# nabu config\n")
  end

  # Every file under the target, with content, so a dry-run's no-op is provable.
  def target_snapshot
    Dir.glob("**/*", File::FNM_DOTMATCH, base: @target)
       .reject { |rel| rel.end_with?(".", "..") }
       .map { |rel| File.join(@target, rel) }
       .select { |path| File.file?(path) }
       .to_h { |path| [path, File.read(path)] }
  end
end
