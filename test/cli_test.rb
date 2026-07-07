# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class CLITest < Minitest::Test
  # Run the Thor CLI in-process (never shell out to bin/nabu). Returns the
  # captured [stdout, stderr, exit_status]. exit_status is nil when the CLI
  # returned normally without calling exit.
  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end

  def test_version_prints_version_to_stdout
    out, _err, status = run_cli(["version"])
    assert_equal "#{Nabu::VERSION}\n", out
    assert_nil status, "version should not signal failure"
  end

  def test_help_lists_all_commands
    out, _err, _status = run_cli(["help"])
    %w[version sync status rebuild verify search show export].each do |command|
      assert_match(/\b#{command}\b/, out, "help output should list #{command}")
    end
  end

  def test_exit_on_failure_is_enabled
    assert Nabu::CLI.exit_on_failure?
  end

  # -- inline subcommand help (owner UX) -----------------------------------
  # `nabu help <command>` must teach the command, not just name it: query
  # syntax, real urn shapes, worked examples. Anchors only — prose may move.

  def test_help_search_documents_syntax_filters_and_examples
    out, _err, _status = run_cli(%w[help search])
    assert_match(/implicit AND/, out, "must state the multi-term semantics")
    assert_match(/μῆνιν/, out, "must show the diacritic-folding promise")
    assert_match(/prefix/, out, "must document the * prefix form")
    assert_match(%r{OR/NOT are not supported}i, out, "must be honest about booleans")
    assert_match(/Examples:/, out)
    assert_match(/--lang/, out)
  end

  def test_help_show_documents_urn_shapes_and_full_urn
    out, _err, _status = run_cli(%w[help show])
    assert_match(/provenance/, out, "must explain the passage view")
    assert_match(/:suffixes/, out, "must explain the document listing form")
    assert_match(/--full-urn/, out)
    assert_match(/urn:cts:greekLit:/, out, "must show a real CTS urn shape")
    assert_match(/restart block/, out, "must explain papyri :b<k> segments")
    assert_match(/Examples:/, out)
  end

  def test_help_export_documents_formats_and_filters
    out, _err, _status = run_cli(%w[help export])
    assert_match(/jsonl/, out)
    assert_match(/annotations/, out, "must say what rides in jsonl lines")
    assert_match(/Examples:/, out)
  end

  # status is implemented (P1-6). Against an empty registry with no catalog db,
  # it reports "no sources" and exits cleanly (0). (The shipped sources.yml now
  # registers perseus-greek, so this behaviour is tested against an isolated
  # empty registry rather than the real config.)
  def test_status_reports_no_sources_and_succeeds
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status, "status should not signal failure with an empty registry"
      assert_match(/no sources registered/i, out)
    end
  end

  # rebuild against an empty registry: nothing to replay, clean exit (0).
  def test_rebuild_empty_registry_says_nothing_to_rebuild
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["rebuild"]) }
      assert_nil status, "rebuild should not signal failure with an empty registry"
      assert_match(/nothing to rebuild/i, out)
    end
  end

  def test_rebuild_dry_run_lists_plan_and_changes_nothing
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild --dry-run]) }

      assert_nil status
      assert_match(/dry run/i, out)
      assert_match(/replay\s+corpus/, out)
      refute File.exist?(config.catalog_path), "dry run must not build the db"
    end
  end

  def test_rebuild_runs_and_reports_counts
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild]) }

      assert_nil status
      assert_match(/Dropped catalog db/, out)
      assert_match(/corpus.*\+2 added/, out)
      assert_match(/TOTAL.*\+2 added/, out)
      assert_match(/indexed 3 passages/, out) # μῆνιν, ἄειδε, ἄνδρα
      assert File.exist?(config.fulltext_path), "a real run builds the fulltext index"
      assert File.exist?(config.catalog_path), "a real run builds the db"
    end
  end

  # -- backup (P7-2) -------------------------------------------------------

  def test_backup_runs_to_a_local_target_and_reports_ok
    with_backup_env do |config, target|
      out, _err, status = with_config(config) { run_cli(["backup", "--to", target, "--allow-unmounted"]) }

      assert_nil status, "a clean backup exits 0"
      assert_match(/Backup → #{Regexp.escape(target)}/, out)
      assert_match(/canonical\s+ok/, out)
      assert_match(/OK\b/, out)
      assert File.exist?(File.join(target, "canonical", "corpus", "one.txt"))
      assert File.exist?(File.join(target, "config", "sources.yml"))
    end
  end

  def test_backup_dry_run_prints_plan_and_changes_nothing
    with_backup_env do |config, target|
      out, _err, status = with_config(config) { run_cli(["backup", "--to", target, "--allow-unmounted", "--dry-run"]) }

      assert_nil status
      assert_match(/dry run/i, out)
      refute File.exist?(File.join(target, "canonical")), "dry-run writes nothing"
    end
  end

  # The mount-point guard: a same-device tmp target without --allow-unmounted
  # is refused loudly (exit 1), and nothing is written.
  def test_backup_refuses_an_unmounted_target
    with_backup_env do |config, target|
      _out, err, status = with_config(config) { run_cli(["backup", "--to", target]) }

      assert_equal 1, status
      assert_match(/volume not mounted/i, err)
      refute File.exist?(File.join(target, "canonical"))
    end
  end

  def test_help_backup_documents_the_set_guard_and_examples
    out, _err, _status = run_cli(%w[help backup])
    assert_match(/mount-point guard/i, out)
    assert_match(/\.attic/, out, "must explain why the attic rides along")
    assert_match(/--skip-derived/, out)
    assert_match(/Examples:/, out)
  end

  # -- verify (P4-4) -------------------------------------------------------

  def test_verify_clean_corpus_reports_ok_and_exits_zero
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) } # build the catalog first
      out, _err, status = with_config(config) { run_cli(%w[verify]) }

      assert_nil status, "a clean verify exits 0"
      assert_match(/OK\s+corpus\s+\(2 documents verified\)/, out)
      assert_match(/All canonical documents verified/, out)
    end
  end

  def test_verify_corrupted_file_reports_mismatch_and_exits_one
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      # Change a word in one canonical file (filename unchanged ⇒ same urn).
      File.write(File.join(config.canonical_dir, "corpus", "one.txt"), "Iliad\nμῆνιν\nΧΧΧ\n")

      out, err, status = with_config(config) { run_cli(%w[verify]) }

      assert_equal 1, status
      assert_match(/FAILED\s+corpus/, out)
      assert_match(/MISMATCH\s+urn:nabu:test_adapter:one/, out)
      assert_match(/Integrity check FAILED/, out)
      assert_match(/failed the integrity check/, err)
    end
  end

  def test_verify_without_catalog_hints_to_sync_or_rebuild
    with_rebuild_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[verify]) }
      assert_equal 1, status
      assert_match(/no catalog/i, err)
    end
  end

  # -- sync (P2-4) ---------------------------------------------------------

  def test_sync_without_slug_or_all_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync]) }
      assert_equal 1, status
      assert_match(/slug or --all/i, err)
    end
  end

  def test_sync_unknown_slug_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync nope]) }
      assert_equal 1, status
      assert_match(/unknown source/i, err)
    end
  end

  # --parse-only skips fetch, so TestAdapter (whose #fetch is unimplemented)
  # loads straight off the canonical dir and the counts are reported.
  def test_sync_parse_only_loads_and_reports_counts
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/corpus\s+parse-only/, out)
      assert_match(/\+2 added/, out)
      assert_match(/indexed 3 passages/, out) # μῆνιν, ἄειδε, ἄνδρα
    end
  end

  # Explicit beats config: a disabled source named by slug still syncs, with a
  # printed note.
  def test_sync_disabled_source_by_slug_prints_note_and_runs
    with_sync_env(enabled: false) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/disabled; syncing anyway/i, out)
      assert_match(/\+2 added/, out)
    end
  end

  # -- progress reporting (P2-6) -------------------------------------------

  # When $stderr is a tty, the loader's per-document ticks render a \r-updating
  # "loading…" counter on $stderr; the final counts still land on $stdout.
  def test_sync_progress_hits_stderr_when_tty_stdout_counts_unchanged
    with_sync_env(enabled: true) do |config|
      out, err = with_config(config) do
        capture_with_tty(stderr_tty: true) { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      assert_match(/loading…/, err, "tty progress must write the counter to $stderr")
      assert_match(/corpus\s+parse-only/, out, "final counts stay on $stdout")
      assert_match(/\+2 added/, out)
      refute_match(/loading…/, out, "progress must not leak into $stdout")
    end
  end

  # Non-tty (the default in the suite): a small corpus stays completely silent
  # on $stderr — the per-100-docs line never triggers for two documents.
  def test_sync_non_tty_small_corpus_emits_no_progress
    with_sync_env(enabled: true) do |config|
      _out, err = with_config(config) do
        capture_with_tty(stderr_tty: false) { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      assert_empty err, "non-tty small corpus must not emit progress"
    end
  end

  # -- the history ledger at the CLI seam (P7-1) ----------------------------

  # Fresh bootstrap: no ledger file exists; status degrades honestly, the
  # first sync creates it, and the recorded run shows up in status.
  def test_first_sync_creates_the_ledger_and_status_reads_it
    with_sync_env(enabled: true) do |config|
      refute File.exist?(config.history_path), "no ledger before the first sync"

      with_config(config) { run_cli(%w[sync corpus --parse-only]) }

      assert File.exist?(config.history_path), "the first sync creates the ledger"
      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status
      assert_match(/corpus.*last run .*succeeded \(\+2 ~0 -0 !0\)/, out)
    end
  end

  # A catalog built without any run history (e.g. restored derived dbs, no
  # ledger): status stays functional and says so instead of inventing history.
  def test_status_without_ledger_reports_no_run_history
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      File.delete(config.history_path) # simulate a ledger-less derived set

      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status
      assert_match(/corpus.*docs=2.*no run history/, out)
    end
  end

  # -- health (P5-3 remote, P5-5 local) ------------------------------------

  # Bare `health` over a freshly synced, healthy corpus: source row "ok", golden
  # queries all skipped (the TestAdapter corpus holds none of the golden urns),
  # exit 0.
  def test_health_local_healthy_corpus_exits_zero
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[health]) }
      assert_nil status, "a healthy corpus is exit 0"
      assert_match(/corpus\s+ok/, out)
      assert_match(/golden replay:/, out)
      assert_match(/health: OK/, out)
      assert_match(/health --remote/, out, "bare health hints at the upstream probe")
    end
  end

  # A seeded quarantine spike in the run history is a loud finding: exit 1.
  def test_health_local_seeded_spike_exits_one
    with_indexed_corpus do |config|
      seed_spike_runs(config)
      out, err, status = with_config(config) { run_cli(%w[health]) }
      assert_equal 1, status, "a quarantine spike fails health"
      assert_match(/ANOMALY/, out)
      assert_match(/quarantine spike/i, out)
      assert_match(/loud finding/i, err)
    end
  end

  # No catalog on disk: an informational "no corpus" note, exit 0.
  def test_health_local_no_corpus_notes_and_exits_zero
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[health]) }
      assert_nil status
      assert_match(/no corpus/i, out)
      assert_match(/health: OK/, out)
    end
  end

  # --remote, every upstream alive → the table lands on stdout and exit is 0.
  # TestAdapter's upstream is non-github, so the license check stays unchecked
  # (no HTTP), and with no catalog built drift reads never-synced.
  def test_health_remote_all_alive_exits_zero
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) do
        with_stubbed_shell(->(*_argv) { "sha_head\tHEAD\n" }) { run_cli(%w[health --remote]) }
      end
      assert_nil status, "all-alive is exit 0"
      assert_match(/corpus\s+alive/, out)
      assert_match(/1 source, 1 alive/, out)
    end
  end

  # --remote, a gone upstream → GONE in the table (stdout) and exit 1.
  def test_health_remote_gone_upstream_exits_one
    with_sync_env(enabled: true) do |config|
      dead = ->(*_argv) { raise Nabu::Shell::Error.new("x", status: 128, stderr: "remote: Repository not found.") }
      out, err, status = with_config(config) do
        with_stubbed_shell(dead) { run_cli(%w[health --remote]) }
      end
      assert_equal 1, status
      assert_match(/corpus\s+GONE/, out)
      assert_match(/upstream.*gone/i, err)
    end
  end

  # -- search (P4-2) -------------------------------------------------------

  # Build the store (catalog + fulltext index) via a real parse-only sync, then
  # search. The unaccented query "μηνιν" must find the accented passage μῆνιν —
  # proving query and index share the diacritic fold.
  def test_search_finds_greek_passage_via_unaccented_query
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search μηνιν]) }
      assert_nil status, "a successful search exits 0"
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out)
      assert_match(/\[μηνιν\]/, out, "the folded match is highlighted")
      assert_match(/1 hit\b/, out)
    end
  end

  def test_search_zero_hits_says_no_matches_and_succeeds
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search zzzznotfound]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out)
    end
  end

  def test_search_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search μηνιν --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  def test_search_without_index_hints_to_sync_or_rebuild
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[search anything]) }
      assert_equal 1, status
      assert_match(/no index.*sync.*rebuild/i, err)
    end
  end

  # -- show (P4-3) ---------------------------------------------------------

  def test_show_passage_prints_text_document_and_provenance
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1]) }
      assert_nil status, "a resolved urn exits 0"
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out)
      assert_match(/μῆνιν/, out, "the pristine passage text is shown")
      assert_match(/document: urn:nabu:test_adapter:one/, out)
      assert_match(/provenance:/, out)
      assert_match(/loaded/, out, "the loader's provenance event is listed")
    end
  end

  def test_show_document_lists_passages_as_suffixes
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one]) }
      assert_nil status
      assert_match(/passages \(2\):/, out)
      assert_match(/^ +:1  /, out, "passage lines carry only the suffix relative to the document urn")
      assert_match(/^ +:2  /, out)
      refute_match(/^ +urn:nabu:test_adapter:one:1\b/, out,
                   "the document urn is printed once in the header, not per line")
    end
  end

  def test_show_document_full_urn_flag_restores_absolute_urns
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one --full-urn]) }
      assert_nil status
      assert_match(/^ +urn:nabu:test_adapter:one:1\b/, out)
      assert_match(/^ +urn:nabu:test_adapter:one:2\b/, out)
    end
  end

  def test_show_unknown_urn_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:nope]) }
      assert_equal 1, status
      assert_match(/urn not found/i, err)
    end
  end

  # -- export (P4-3) -------------------------------------------------------

  def test_export_plain_streams_one_line_per_passage
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[export --format plain]) }
      assert_nil status
      lines = out.split("\n")
      assert_equal 3, lines.size, "three live passages, one line each"
      assert_includes lines, "μῆνιν"
    end
  end

  def test_export_jsonl_emits_valid_json_objects
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[export --format jsonl]) }
      assert_nil status
      records = out.split("\n").map { |line| JSON.parse(line) }
      assert_equal 3, records.size
      record = records.first
      assert_equal %w[annotations language text text_normalized urn].sort, record.keys.sort
      assert_kind_of Hash, record.fetch("annotations")
    end
  end

  def test_export_conllu_is_deferred
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[export --format conllu]) }
      assert_equal 1, status
      assert_match(/deferred until the enrichment phase/i, err)
    end
  end

  def test_export_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[export --format plain --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  private

  # A config whose db/ has been fully built (catalog + fulltext index) by a real
  # parse-only sync of the two-document TestAdapter corpus. Yields the config.
  def with_indexed_corpus
    with_sync_env(enabled: true) do |config|
      with_config(config) do
        capture_io { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      yield config
    end
  end

  # Append three succeeded runs for the just-synced "corpus" source so the
  # latest errored count (90) towers over the recent norm — a quarantine spike.
  # Runs live in the history ledger (P7-1), slug-keyed; writes through its own
  # connection, then hands back so the CLI opens it fresh.
  def seed_spike_runs(config)
    db = Nabu::Store::Ledger.open!(config.history_path)
    now = Time.now
    [2, 3, 90].each do |errored|
      Nabu::Store::Run.create(source_slug: "corpus", kind: "sync", started_at: now, finished_at: now,
                              added: 1, updated: 0, errored: errored, status: "succeeded")
    end
  ensure
    db&.disconnect
  end

  # capture_io, but with tty? forced on the swapped StringIO streams so the
  # tty-gated progress paths can be exercised (Minitest 6 has no Mock; this is
  # the house swap-singleton pattern). Returns [stdout_string, stderr_string].
  def capture_with_tty(stderr_tty:)
    out = StringIO.new
    err = StringIO.new
    out.define_singleton_method(:tty?) { false }
    err.define_singleton_method(:tty?) { stderr_tty }
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    yield
    [out.string, err.string]
  ensure
    $stdout = old_out
    $stderr = old_err
  end

  # One TestAdapter source "corpus" (two documents) with canonical data; the
  # caller stubs Config.load with the yielded config. +enabled+ seeds the row.
  def with_sync_env(enabled:)
    Dir.mktmpdir("nabu-cli-sync") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: #{enabled}\n  sync_policy: live\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # Swap Nabu::Shell.run for +impl+ (a proc) so the health probe sees canned
  # ls-remote output/failures with no network, restoring the original after.
  def with_stubbed_shell(impl)
    original = Nabu::Shell.method(:run)
    Nabu::Shell.define_singleton_method(:run) { |*argv| impl.call(*argv) }
    yield
  ensure
    Nabu::Shell.define_singleton_method(:run, original)
  end

  # Minitest 6 dropped Minitest::Mock (and it is outside the dependency budget),
  # so pin Config.load to +config+ by swapping the singleton method, restoring
  # the original afterward.
  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  # Build a throwaway config with an empty (comments-only) registry and no
  # catalog db, and yield it.
  def with_empty_registry_env
    Dir.mktmpdir("nabu-cli-empty") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# no sources registered\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # Build a throwaway config whose config_dir is a REAL tmp dir (so the backup's
  # config/ section never rsyncs the project root) plus a tiny canonical tree,
  # and yield [config, target].
  def with_backup_env
    Dir.mktmpdir("nabu-cli-backup") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\n")
      cfg = File.join(root, "config")
      FileUtils.mkdir_p(cfg)
      File.write(File.join(cfg, "sources.yml"), "corpus:\n  adapter: TestAdapter\n")
      File.write(File.join(cfg, "nabu.yml"), "# nabu config\n")
      target = File.join(root, "backup-target")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(cfg, "sources.yml"), config_path: File.join(cfg, "nabu.yml")
      )
      yield config, target
    end
  end

  # Build a throwaway config with one replayable TestAdapter source ("corpus",
  # two documents) and yield it; the caller stubs Config.load with it.
  def with_rebuild_env
    Dir.mktmpdir("nabu-cli-rebuild") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end
end
