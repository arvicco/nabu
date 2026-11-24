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

  def preflight(slugs: %w[pap cdli], free: 10_000_000, holders: [], ps_text: "", trickle_dir: nil)
    P.new(db_dir: @db_dir, catalog_path: catalog, fulltext_path: fulltext, canonical_dir: @canonical,
          slugs: slugs, ledger: @ledger, trickle_dir: trickle_dir, free_bytes: ->(_dir) { free },
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
    assert_equal ["load pap", "load cdli", "code identities"], forecast.stages.first(3).map(&:label)
    assert_includes forecast.stages.map(&:label), "timeline"
    assert_in_delta 3_720.0 + 9_999, forecast.total, 0.001, "600 + 120 + 3000, plus cdli's sync-row estimate"
    refute_includes forecast.unpriced.map(&:label), "load cdli"
    assert_equal([["load cdli", :sync]], forecast.estimated.map { |stage| [stage.label, stage.basis] })
    assert_equal 2 + corpus_count - 4, forecast.unpriced.size
  end

  # A source added since the last full rebuild has no rebuild row: its
  # heaviest sync load row is a first estimate (a fresh load is a full one,
  # so a later no-change sync's seconds would underprice it), labelled as
  # such. A rebuild row always wins over any sync row.
  def test_a_never_rebuilt_source_is_priced_from_its_heaviest_sync_load_row_and_labelled
    sync = lambda do |slug, seconds|
      Nabu::Store::StageTimings.record!(@ledger, kind: "sync", scope: slug, stage: "load", seconds: seconds)
    end
    sync.call("cdli", 240)
    sync.call("cdli", 3) # a later no-change sync: not the price of a fresh load
    sync.call("pap", 9_000)
    record("pap", "load", 60) # the rebuild row wins

    forecast = preflight.forecast
    pap, cdli = forecast.stages.first(2)

    assert_in_delta 60.0, pap.seconds, 0.001
    assert_equal :rebuild, pap.basis
    assert_in_delta 240.0, cdli.seconds, 0.001
    assert_equal :sync, cdli.basis
    lines = P.render(preflight.report)
    assert_match(/1 priced from a sync row \(an estimate\), \d+ UNPRICED/, lines[1])
    assert_includes lines, "      #{'load cdli'.ljust(34)} ~4m (sync row)"
    assert_includes lines, "      #{'load pap'.ljust(34)} ~1m"
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

  # A trickle runner holds the fetch lock for days but only fetches — it
  # never loads, so it is not a catalog writer and must not block an
  # hours-long rebuild. It is named, with the consequence, and the verdict
  # stays CLEAR; a fetching SYNC (no trickle pidfile) still blocks.
  def test_a_trickle_runners_fetch_lock_is_named_but_does_not_block
    trickle_dir = File.join(@dir, "trickle")
    FileUtils.mkdir_p(trickle_dir)
    File.write(File.join(trickle_dir, "ndl.pid"), "#{Process.pid}\n")
    report = nil
    Nabu::FetchLock.hold(canonical_dir: @canonical, slug: "ndl") do
      report = preflight(trickle_dir: trickle_dir).report
    end

    assert_equal ["trickle crawl"], report.writers.map(&:kind)
    refute report.writers.first.blocking
    assert_match(/ndl .*only fetches, never loads/, report.writers.first.detail)
    assert_empty report.blockers
    refute_predicate report, :blocked?
  end

  def test_a_fetch_lock_without_its_trickle_pidfile_still_blocks
    trickle_dir = File.join(@dir, "trickle")
    FileUtils.mkdir_p(trickle_dir)
    File.write(File.join(trickle_dir, "ndl.pid"), "999999\n") # some other pid: not this lock's holder
    found = nil
    Nabu::FetchLock.hold(canonical_dir: @canonical, slug: "ndl") { found = preflight(trickle_dir: trickle_dir).writers }

    assert_equal ["fetch lock"], found.map(&:kind)
    assert found.first.blocking
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
