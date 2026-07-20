# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::DerivationFingerprint (P36-1): the honest per-source identity behind
# `rebuild --incremental`. Four inputs (canonical bytes, parser/pipeline code,
# fold rules, migration level) plus the entry's derivation-shaping registry
# flags. The cardinal rule under test: anything that could change derived rows
# must move the fingerprint; a weak identity must read as "never skip".
class DerivationFingerprintTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-fingerprint")
    @canonical = File.join(@root, "canonical")
    FileUtils.mkdir_p(@canonical)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- canonical identity: plain (non-git) trees ---------------------------

  def test_plain_tree_identity_tracks_content_not_mtime
    dir = write_tree("corpus", "one.txt" => "Iliad\nμῆνιν\n")
    before = identity(dir)
    refute_nil before

    # mtime-only churn must not move the identity (content is the identity).
    FileUtils.touch(File.join(dir, "one.txt"), mtime: Time.now + 3600)
    assert_equal before, identity(dir)

    # One changed byte must move it.
    File.write(File.join(dir, "one.txt"), "Iliad\nμῆνιν!\n")
    refute_equal before, identity(dir)
  end

  def test_plain_tree_identity_sees_added_and_renamed_files
    dir = write_tree("corpus", "one.txt" => "Iliad\nμῆνιν\n")
    before = identity(dir)

    File.write(File.join(dir, "two.txt"), "Odyssey\nἄνδρα\n")
    added = identity(dir)
    refute_equal before, added

    FileUtils.mv(File.join(dir, "two.txt"), File.join(dir, "renamed.txt"))
    refute_equal added, identity(dir)
  end

  def test_missing_dir_identity_is_weak
    assert_nil identity(File.join(@canonical, "absent"))
  end

  # -- canonical identity: git-backed trees --------------------------------

  def test_git_tree_identity_follows_head
    dir = git_tree("corpus", "one.txt" => "alpha\n")
    before = identity(dir)
    refute_nil before

    # Identity is HEAD-based: a new commit moves it.
    File.write(File.join(dir, "one.txt"), "beta\n")
    git(dir, "add", ".")
    git_commit(dir, "update")
    refute_equal before, identity(dir)
  end

  def test_git_tree_with_local_modifications_is_weak
    dir = git_tree("corpus", "one.txt" => "alpha\n")
    refute_nil identity(dir)

    # An uncommitted edit means HEAD no longer names the bytes on disk:
    # the identity is WEAK (nil) and the source must never be skipped.
    File.write(File.join(dir, "one.txt"), "tampered\n")
    assert_nil identity(dir)
  end

  def test_git_attic_content_participates_in_the_identity
    dir = git_tree("corpus", "one.txt" => "alpha\n")
    # Mimic GitFetch's attic: excluded from git's sight, still canonical data.
    File.write(File.join(dir, ".git", "info", "exclude"), "/.attic/\n")
    attic = File.join(dir, ".attic")
    FileUtils.mkdir_p(attic)
    File.write(File.join(attic, "retired.txt"), "gone upstream\n")
    with_attic = identity(dir)
    refute_nil with_attic, "an excluded attic must not read as a dirty tree"
    refute_equal identity_without(dir, attic), with_attic

    File.write(File.join(attic, "retired.txt"), "gone upstream, edited\n")
    refute_equal with_attic, identity(dir)
  end

  def test_nested_git_repos_are_each_identified_by_head
    parent = File.join(@canonical, "kanripo-style")
    repo_a = git_tree("kanripo-style/KR1a0001", "a.txt" => "one\n")
    git_tree("kanripo-style/KR1a0002", "b.txt" => "two\n")
    before = identity(parent)
    refute_nil before

    File.write(File.join(repo_a, "a.txt"), "changed\n")
    git(repo_a, "add", ".")
    git_commit(repo_a, "update")
    refute_equal before, identity(parent)
  end

  # -- parser digest: per-family closure -----------------------------------

  def test_parser_closure_reaches_the_family_a_bare_constant_reference_names
    # Perseus references EpidocParser WITHOUT require_relative — the closure
    # must still see it (the under-rebuild sin lives exactly here).
    files = computer.parser_files(entry(adapter: "Nabu::Adapters::Perseus"))
    assert_includes files, adapter_path("perseus.rb")
    assert_includes files, adapter_path("epidoc_parser.rb")
    refute_includes files, adapter_path("tls_xml_parser.rb")
  end

  def test_parser_closure_is_per_family_not_whole_directory
    files = computer.parser_files(entry(adapter: "Nabu::Adapters::Tls"))
    assert_includes files, adapter_path("tls.rb")
    assert_includes files, adapter_path("tls_xml_parser.rb")
    refute_includes files, adapter_path("epidoc_parser.rb")
  end

  def test_parser_closure_follows_subclassing
    # First1kGreek subclasses Perseus: its closure must include perseus.rb
    # and the epidoc family behind it.
    files = computer.parser_files(entry(adapter: "Nabu::Adapters::First1kGreek"))
    assert_includes files, adapter_path("first1k_greek.rb")
    assert_includes files, adapter_path("perseus.rb")
    assert_includes files, adapter_path("epidoc_parser.rb")
  end

  # -- the other inputs ----------------------------------------------------

  def test_migration_level_is_the_latest_migration_number
    expected = Dir[File.join(Nabu::Store::MIGRATIONS_DIR, "*.rb")]
               .map { |file| File.basename(file).to_i }.max
    assert_equal expected, Nabu::DerivationFingerprint.migration_level
  end

  def test_registry_flags_move_the_fingerprint
    write_tree("corpus", "one.txt" => "Iliad\nμῆνιν\n")
    plain = computer.for_source(entry)
    flagged = computer.for_source(entry(translations: true))
    refute_equal plain.combined, flagged.combined
    assert_equal :config, flagged.drift_against(stamp_row(plain))
  end

  def test_fold_digest_moves_the_fingerprint
    write_tree("corpus", "one.txt" => "Iliad\nμῆνιν\n")
    before = computer.for_source(entry)
    after = with_fold_digest("folds-changed") do
      computer(fresh: true).for_source(entry)
    end
    refute_equal before.combined, after.combined
    assert_equal :fold, after.drift_against(stamp_row(before))
  end

  def test_weak_identity_has_no_combined_fingerprint
    dir = git_tree("corpus", "one.txt" => "alpha\n")
    File.write(File.join(dir, "one.txt"), "tampered\n")
    fingerprint = computer.for_source(entry)
    assert_predicate fingerprint, :weak?
    assert_nil fingerprint.combined
  end

  def test_drift_against_names_the_changed_component
    write_tree("corpus", "one.txt" => "Iliad\nμῆνιν\n")
    before = computer.for_source(entry)
    assert_nil before.drift_against(stamp_row(before))

    File.write(File.join(@canonical, "corpus", "one.txt"), "Iliad\nμῆνιν!\n")
    after = computer(fresh: true).for_source(entry)
    assert_equal :canonical, after.drift_against(stamp_row(before))
    assert_equal :unstamped, after.drift_against(nil)
  end

  # -- helpers -------------------------------------------------------------

  private

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: File.join(@root, "db"),
      sources_path: File.join(@root, "sources.yml"), config_path: "(test)"
    )
  end

  def computer(fresh: false)
    @computer = nil if fresh
    @computer ||= Nabu::DerivationFingerprint.new(config: config)
  end

  def entry(slug: "corpus", adapter: "TestAdapter", **flags)
    Nabu::SourceRegistry::Entry.new(
      slug: slug, adapter_class_name: adapter, enabled: true, sync_policy: "manual", **flags
    )
  end

  def identity(dir)
    Nabu::DerivationFingerprint.canonical_identity(dir)
  end

  # Temporarily replace the fold-rules digest (no minitest/mock in this
  # suite): define, yield, restore.
  def with_fold_digest(value)
    singleton = Nabu::DerivationFingerprint.singleton_class
    original = Nabu::DerivationFingerprint.method(:fold_digest)
    singleton.define_method(:fold_digest) { value }
    yield
  ensure
    singleton.define_method(:fold_digest, original)
  end

  # Identity of +dir+ as it would read without +subtree+ (computed by moving
  # it aside; restored afterwards).
  def identity_without(dir, subtree)
    aside = File.join(@root, "aside")
    FileUtils.mv(subtree, aside)
    identity(dir)
  ensure
    FileUtils.mv(aside, subtree)
  end

  def stamp_row(fingerprint)
    {
      fingerprint: fingerprint.combined,
      canonical_identity: fingerprint.canonical_identity,
      parser_digest: fingerprint.parser_digest,
      fold_digest: fingerprint.fold_digest,
      migration_level: fingerprint.migration_level,
      config_json: fingerprint.config_json
    }
  end

  def adapter_path(basename)
    File.expand_path(File.join("..", "lib", "nabu", "adapters", basename), __dir__)
  end

  def write_tree(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
    dir
  end

  def git_tree(slug, files)
    dir = write_tree(slug, files)
    git(dir, "init", "--quiet")
    git(dir, "add", ".")
    git_commit(dir, "seed")
    dir
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *)
  end

  def git_commit(dir, message)
    git(dir, "-c", "user.email=test@nabu", "-c", "user.name=test",
        "commit", "--quiet", "-m", message)
  end
end
