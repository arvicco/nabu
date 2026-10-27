# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::ModuleCensus — the seam-census hook a kind: module row reports
# through instead of the document counters it holds zero of by invariant.
# A module adapter exposes `self.module_census(read)` (nil by default);
# nabu-lects counts its registry through Nabu::Lects.census. The same
# counter runs over the working tree and over an OLD git blob, so a sync
# can print the delta. No network: the git repos are local tmpdirs.
class ModuleCensusTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")

  def setup
    @root = Dir.mktmpdir("nabu-module-census")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_lects_census_counts_the_registry_from_strings
    census = Nabu::Lects.census(lects_yaml: File.read(File.join(FIXTURES, "lects.yml")),
                                codemap_yaml: File.read(File.join(FIXTURES, "codemap.yml")))
    assert_equal 269, census.anchors
    assert_equal 143, census.stages
    assert_equal 27, census.varieties
    assert_equal 180, census.codemap
  end

  def test_the_nabu_lects_hook_reads_both_files
    counts = Nabu::ModuleCensus.at_dir(Nabu::Adapters::NabuLects, FIXTURES)
    pairs = counts.map { |count| [count.label, count.count] }
    assert_equal [["anchors", 269], ["stages", 143], ["varieties", 27], ["codemap rows", 180]], pairs
  end

  def test_a_census_less_module_reports_nil_never_fake_zeros
    assert_nil Nabu::ModuleCensus.at_dir(Nabu::Adapters::NabuPlaces, FIXTURES)
    assert_nil Nabu::ModuleCensus.at_dir(Nabu::Adapters::Ucd, FIXTURES)
  end

  def test_an_absent_registry_tree_reports_nil
    assert_nil Nabu::ModuleCensus.at_dir(Nabu::Adapters::NabuLects, File.join(@root, "absent"))
  end

  def test_render_carries_nonzero_deltas_only
    now = counts(anchors: 248, stages: 125, varieties: 32, codemap: 157)
    before = counts(anchors: 246, stages: 125, varieties: 27, codemap: 158)
    assert_equal "248 anchors (+2) · 125 stages · 32 varieties (+5) · 157 codemap rows (-1)",
                 Nabu::ModuleCensus.render(now, previous: before)
    assert_equal "248 anchors · 125 stages · 32 varieties · 157 codemap rows", Nabu::ModuleCensus.render(now)
  end

  def test_summary_falls_back_to_the_pin_for_a_census_less_module
    assert_equal "module @ 0123456789ab", Nabu::ModuleCensus.summary(nil, pin: "0123456789abcdef")
    assert_equal "module (not synced)", Nabu::ModuleCensus.summary(nil, pin: nil)
    assert_equal "246 anchors · 125 stages · 27 varieties · 157 codemap rows",
                 Nabu::ModuleCensus.summary(counts(anchors: 246, stages: 125, varieties: 27, codemap: 157),
                                            pin: "0123456789abcdef")
  end

  # --- the sync delta over a real (local) git history --------------------

  def test_delta_reads_the_old_blob_and_the_changed_files
    dir = seed_repo
    before = git(dir, "rev-parse", "HEAD")
    add_anchor(dir)
    after = git(dir, "rev-parse", "HEAD")

    delta = Nabu::ModuleCensus.delta(adapter_class: Nabu::Adapters::NabuLects, dir: dir,
                                     before: before, after: after, fetched: true)

    assert_equal before, delta.before
    assert_equal after, delta.after
    assert_equal ["lects.yml"], delta.changed
    assert_equal 270, delta.census.first.count
    assert_equal 269, delta.previous_census.first.count
    assert delta.moved?
  end

  def test_an_unmoved_delta_carries_no_previous_census_and_no_changes
    dir = seed_repo
    head = git(dir, "rev-parse", "HEAD")

    delta = Nabu::ModuleCensus.delta(adapter_class: Nabu::Adapters::NabuLects, dir: dir,
                                     before: head, after: head, fetched: true)

    refute delta.moved?
    assert_nil delta.changed
    assert_nil delta.previous_census
    assert_equal 269, delta.census.first.count
  end

  def test_head_reads_only_a_repo_of_its_own
    dir = seed_repo
    assert_equal git(dir, "rev-parse", "HEAD"), Nabu::ModuleCensus.head(dir)
    plain = File.join(dir, "sub")
    FileUtils.mkdir_p(plain)
    assert_nil Nabu::ModuleCensus.head(plain), "never walk up into an enclosing repo"
    assert_nil Nabu::ModuleCensus.head(File.join(@root, "absent"))
  end

  # The resettable-pin lesson (caught live 2026-10-18): the catalog's
  # last_sync_sha resets at rebuild, so a nil pin consults the tree
  # itself — its own git HEAD, then bare heldness — before ever
  # claiming "not synced".
  def test_summary_falls_back_to_the_trees_own_head_then_heldness
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "spine.txt"), "held content")
      assert_equal "module (held)", Nabu::ModuleCensus.summary(nil, pin: nil, workdir: dir)
    end
    Dir.mktmpdir do |dir|
      assert_equal "module (not synced)", Nabu::ModuleCensus.summary(nil, pin: nil, workdir: dir)
    end
  end

  private

  def counts(anchors:, stages:, varieties:, codemap:)
    [["anchors", anchors], ["stages", stages], ["varieties", varieties], ["codemap rows", codemap]]
      .map { |label, count| Nabu::ModuleCensus::Count.new(label: label, count: count) }
  end

  def seed_repo
    dir = File.join(@root, "nabu-lects")
    FileUtils.mkdir_p(dir)
    FileUtils.cp(File.join(FIXTURES, "lects.yml"), dir)
    FileUtils.cp(File.join(FIXTURES, "codemap.yml"), dir)
    git(dir, "init", "-q")
    git(dir, "add", ".")
    commit(dir, "seed")
    dir
  end

  def add_anchor(dir)
    path = File.join(dir, "lects.yml")
    File.write(path, File.read(path).sub(/^scripts:/, "  zzx:\n    name: Test anchor\n\nscripts:"))
    git(dir, "add", ".")
    commit(dir, "mint zzx")
  end

  def commit(dir, message)
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
