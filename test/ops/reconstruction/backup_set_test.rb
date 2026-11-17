# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "nabu/ops/reconstruction/backup_set"

# `nabu reconstruct backupset`: the combined restore path — the computed
# set of expensive-to-reacquire paths (the instance, vectors, rail trees,
# extra-huge trees, attic subtrees) with the re-sync remainder summed.
# Planted ledger, registry, verdicts and trees; no box data, no du (sizes
# off except the one sizing test).
class ReconstructionBackupSetTest < Minitest::Test
  BackupSet = Nabu::Ops::Reconstruction::BackupSet
  Verdict = Nabu::Ops::Reconstruction::SourceClass::Verdict

  def entry(slug, kind: "source", wired: true)
    Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: "PlainAdapter", wired: wired,
                                    sync_policy: "manual", kind: kind)
  end

  def verdict(slug, klass, attic: false)
    Verdict.new(slug: slug, klass: klass, computed: klass, attic: attic)
  end

  def setup
    @tmp = Dir.mktmpdir("nabu-backupset")
    @canonical = File.join(@tmp, "canonical")
    @local = File.join(@tmp, "local")
    @vectors = File.join(@tmp, "vectors.sqlite3")
    FileUtils.mkdir_p(@local)
    File.write(@vectors, "v")
    %w[alpha huge rail gamma byhand slowhand].each { |slug| FileUtils.mkdir_p(File.join(@canonical, slug)) }
    FileUtils.mkdir_p(File.join(@canonical, "gamma", ".attic"))
    FileUtils.mkdir_p(File.join(@canonical, "huge", ".attic"))
    FileUtils.mkdir_p(File.join(@canonical, "slowhand", ".attic"))
    @ledger = Nabu::Store::Ledger.migrate!(Sequel.sqlite)
    @registry = Nabu::SourceRegistry.new([entry("lects", kind: "module"), entry("alpha"), entry("huge"),
                                          entry("rail"), entry("gamma"), entry("cold", wired: false),
                                          entry("byhand"), entry("slowhand")])
    @verdicts = [verdict("lects", :public_stable), verdict("alpha", :public_stable),
                 verdict("huge", :public_stable, attic: true), verdict("rail", :rail_paced),
                 verdict("gamma", :public_stable, attic: true), verdict("cold", :public_stable),
                 verdict("byhand", :manual), verdict("slowhand", :manual, attic: true)]
    sync_run("alpha", 100)
    sync_run("huge", 3_600)
    sync_run("gamma", 50)
    sync_run("byhand", 50)
    sync_run("slowhand", 3_600)
  end

  def teardown
    @ledger.disconnect
    FileUtils.remove_entry(@tmp)
  end

  def sync_run(slug, seconds)
    start = Time.utc(2026, 11, 1, 10)
    @ledger[:runs].insert(source_slug: slug, kind: "sync", status: "succeeded", started_at: start,
                          finished_at: start + seconds)
  end

  def build(**overrides)
    BackupSet.new(registry: @registry, verdicts: @verdicts, ledger: @ledger, canonical_dir: @canonical,
                  local_dir: @local, vectors_path: @vectors, sizes: false, **overrides).build
  end

  def paths(result) = result.entries.map(&:path)

  def test_the_set_holds_instance_vectors_rail_huge_and_foreign_attics
    result = build

    assert_includes paths(result), @local
    assert_includes paths(result), @vectors
    assert_includes paths(result), File.join(@canonical, "rail")
    assert_includes paths(result), File.join(@canonical, "huge")
    assert_includes paths(result), File.join(@canonical, "gamma", ".attic")
  end

  def test_a_fast_source_resyncs_and_a_covered_tree_needs_no_attic_entry
    result = build

    refute_includes paths(result), File.join(@canonical, "alpha")
    refute_includes paths(result), File.join(@canonical, "huge", ".attic"),
                    "a whole-tree entry already covers its attic"
  end

  def test_manual_trees_join_the_set_by_class_exactly_once
    result = build

    byhand = result.entries.find { |e| e.path == File.join(@canonical, "byhand") }
    refute_nil byhand, "a fast manual tree still rides the set — the route is human-hours, not compute"
    assert_match(/human/, byhand.reason)
    slow = result.entries.select { |e| e.path == File.join(@canonical, "slowhand") }
    assert_equal 1, slow.size, "a manual tree past the threshold appears once, as manual"
    assert_match(/human/, slow.first.reason)
    refute_includes paths(result), File.join(@canonical, "slowhand", ".attic"),
                    "a whole-tree manual entry already covers its attic"
  end

  def test_the_remainder_counts_only_wired_unbacked_sources
    result = build

    # alpha + gamma (measured) + lects (module, wired, unmeasured); cold is
    # unwired, rail and huge are backed up.
    assert_equal 3, result.resync_count
    assert_equal 150, result.resync_seconds
    assert_equal 1, result.resync_unmeasured
  end

  def test_the_threshold_is_overridable
    result = build(threshold: 2 * 3_600)

    refute_includes paths(result), File.join(@canonical, "huge")
    assert_includes paths(result), File.join(@canonical, "huge", ".attic"),
                    "a tree out of the set leaves its attic bytes in it"
    assert_equal 4, result.resync_count
  end

  def test_absent_instance_pieces_are_skipped_never_raised
    FileUtils.rm(@vectors)
    FileUtils.remove_entry(@local)
    result = build

    refute_includes paths(result), @vectors
    refute_includes paths(result), @local
  end

  def test_render_carries_reasons_counts_and_the_restore_order
    text = BackupSet.render(build)

    assert_includes text, "months-class to re-crawl"
    assert_includes text, "extra-huge: last re-sync measured 1h"
    assert_includes text, "upstream-deleted bytes"
    assert_includes text, "re-sync remainder: 3 wired sources"
    assert_includes text, "restore order:"
  end

  def test_sizes_come_from_du_when_asked
    File.write(File.join(@canonical, "rail", "blob"), "x" * 10)
    result = BackupSet.new(registry: @registry, verdicts: @verdicts, ledger: @ledger,
                           canonical_dir: @canonical, local_dir: @local, vectors_path: @vectors,
                           sizes: true).build
    rail = result.entries.find { |e| e.path == File.join(@canonical, "rail") }

    assert_operator rail.bytes, :>, 0
  end
end
