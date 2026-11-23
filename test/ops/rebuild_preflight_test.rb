# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/rebuild_preflight"

# Nabu::Ops::RebuildPreflight — the full rebuild's BEFORE half: the per-stage
# price from the ledger's own rows, the drop-first disk arithmetic, and the
# writers that must refuse the run — all read before anything is dropped.
class RebuildPreflightTest < Minitest::Test
  P = Nabu::Ops::RebuildPreflight
  T0 = Time.utc(2026, 11, 20)

  def setup
    @dir = Dir.mktmpdir("nabu-rebuild-preflight")
    @db_dir = File.join(@dir, "db")
    @canonical = File.join(@dir, "canonical")
    FileUtils.mkdir_p([@db_dir, @canonical])
    @ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
    @holder_calls = []
  end

  def teardown
    @ledger.disconnect
    FileUtils.rm_rf(@dir)
  end

  def catalog = File.join(@db_dir, "catalog.sqlite3")
  def fulltext = File.join(@db_dir, "fulltext.sqlite3")

  def preflight(slugs: %w[pap cdli], free: 10_000_000, holders: [], ps_text: "")
    P.new(db_dir: @db_dir, catalog_path: catalog, fulltext_path: fulltext, canonical_dir: @canonical,
          slugs: slugs, ledger: @ledger, free_bytes: ->(_dir) { free },
          holders: lambda { |paths|
            @holder_calls << paths
            holders
          },
          ps_output: -> { ps_text }, own_pids: [Process.pid])
  end

  def record(scope, stage, seconds, at: T0)
    Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: scope, stage: stage, seconds: seconds, at: at)
  end

  def write_bytes(path, bytes) = File.binwrite(path, "x" * bytes)

  # -- the price --------------------------------------------------------------

  def test_every_stage_is_priced_from_its_latest_rebuild_row_or_listed_unpriced
    record("pap", "load", 900)
    record("pap", "load", 600, at: T0 + 86_400) # the latest row governs
    record("corpus", "timeline", 120)
    record("corpus", "fts_lemma", 3_000)
    Nabu::Store::StageTimings.record!(@ledger, kind: "sync", scope: "cdli", stage: "load", seconds: 9_999)

    forecast = preflight.forecast

    corpus_count = Nabu::RebuildProfile::CORPUS_STAGE_LABELS.size
    assert_equal 2 + corpus_count, forecast.stages.size, "every load, then every profiled corpus stage"
    assert_equal ["load pap", "load cdli", "timeline"], forecast.stages.first(3).map(&:label)
    assert_in_delta 3_720.0, forecast.total, 0.001, "600 + 120 + 3000 — a sync row never prices a rebuild load"
    assert_includes forecast.unpriced.map(&:label), "load cdli"
    assert_equal 2 + corpus_count - 3, forecast.unpriced.size
  end

  def test_the_last_completed_full_run_is_the_wall_time_cross_check
    full = Nabu::Store::RebuildRuns.start!(@ledger, mode: "full", planned_stages: [], git_sha: "a", pid: 1, at: T0)
    Nabu::Store::RebuildRuns.complete!(@ledger, full, at: T0 + 7_200)
    incremental = Nabu::Store::RebuildRuns.start!(@ledger, mode: "incremental", planned_stages: [], git_sha: "a",
                                                           pid: 1, at: T0 + 86_400)
    Nabu::Store::RebuildRuns.complete!(@ledger, incremental, at: T0 + 86_460)
    Nabu::Store::RebuildRuns.start!(@ledger, mode: "full", planned_stages: [], git_sha: "a", pid: 1,
                                             at: T0 + (2 * 86_400)) # died: never completed

    last = preflight.forecast.last_full

    assert_in_delta 7_200.0, last.seconds, 0.001, "the newest COMPLETED full run — not incremental, not dead"
    assert_match(/last completed full rebuild: 2h wall \(started 2026-11-20\)/,
                 P.render(preflight.report).join("\n"))
  end

  def test_the_render_names_the_unpriced_stages_and_every_stage_on_the_full_view
    record("pap", "load", 60)
    lines = P.render(preflight.report)

    assert_match(/price: ~1m summed over 1 of \d+ stages .* UNPRICED/, lines[1])
    assert_includes lines, "      #{'load pap'.ljust(34)} ~1m"
    assert_includes lines, "      #{'load cdli'.ljust(34)} unpriced"
    short = P.render(preflight.report, stages: false).join("\n")
    assert_match(/heaviest 1:/, short)
    refute_match(/load cdli/, short, "the short view shows priced stages only")
  end

  # -- the disk ---------------------------------------------------------------

  def test_drop_first_arithmetic_counts_the_freed_bytes_with_their_sidecars
    write_bytes(catalog, 4_000)
    write_bytes("#{catalog}-wal", 1_000)
    write_bytes(fulltext, 3_000)
    write_bytes(File.join(@db_dir, "links.sqlite3"), 50_000) # rewritten in place, never dropped

    disk = preflight(free: 100_000).disk

    assert_equal 8_000, disk.drop_bytes
    assert_equal 108_000, disk.available
    refute disk.short?
    refute disk.tight?
    assert_empty @holder_calls, "free space alone covers the build: no holder probe at all"
  end

  def test_a_shortfall_blocks_and_a_tight_fit_only_warns
    write_bytes(catalog, 8_000)

    short = preflight(free: 0, holders: [[42, "nabu-mcp", catalog]]).report
    assert short.disk.short?, "the drop frees nothing while a reader pins the file"
    assert_equal 1, @holder_calls.size, "the run depends on the freed bytes: holders are probed"
    assert_match(/disk: the fresh build needs/, short.blockers.join)
    assert_match(/pid 42 \(nabu-mcp\) holds catalog\.sqlite3 open/, P.render(short).join("\n"))

    tight = preflight(free: 1_000).report
    assert tight.disk.tight?
    refute tight.blocked?, "inside the declared margin is a warning, never a refusal"
    assert_match(/inside the margin/, P.render(tight).join("\n"))
  end

  def test_lsof_field_output_parses_into_pid_command_path_rows
    out = "p101\ncruby\nf12\np202\ncnabu-mcp\n"
    assert_equal [[101, "ruby", "/db/catalog.sqlite3"], [202, "nabu-mcp", "/db/catalog.sqlite3"]],
                 P.holder_rows(out, "/db/catalog.sqlite3")
  end

  def test_unreadable_free_space_is_said_not_guessed
    write_bytes(catalog, 10)
    report = preflight(free: nil).report

    refute report.blocked?
    assert_match(/free space unreadable \(df\)/, P.render(report).join("\n"))
  end

  # -- the writers ------------------------------------------------------------

  def test_a_held_catalog_write_window_is_a_named_blocker
    handle = Nabu::CatalogWriteLock.acquire(db_dir: @db_dir, slug: "pap", announce: ->(_) {})
    report = preflight.report

    assert report.blocked?
    assert_match(/catalog write window: held by pap \(pid #{Process.pid}, held \d+s\)/, report.blockers.join)
  ensure
    handle&.release
  end

  def test_a_free_write_window_and_an_absent_lock_file_are_clear_and_untouched
    assert_empty preflight.writers
    refute File.exist?(File.join(@db_dir, Nabu::CatalogWriteLock::FILENAME)), "a probe never mints the lock file"

    Nabu::CatalogWriteLock.hold(db_dir: @db_dir, slug: "pap", announce: ->(_) {}) { nil } # leaves a free file
    assert_empty preflight.writers
  end

  def test_a_held_fetch_lock_names_the_source_being_fetched
    found = nil
    Nabu::FetchLock.hold(canonical_dir: @canonical, slug: "ndl") { found = preflight.writers }

    assert_equal ["fetch lock"], found.map(&:kind)
    assert_match(/ndl is being fetched \(a sync or trickle runner, pid #{Process.pid}\)/, found.first.detail)
    assert_empty preflight.writers, "released after the fetch"
  end

  def test_writer_processes_come_from_the_process_table
    ps = <<~PS
      101 ruby bin/nabu sync pap
      102 ruby bin/nabu rebuild --dry-run
      103 ruby bin/nabu search wrath
      104 /usr/bin/ruby /x/bin/nabu index refresh ndl
      #{Process.pid} ruby bin/nabu rebuild
    PS
    writers = preflight(ps_text: ps).writers

    assert_equal ["pid 101: ruby bin/nabu sync pap", "pid 104: /usr/bin/ruby /x/bin/nabu index refresh ndl"],
                 writers.map(&:detail), "dry runs, readers and the run itself are not writers"
    assert_match(/verdict: BLOCKED — writer process: pid 101/, P.render(preflight(ps_text: ps).report).last)
  end

  def test_a_clear_box_reads_clear
    assert_equal "  verdict: CLEAR — nothing blocks the rebuild", P.render(preflight.report).last
  end
end
