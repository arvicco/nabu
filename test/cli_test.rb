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
    %w[version sync status rebuild verify search show export define etym].each do |command|
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

  def test_help_show_documents_parallel_with_an_example
    out, _err, _status = run_cli(%w[help show])
    assert_match(/--parallel/, out)
    assert_match(/citation suffix/, out, "must explain the alignment rule")
    assert_match(/--parallel\b.*\n?.*eng/, out, "must show a worked --parallel example")
    assert_match(/one-sided|only in/i, out, "must be honest about unmatched suffixes")
  end

  def test_help_show_documents_range_syntax_with_a_papyri_example
    out, _err, _status = run_cli(%w[help show])
    assert_match(/RANGE|range/, out, "must document the range syntax")
    assert_match(/1\.1-1\.10/, out, "must show a CTS range example")
    assert_match(/:1-b2:2|:b2:/, out, "must show a papyri cross-block range example")
    assert_match(/inclusive/i, out, "must state the endpoints are inclusive")
  end

  def test_help_search_mentions_translations
    out, _err, _status = run_cli(%w[help search])
    assert_match(/translation/i, out, "must say eng translations are searchable when ingested")
    assert_match(/--lang eng/, out)
  end

  def test_help_search_documents_lemma_search_with_a_real_example
    out, _err, _status = run_cli(%w[help search])
    assert_match(/--lemma/, out)
    assert_match(/treebank/i, out, "must scope --lemma to the gold treebanks")
    assert_match(/--lemma λέγω/, out, "must show a worked Greek example")
    assert_match(/εἶπας/, out, "must show the suppletive payoff — forms no text query reaches")
    assert_match(/replaces the text query/i, out, "must be honest that --lemma and a query don't combine")
  end

  # P11-4 (+P12-3): `nabu define` help must teach the shelf, the folding
  # promise, the citation-resolution behavior, and worked examples in all
  # three languages — including the OE ASCII-folding promise (aethele finds
  # æðele).
  def test_help_define_documents_the_dictionary_shelf
    out, _err, _status = run_cli(%w[help define])
    assert_match(/LSJ/, out)
    assert_match(/Lewis & Short/, out)
    assert_match(/Bosworth-Toller/, out)
    assert_match(/Wiktionary/, out, "must document the OCS shelf (P13-10)")
    assert_match(/μηνις finds μῆνις/, out, "must show the diacritic-folding promise")
    assert_match(/aethele finds æðele/, out, "must show the OE ASCII-folding promise")
    assert_match(/nabu show <urn>/, out, "must teach the resolved-citation handoff")
    assert_match(/--lang grc\|lat\|ang\|chu/, out)
    assert_match(/nabu define virtus/, out, "must show a Latin example")
  end

  # P14-1: `nabu etym` help must teach the walk (attested → proto →
  # cognates), the asterisk convention, the romanization bridge, and worked
  # examples on the demo chains.
  def test_help_etym_documents_the_reconstruction_walk
    out, _err, _status = run_cli(%w[help etym])
    assert_match(/Proto-Slavic/, out)
    assert_match(/Proto-Indo-European/, out)
    assert_match(/Proto-Germanic/, out)
    assert_match(/attestation count/i, out, "must promise corpus counts")
    assert_match(/\*bogъ/, out, "must show the asterisk convention")
    assert_match(/guþ/, out, "must show the romanization bridge example")
    assert_match(/nabu etym богъ/, out, "must show the OCS worked example")
    assert_match(/bhewgh/, out, "P14-10: must teach the ASCII bare-form fallback")
    assert_match(/'\*kaisaraz'/, out, "P14-10: shell star examples must be quoted")
  end

  def test_help_define_documents_the_reconstruction_shelves
    out, _err, _status = run_cli(%w[help define])
    assert_match(/sla-pro\|ine-pro\|gem-pro/, out, "the widened --lang gate")
    assert_match(/define '\*bogъ'/, out, "must show the quoted asterisk example (zsh globs bare *)")
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
      assert_match(/corpus.*last \d{4}-\d{2}-\d{2} \d{2}:\d{2} ok \(\+2 ~0 -0 !0\)/, out)
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

  # -- search --lemma (P7-5) -------------------------------------------------

  # Real UD Ancient Greek PROIEL fixture synced through the real pipeline:
  # --lemma λέγω must surface the suppletive aorist εἶπας (sentence 64498) —
  # an attestation no λεγ- text query can reach.
  def test_search_lemma_finds_inflected_attestations
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λέγω --lang grc]) }
      assert_nil status, "a successful lemma search exits 0"
      assert_match(/urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50:64498 \[grc\]/, out)
      assert_match(/λέγω → εἶπας/, out, "the hit names the matched surface form")
      assert_match(/λέγειν, εἰπεῖν/, out, "multiple forms in one passage aggregate on one hit")
      assert_match(/exact lemma match/, out, "the footer labels the match kind")
    end
  end

  # Fold both sides at the CLI seam: the unaccented spelling still hits.
  def test_search_lemma_unaccented_query_matches
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λεγω]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out)
    end
  end

  def test_search_lemma_zero_hits_says_no_matches
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma τίθημι]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out)
    end
  end

  def test_search_lemma_with_a_text_query_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search μηνιν --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/--lemma replaces the text query/, err)
    end
  end

  # A fulltext file built before P7-5 has no lemma table: honest hint, exit 1.
  def test_search_lemma_against_a_pre_lemma_index_hints_to_reindex
    with_treebank_corpus do |config|
      ft = Nabu::Store.connect_fulltext(config.fulltext_path)
      ft.drop_table(Nabu::Store::Indexer::LEMMA_TABLE)
      ft.disconnect
      _out, err, status = with_config(config) { run_cli(%w[search --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/no lemma index.*sync.*rebuild/i, err)
    end
  end

  # -- search --near (P14-8 proximity) -------------------------------------

  # Real UD grc sentence 64498: … ὁ κῆρυξ(7) καὶ(8) εἶπας(9) … — κῆρυξ and
  # εἶπας sit a word apart. --window 1 admits them, both folded terms
  # bracketed; --window 0 (adjacency) does not.
  def test_search_near_within_window_hits_with_both_terms_highlighted
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search κῆρυξ --near εἶπας --window 1]) }
      assert_nil status, "a successful proximity search exits 0"
      assert_match(/:64498 \[grc\]/, out)
      assert_match(/\[κηρυξ\]/, out, "the anchor term is highlighted")
      assert_match(/\[ειπασ\]/, out, "the near term is highlighted too")
    end
  end

  def test_search_near_window_zero_requires_adjacency
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search κῆρυξ --near εἶπας --window 0]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out, "window 0 needs adjacency — κῆρυξ and εἶπας are a word apart")
    end
  end

  # The lemma anchor expands to attested surface forms before the NEAR: the
  # suppletive aorist εἶπας is a form of λέγω, so it sits near the rare κῆρυξ.
  def test_search_near_expands_a_lemma_anchor
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λέγω --near κῆρυξ --window 1]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out, "εἶπας (a form of λέγω) is one word from κῆρυξ")
    end
  end

  def test_search_near_with_morph_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --lemma λέγω --near κύριος --morph case=nom]) }
      assert_equal 1, status
      assert_match(/--morph does not compose with --near/, err)
    end
  end

  def test_search_near_without_an_anchor_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --near θεα]) }
      assert_equal 1, status
      assert_match(/--near needs an anchor/, err)
    end
  end

  # -- concord (P8-3) ------------------------------------------------------

  def test_concord_prints_kwic_lines_with_the_keyword_located
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord μηνιν --width 10]) }
      assert_nil status, "a successful concord exits 0"
      assert_match(/μῆνιν/, out, "the pristine accented keyword appears in the KWIC line")
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out, "the urn + language tag per row")
      assert_match(/1 line\b/, out, "the footer counts KWIC lines")
    end
  end

  # Alignment: the keyword column is identical across rows of varying keyword
  # length. Two passages, different words matched by one prefix query; the
  # keyword's left edge sits at the same character offset on both lines.
  def test_concord_aligns_the_keyword_column
    with_kwic_corpus do |config|
      out, _err, _status = with_config(config) { run_cli(%w[concord μηνι* --width 8]) }
      lines = out.split("\n").select { |line| line.include?("test_adapter:kwic:") }
      assert_equal 2, lines.size, "two hits with different-length keywords"
      # Each line begins with an 8-char left context; the keyword's left edge
      # (the μ of μῆνιν / μηνιτισι) therefore sits at column 8 on both rows.
      assert lines.all? { |line| line.chars[8] == "μ" }, "keyword column aligned at width"
    end
  end

  def test_concord_zero_hits_says_no_matches
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord zzzznotfound]) }
      assert_nil status
      assert_match(/no matches/i, out)
    end
  end

  def test_concord_lemma_mode_finds_inflected_forms_in_context
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord --lemma λέγω --lang grc]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out)
      assert_match(/εἶπας/, out, "the located surface form is the inflected attestation")
    end
  end

  def test_concord_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord μηνιν --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  def test_concord_without_index_hints_to_sync_or_rebuild
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord anything]) }
      assert_equal 1, status
      assert_match(/no index.*sync.*rebuild/i, err)
    end
  end

  def test_concord_lemma_with_a_text_query_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord μηνιν --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/--lemma replaces the text query/, err)
    end
  end

  def test_help_concord_documents_kwic_lemma_and_examples
    out, _err, _status = run_cli(%w[help concord])
    assert_match(/KWIC|keyword-in-context/i, out)
    assert_match(/--width/, out)
    assert_match(/corpus order/i, out, "must say rows are corpus-ordered, not ranked")
    assert_match(/nabu concord μῆνιν/, out, "a worked grc example")
    assert_match(/--lemma λέγω/, out, "a worked lemma example")
    assert_match(/Examples:/, out)
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

  # -- show --random (P11-9) -------------------------------------------------

  def test_show_random_prints_a_passage_in_the_standard_layout
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show --random]) }
      assert_nil status, "a random draw over a non-empty corpus exits 0"
      assert_match(/urn:nabu:test_adapter:\w+:\d+ \[grc\]/, out, "a passage urn + language header")
      assert_match(/document: urn:nabu:test_adapter:/, out, "the standard show layout, document line")
      assert_match(/provenance:/, out, "the full provenance trail, as `show <urn>` renders it")
    end
  end

  def test_show_random_count_bounds_the_number_of_passages
    with_indexed_corpus do |config|
      # The fixture corpus holds three live passages; --count 3 shows all three.
      out, _err, status = with_config(config) { run_cli(%w[show --random --count 3]) }
      assert_nil status
      headers = out.scan(/^urn:nabu:test_adapter:/).length
      assert_equal 3, headers, "three passages, three headers"
    end
  end

  def test_show_random_scopes_to_a_source
    with_indexed_corpus do |config|
      # The fixture source's slug is "corpus" (the sources.yml key); its adapter
      # mints urn:nabu:test_adapter:… passage urns.
      out, _err, status = with_config(config) { run_cli(%w[show --random --source corpus --count 3]) }
      assert_nil status
      headers = out.scan(/^urn:\S+/)
      refute_empty headers
      assert(headers.all? { |urn| urn.start_with?("urn:nabu:test_adapter") },
             "every drawn passage belongs to the scoped source")
    end
  end

  def test_show_random_unknown_source_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
    end
  end

  def test_show_random_rejects_a_urn
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random urn:nabu:test_adapter:one:1]) }
      assert_equal 1, status
      assert_match(/--random takes no urn/, err)
    end
  end

  def test_show_source_without_random_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1 --source test_adapter]) }
      assert_equal 1, status
      assert_match(/--source requires --random/, err)
    end
  end

  # -- show ranges (P7-6) ----------------------------------------------------

  def test_show_range_lists_the_slice_as_suffixes_with_an_honest_count
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-1]) }
      assert_nil status, "a resolved range exits 0"
      assert_match(/urn:nabu:test_adapter:one\b/, out, "the document header names the document urn")
      assert_match(/1 of 2 passages/, out, "the honest [N of M] note")
      assert_match(/^ +:1  /, out, "slice lines carry only the :suffix")
      refute_match(/^ +:2  /, out, "the slice excludes passages outside the range")
    end
  end

  def test_show_range_full_urn_restores_absolute_urns
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-2 --full-urn]) }
      assert_nil status
      assert_match(/^ +urn:nabu:test_adapter:one:1\b/, out)
      assert_match(/^ +urn:nabu:test_adapter:one:2\b/, out)
    end
  end

  def test_show_range_endpoint_not_found_exits_one_naming_the_endpoint
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-99]) }
      assert_equal 1, status
      assert_match(/range end not found/i, err)
      assert_match(/urn:nabu:test_adapter:one:99/, err)
    end
  end

  def test_show_reversed_range_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:2-1]) }
      assert_equal 1, status
      assert_match(/reversed/i, err)
    end
  end

  def test_show_parallel_composes_with_a_range
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1-2", "--parallel"]) }
      assert_nil status
      # eng :1 owns grc :1 and :2 as ONE block; :3 is outside the slice.
      assert_match(/0 paired, 1 block covering 2 lines, 0 grc only, 0 eng only/, out)
      assert_match(/grc {2}μῆνιν/, out)
      assert_match(/grc {2}ἄειδε/, out, "the whole span shows, not just the anchor line")
      assert_match(/eng \[:1 — covers :1–:2\]/, out, "the block is labeled by its coverage")
      assert_match(/Wrath/, out)
      refute_match(/θεά/, out, ":3 is outside the slice")
    end
  end

  # -- show --parallel (P7-4, span-grouped P8-1b) ----------------------------

  GRC_URN = "urn:cts:greekLit:tg1.w1.perseus-grc2"
  ENG_URN = "urn:cts:greekLit:tg1.w1.perseus-eng2"

  # A verse-for-verse translation renders byte-identically to pre-P8-1b: every
  # anchor is a 1:1 pair, no blocks clause, the compact two-line pair form.
  def test_show_parallel_verse_output_is_byte_identical_to_the_pair_form
    with_verse_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel"]) }
      assert_nil status
      expected = <<~OUT
        #{GRC_URN} — Iliad [grc]
          parallel: #{ENG_URN} — Iliad [eng]
          aligned by citation: 3 paired, 0 grc only, 0 eng only
          :1
            grc  μῆνιν
            eng  Wrath
          :2
            grc  ἄειδε
            eng  sing
          :3
            grc  θεά
            eng  goddess
      OUT
      assert_equal expected, out
    end
  end

  # A card-cited coarse translation: the whole span of original lines, then the
  # translation block ONCE with its coverage label — no wall of dashes.
  def test_show_parallel_full_document_coarse_render
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel"]) }
      assert_nil status
      assert_match(/aligned by citation: 0 paired, 2 blocks covering 8 lines, 0 grc only, 0 eng only/, out)
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4\]\n {4}Block one/, out)
      assert_match(/eng \[:1\.5 — covers :1\.5–:1\.8\]\n {4}Block two/, out)
      assert_match(/^ +:1\.4\n {4}grc {2}grc4$/, out, "each owned original line is shown once, suffix-labeled")
      refute_match(/eng {2}—/, out, "no per-line dashes under a coarse block")
    end
  end

  def test_show_parallel_mid_card_range_clips_with_a_note
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1.2-1.3", "--parallel"]) }
      assert_nil status
      assert_match(/0 paired, 1 block covering 2 lines/, out)
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4; range shows :1\.2–:1\.3\]/, out)
      assert_match(/grc {2}grc2/, out)
      refute_match(/grc1|grc4/, out, "only the in-slice originals are listed")
    end
  end

  # The regression the owner hit: a range that STARTS inside a card — the
  # owning anchor lies outside the slice, yet the block still renders (it used
  # to dash every line).
  def test_show_parallel_range_starting_inside_a_card_still_shows_the_block
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1.3-1.6", "--parallel"]) }
      assert_nil status
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4; range shows :1\.3–:1\.4\]\n {4}Block one/, out,
                   "the card anchored at 1.1 (outside the slice) still renders its block")
      assert_match(/eng \[:1\.5 — covers :1\.5–:1\.8; range shows :1\.5–:1\.6\]\n {4}Block two/, out)
      refute_match(/eng {2}—/, out)
    end
  end

  def test_show_parallel_takes_an_explicit_language
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", ENG_URN, "--parallel", "grc"]) }
      assert_nil status
      assert_match(/#{Regexp.escape(GRC_URN)}/, out)
      assert_match(/grc {2}ἄειδε/, out, "grc :2, absent from the eng original, stays one-sided")
    end
  end

  def test_show_parallel_passage_urn_scopes_to_the_owning_block
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1", "--parallel"]) }
      assert_nil status
      assert_match(/grc {2}μῆνιν/, out)
      assert_match(/eng \[:1 — covers :1–:2; range shows :1–:1\]/, out, "the owning block, clipped to the line")
      assert_match(/Wrath/, out)
      refute_match(/ἄειδε/, out, "a passage urn shows only its own line of the block")
    end
  end

  def test_show_parallel_full_urn_restores_absolute_row_labels
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel", "eng", "--full-urn"]) }
      assert_nil status
      assert_match(/^ +#{Regexp.escape("#{GRC_URN}:1")}$/, out)
    end
  end

  def test_show_parallel_without_a_sibling_exits_one_naming_the_language
    with_parallel_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel", "lat"]) }
      assert_equal 1, status
      assert_match(/no lat parallel edition/i, err)
    end
  end

  def test_show_parallel_unknown_urn_exits_one
    with_parallel_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:cts:greekLit:tg1.w1.nope --parallel]) }
      assert_equal 1, status
      assert_match(/urn not found/i, err)
    end
  end

  # -- align (P11-3) ---------------------------------------------------------

  def test_align_renders_a_verse_across_witnesses_with_license_labels
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status, "an attested ref exits 0"
      assert_match(/MARK 2\.3 — New Testament/, out)
      assert_match(/greek-nt — Greek NT \[grc\] {3}license: nc/, out)
      assert_match(/marianus — Codex Marianus \[chu\] {3}license: nc/, out)
      assert_match(/παραλυτικὸν/, out)
      assert_match(/носѧште/, out)
      assert(out.index("παραλυτικὸν") < out.index("носѧште"),
             "witnesses render in registry order")
      assert_match(/2 of 2 witnesses/, out)
    end
  end

  def test_align_shows_the_hebrew_witness_at_its_native_ref_with_a_numbering_label
    registry = <<~YAML
      psalms:
        title: "Psalms"
        witnesses:
          - label: LXX
            extractor: cts-verse
            documents:
              PSA: urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1
          - label: WEB (English)
            extractor: cts-verse
            numbering:
              system: "Hebrew (Masoretic)"
              ranges:
                - { from: 11, to: 113, shift: -1 }
            documents:
              PSA: urn:nabu:eng-web:psa
    YAML
    with_psalms_corpus(registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "PSA", "22.1"]) }
      assert_nil status, "an attested ref exits 0"
      assert_match(/PSA 22\.1 — Psalms/, out)
      assert_match(/ποιμαίνει/, out, "the Greek witness at the work ref")
      assert_match(/Hebrew \(Masoretic\) numbering/, out, "the WEB column is flagged as remapped")
      assert_match(/\[Hebrew \(Masoretic\): PSA 23\.1\]/, out, "and shows its native Hebrew ref")
      assert_match(/shepherd/, out)
    end
  end

  def test_align_normalizes_the_query_ref
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "mark", "2:3"]) }
      assert_nil status
      assert_match(/MARK 2\.3/, out)
    end
  end

  def test_align_pivots_from_a_passage_urn
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align urn:nabu:proiel:marianus:1]) }
      assert_nil status
      assert_match(/MARK 2\.3/, out)
      assert_match(/παραλυτικὸν/, out)
    end
  end

  def test_align_unattested_ref_reads_honestly_and_exits_zero
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "JOHN", "1.1"]) }
      assert_nil status, "an all-absent ref is a result, not an error"
      assert_match(/0 of 2 witnesses/, out)
      assert_match(/not attested/, out)
    end
  end

  def test_align_unsynced_witness_reads_not_synced
    with_aligned_corpus(extra_witness: "urn:nabu:proiel:wscp") do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/wscp — not synced/, out)
      assert_match(/2 of 3 witnesses/, out)
    end
  end

  # P11-5: a multi-document (cts-verse) witness that misses the ref heads its
  # column with the label alone — no arbitrary book title.
  def test_align_multi_document_witness_miss_renders_label_without_a_title
    registry = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - label: verses
            extractor: cts-verse
            documents:
              MARK: urn:nabu:proiel:marianus
              JOHN: urn:nabu:sblgnt:john
    YAML
    with_aligned_corpus(registry: registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/^verses \[chu\] {3}license: nc/, out)
      assert_match(/not attested/, out)
      assert_match(/1 of 2 witnesses/, out)
    end
  end

  # …and when the multi-document witness does not even map the queried ref's
  # book, the not-synced note phrases the miss neutrally (no unrelated urn).
  def test_align_not_synced_multi_document_witness_with_unmapped_book_reads_neutrally
    registry = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
          - label: verses
            extractor: cts-verse
            documents:
              JOHN: urn:nabu:sblgnt:john
              ACTS: urn:nabu:sblgnt:acts
    YAML
    with_aligned_corpus(registry: registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/verses — not synced \(its registered documents are not in the catalog\)/, out)
      refute_match(/urn:nabu:sblgnt/, out, "no unrelated book urn is named")
    end
  end

  def test_align_without_index_hints_to_sync_or_rebuild
    with_aligned_corpus(indexed: false) do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_equal 1, status
      assert_match(/nabu sync or nabu rebuild/, err)
    end
  end

  def test_align_with_no_registry_exits_one_with_guidance
    with_aligned_corpus(registry: "") do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_equal 1, status
      assert_match(/no alignment works registered/i, err)
    end
  end

  def test_align_unknown_work_exits_one_naming_the_registered
    with_aligned_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3", "--work", "iliad"]) }
      assert_equal 1, status
      assert_match(/iliad/, err)
      assert_match(/nt/, err)
    end
  end

  def test_align_without_a_ref_exits_one
    with_aligned_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[align]) }
      assert_equal 1, status
      assert_match(/give a citation/i, err)
    end
  end

  # -- align ranges / chapters (P11-8) ---------------------------------------

  def test_align_chapter_renders_every_ref_compactly_with_a_witness_legend
    with_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align JON 1]) }
      assert_nil status
      assert_match(/JON 1 — /, out, "the query heads the block")
      assert_match(/witnesses:.*full.*partial/m, out, "a one-line legend, titles shown once")
      # Every attested verse in document order, verse 1 before verse 2 before 10.
      assert(out.index("JON 1.1") < out.index("JON 1.2"), "refs in document order")
      assert(out.index("JON 1.2") < out.index("JON 1.10"), "numeric, not lexical, order")
      assert_match(/full  greek verse 1/, out)
      assert_match(/partial — not attested/, out, "per-ref attestation honesty")
    end
  end

  def test_align_chapter_summarizes_all_absent_witnesses_once_in_the_header
    with_absent_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align JON 1]) }
      assert_nil status
      assert_match(/not synced: ghost/, out, "an all-absent witness is summarized once in the header")
      assert_equal 1, out.scan("ghost").length, "ghost never repeats down the per-ref blocks"
      assert_match(/partial — not attested/, out, "a partially-attesting witness stays per-ref")
      assert_match(/full  greek verse 1/, out, "attesting witnesses render per ref as before")
    end
  end

  def test_align_verse_range_renders_the_inclusive_slice
    with_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "JON 1.3-1.5"]) }
      assert_nil status
      assert_match(/JON 1\.3/, out)
      assert_match(/JON 1\.5/, out)
      refute_match(/JON 1\.6/, out, "the range is inclusive and bounded")
      refute_match(/JON 1\.2\b/, out)
    end
  end

  def test_align_reversed_range_exits_one
    with_range_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "JON 1.5-1.3"]) }
      assert_equal 1, status
      assert_match(/reversed range/, err)
    end
  end

  def test_help_align_documents_refs_work_and_examples
    out, _err, _status = run_cli(%w[help align])
    assert_match(/MARK 2\.3/, out, "a worked ref example")
    assert_match(/--work/, out)
    assert_match(%r{config/alignments\.yml}, out, "must point at the registry")
    assert_match(/Examples:/, out)
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

  # An on-disk two-witness alignment corpus (P11-3): a registry file, a
  # catalog with the greek-nt/marianus MARK 2.3 sentences (real live-catalog
  # snippets, sentence-id urns, verse identity in the token citation_parts),
  # and — unless indexed: false — the fulltext db with alignment_refs built.
  def with_aligned_corpus(registry: nil, extra_witness: nil, indexed: true)
    Dir.mktmpdir("nabu-cli-align") do |root|
      config = aligned_corpus_config(root, registry, extra_witness)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_aligned_witnesses(catalog)
      index_aligned_corpus(config, catalog) if indexed
      catalog.disconnect
      yield config
    end
  end

  # A two-witness Psalms corpus (P13-5): the LXX shepherd verse at Greek 22.1
  # and the WEB shepherd verse at Hebrew 23.1, so the numbering remap is
  # exercised end to end through the CLI render.
  def with_psalms_corpus(registry)
    Dir.mktmpdir("nabu-cli-psalms") do |root|
      alignments = File.join(root, "alignments.yml")
      File.write(alignments, registry)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, alignments_path: alignments, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_psalms_witnesses(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_psalms_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "attribution",
      enabled: true
    )
    [["urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1", "Psalmi", "grc", "22.1", "Κύριος ποιμαίνει με"],
     ["urn:nabu:eng-web:psa", "Psalms", "eng", "23.1",
      "Yahweh is my shepherd: I shall lack nothing."]].each do |doc_urn, title, lang, tail, text|
      doc_id = catalog[:documents].insert(
        source_id: source_id, urn: doc_urn, title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      catalog[:passages].insert(
        document_id: doc_id, urn: "#{doc_urn}:#{tail}", sequence: 0, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: "{}"
      )
    end
  end

  def aligned_corpus_config(root, registry, extra_witness)
    yaml = registry || <<~YAML
      nt:
        title: "New Testament (parallel witnesses)"
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
    YAML
    yaml += "    - document: #{extra_witness}\n" if extra_witness
    alignments = File.join(root, "alignments.yml")
    File.write(alignments, yaml)
    sources = File.join(root, "sources.yml")
    File.write(sources, "# none\n")
    Nabu::Config.new(
      canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
      sources_path: sources, alignments_path: alignments, config_path: "(test)"
    )
  end

  def seed_aligned_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc",
      enabled: true
    )
    [["greek-nt", "Greek NT", "grc",
      "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων."],
     ["marianus", "Codex Marianus", "chu",
      "Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми."]].each do |tail, title, lang, text|
      doc_id = catalog[:documents].insert(
        source_id: source_id, urn: "urn:nabu:proiel:#{tail}", title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      catalog[:passages].insert(
        document_id: doc_id, urn: "urn:nabu:proiel:#{tail}:1", sequence: 0, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: JSON.generate(
          "citation" => "MARK 2.3",
          "tokens" => [{ "citation_part" => "MARK 2.3", "form" => "x" }]
        )
      )
    end
  end

  # A synced+indexed corpus for range/chapter align tests: two cts-verse
  # witnesses over Jonah 1 — "full" attests vv. 1..10, "partial" only 1 and 3.
  def range_registry_yaml
    <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
    YAML
  end

  def with_range_corpus
    Dir.mktmpdir("nabu-cli-range") do |root|
      config = aligned_corpus_config(root, range_registry_yaml, nil)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_range_witnesses(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  # Jonah 1 with a THIRD witness (ghost) whose document is never seeded — it is
  # not_synced across the whole range, so P11-9 lifts it to the header summary
  # and drops it from every per-ref block. full/partial seed as usual.
  def with_absent_range_corpus
    yaml = <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
          - label: ghost
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-z:jon
    YAML
    Dir.mktmpdir("nabu-cli-absent") do |root|
      config = aligned_corpus_config(root, yaml, nil)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_range_witnesses(catalog) # src-a + src-b only; src-z stays unsynced
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_range_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "open", enabled: true
    )
    seed_verse_book(catalog, source_id, "urn:nabu:src-a:jon", "ΙΩΝΑΣ", "grc",
                    (1..10).map { |v| ["1.#{v}", "greek verse #{v}"] })
    seed_verse_book(catalog, source_id, "urn:nabu:src-b:jon", "Jonas", "lat",
                    [["1.1", "latin one"], ["1.3", "latin three"]])
  end

  def seed_verse_book(catalog, source_id, urn, title, lang, verses)
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: urn, title: title, language: lang,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    verses.each_with_index do |(tail, text), sequence|
      catalog[:passages].insert(
        document_id: doc_id, urn: "#{urn}:#{tail}", sequence: sequence, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1,
        withdrawn: false, annotations_json: "{}"
      )
    end
  end

  def index_aligned_corpus(config, catalog)
    FileUtils.mkdir_p(File.dirname(config.fulltext_path))
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    Nabu::Store::Indexer.rebuild!(
      catalog: catalog, fulltext: fulltext,
      alignments: Nabu::AlignmentRegistry.load(config.alignments_path)
    )
    fulltext.disconnect
  end

  # A synced-and-indexed corpus with one document whose two passages carry the
  # keyword in different-length words (μῆνιν vs μηνιτισι), matched by one
  # prefix query — the KWIC alignment rig. Same parse-only sync pipeline.
  def with_kwic_corpus
    Dir.mktmpdir("nabu-cli-kwic") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "kwic.txt"),
                 "KWIC\nalpha μῆνιν beta gamma\ndelta μηνιτισι epsilon\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n  sync_policy: live\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      with_config(config) { capture_io { Nabu::CLI.start(%w[sync corpus --parse-only]) } }
      yield config
    end
  end

  # A synced-and-indexed corpus of ONE real treebank fixture (UD Ancient Greek
  # PROIEL), for the --lemma path: the lemma index only has rows when
  # annotations carry token lemmas, which TestAdapter's plaintext corpus never
  # does. Same parse-only sync pipeline as with_indexed_corpus.
  def with_treebank_corpus
    Dir.mktmpdir("nabu-cli-lemma") do |root|
      treebank = File.join(root, "canonical", "ud", "greek-proiel")
      FileUtils.mkdir_p(treebank)
      FileUtils.cp(File.expand_path("fixtures/ud/greek-proiel/grc_proiel-ud-test-head50.conllu", __dir__),
                   treebank)
      sources = File.join(root, "sources.yml")
      File.write(sources, "ud:\n  adapter: Nabu::Adapters::UniversalDependencies\n  " \
                          "enabled: true\n  sync_policy: live\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      with_config(config) do
        capture_io { Nabu::CLI.start(%w[sync ud --parse-only]) }
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

  # A built catalog holding two sibling CTS editions of one work (grc + eng,
  # aligned suffixes :1/:3, grc-only :2) for the show --parallel surface.
  def with_parallel_corpus
    Dir.mktmpdir("nabu-cli-parallel") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "attribution"
      )
      loader = Nabu::Store::Loader.new(db: db, source: source)
      loader.load([parallel_document(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]]),
                   parallel_document(ENG_URN, "eng", [%w[1 Wrath], %w[3 goddess]])], full: false)
      db.disconnect
      yield config
    end
  end

  def parallel_document(urn, language, passages)
    document = Nabu::Document.new(
      urn: urn, language: language, title: "Iliad", canonical_path: "/canonical/src/#{language}.xml"
    )
    passages.each_with_index do |(suffix, text), index|
      document << Nabu::Passage.new(urn: "#{urn}:#{suffix}", language: language, text: text, sequence: index)
    end
    document
  end

  # A verse-for-verse corpus (grc :1/:2/:3 ↔ eng :1/:2/:3, all 1:1) for the
  # byte-identical pair-form regression pin.
  def with_verse_corpus(&)
    build_parallel_corpus(
      parallel_document(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]]),
      parallel_document(ENG_URN, "eng", [%w[1 Wrath], %w[2 sing], %w[3 goddess]]), &
    )
  end

  # A card-cited corpus: grc lines 1.1..1.8, eng cards anchored at 1.1 (owns
  # 1.1–1.4) and 1.5 (owns 1.5–1.8) — the coarse span-grouped case.
  def with_card_corpus(&)
    build_parallel_corpus(
      parallel_document(GRC_URN, "grc", (1..8).map { |n| ["1.#{n}", "grc#{n}"] }),
      parallel_document(ENG_URN, "eng", [["1.1", "Block one"], ["1.5", "Block two"]]), &
    )
  end

  def build_parallel_corpus(*documents)
    Dir.mktmpdir("nabu-cli-parallel") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "attribution"
      )
      Nabu::Store::Loader.new(db: db, source: source).load(documents, full: false)
      db.disconnect
      yield config
    end
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
