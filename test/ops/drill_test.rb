# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `rake ops:drill` core (P7-2): the fresh-machine restore drill, end to end,
# against a small TestAdapter corpus built in tmp. Proves the whole chain —
# back up → restore into a fresh root → rebuild from restored canonical →
# verify → golden replay → counts match the source of truth — without touching
# the live setup or the network.
# P77-r10: the drill_pure defect class in miniature — one urn claimed by
# two canonical files, so restored content is an artifact of encounter
# order. The drill must FAIL on it and hand over evidence, not shrug.
class CollidingDrillAdapter < TestAdapter
  def discover(workdir, &block)
    return enum_for(:discover, workdir) unless block

    refs = []
    super { |ref| refs << ref }
    refs.each(&block)
    yield Nabu::DocumentRef.new(source_id: SOURCE_ID, id: refs.first.id, path: refs.last.path)
  end
end

class DrillTest < Minitest::Test
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"
  ODYSSEY = "Odyssey\nἄνδρα\n"

  def setup
    @root = Dir.mktmpdir("nabu-drill-src")
    build_corpus
    # The "source of truth": build the live derived db once, as a real install
    # would have (a prior sync/rebuild). The drill backs THIS up.
    Nabu::Rebuild.new(config: live_config, registry: registry).run
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_drill_restores_rebuilds_verifies_and_matches_counts
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run

      assert_predicate report.backup, :ok?, "backup section(s) failed"
      assert_equal 0, report.rebuild_quarantined, "a clean restore rebuilds without quarantine"
      assert report.verify_clean, "verify must be clean against the restored, rebuilt catalog"
      assert_equal 0, report.golden_lost, "no golden query may be lost after restore"

      # The restored corpus matches the source of truth: 2 docs, 3 passages.
      assert_equal Nabu::Ops::Drill::Counts.new(documents: 2, passages: 3), report.restored_counts
      assert_equal report.source_counts, report.restored_counts
      assert_predicate report, :counts_match?
      assert_predicate report, :ok?
      # P77-r12: EVERY drill is the law's drill now — the render always
      # speaks the derivation oracles.
      assert_includes report.render, "law"
    end
  end

  # Found on the first LIVE drill (2026-07-07): the real corpus carries 9,316
  # honest quarantines (text-less papyri stubs etc.), and a faithful restore
  # REPRODUCES them — the drill must not read that as "not restorable". The
  # counts cross-check is the fidelity oracle: a genuinely lost document
  # shows up as a count mismatch, not as a quarantine tally.
  def test_drill_is_restorable_when_quarantines_match_the_source_expectation
    File.write(File.join(@root, "canonical", "corpus", "broken.txt"), "")
    Nabu::Rebuild.new(config: live_config, registry: registry).run # source of truth rebuilt WITH the honest quarantine

    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run

      assert_equal 1, report.rebuild_quarantined, "the restored corpus reproduces the source's quarantine"
      assert_equal report.source_counts, report.restored_counts
      assert_predicate report, :ok?, "quarantines faithful to the source are not a restore failure"
    end
  end

  def test_drill_writes_only_under_the_workspace_and_leaves_the_source_untouched
    before = source_snapshot
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run
      # The backup landed under the workspace, not beside the source.
      assert_path_exists File.join(workspace, "target", "canonical", "corpus", "one.txt")
      assert_path_exists File.join(workspace, "machine", "db", "catalog.sqlite3")
      # P77-r12: the backup hauls NO derived db — the machine's catalog
      # above came from the rebuild, never from the target.
      refute_path_exists File.join(workspace, "target", "db", "catalog.sqlite3")
    end
    assert_equal before, source_snapshot, "the drill must read, never mutate, its source"
  end

  # P71-8, THE LAW'S PROOF — since P77-r12 the ONLY mode: the backup
  # carries canonical/ + config/ + local/ and nothing derived, so every
  # restore re-mints every derived store, the lect journal matches the
  # live instrument (the rulings replay), and the grant/creep gates
  # answer from local/config with NO ledger.
  def test_the_drill_restores_the_three_folders_and_rederives_everything
    # Instance state that must survive through local/ alone:
    Nabu::LectRulings.append!(live_config.lect_rulings_path,
                              urn: "urn:nabu:corpus:one", code: "grc", lect_id: "grc:koine")
    gate = Nabu::GrantGate.new(ledger: nil, grants_path: live_config.grants_path)
    gate.record!(slug: "corpus", terms: "any use", how: "typed")
    FileUtils.mkdir_p(File.dirname(live_config.creep_acceptances_path))
    File.write(live_config.creep_acceptances_path,
               "acceptances:\n- source: corpus\n  baseline: 3\n  note: drill\n  at: \"2026-08-11\"\n")
    # Live journal state = what a rederive should reproduce:
    journal = Nabu::Store::LectJournal.open!(live_config.lects_journal_path)
    Nabu::Store::LectJournal.rederive!(journal, catalog: nil, config: live_config)
    journal.disconnect

    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run

      refute_path_exists File.join(report.machine_root, "db", "history.sqlite3"),
                         "the restore carries NO db/ files"
      assert report.lects_match, "the restored lect journal must equal the live derivation"
      assert report.links_match
      assert report.grants_quiet, "grants answer from local/config with no ledger"
      assert report.creep_quiet
      assert_equal report.source_counts, report.restored_counts
      assert_predicate report, :ok?
    end
  end

  # Q21 (P74, minted from the first live drill_pure failure 2026-08-12):
  # a failing drill must hand over evidence. Rig: tamper the LIVE catalog
  # after its rebuild (inject a stray passage) — the drill's fresh rebuild
  # then diverges from the "source of truth", and the report must NAME
  # the differing source with both counts, not just say MISMATCH.
  def test_a_count_mismatch_names_its_source_with_both_counts
    live = Nabu::Store.connect(live_config.catalog_path)
    doc_id = live[:documents].min(:id)
    live[:passages].insert(document_id: doc_id, urn: "urn:nabu:corpus:stray:9", sequence: 9,
                           language: "grc", text: "stray", text_normalized: "stray",
                           content_sha256: "stray", revision: 1)
    live.disconnect

    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run
      refute_predicate report, :counts_match?
      assert_equal 1, report.source_deltas.size
      slug, live_counts, restored_counts = report.source_deltas.first
      assert_equal "corpus", slug
      assert_equal Nabu::Ops::Drill::Counts.new(documents: 2, passages: 4), live_counts
      assert_equal Nabu::Ops::Drill::Counts.new(documents: 2, passages: 3), restored_counts

      rendered = report.render
      assert_includes rendered, "corpus", "the delta section names the source"
      assert_includes rendered, "live 2 docs / 4 passages", "both sides render"
      assert_includes rendered, "restored 2 docs / 3 passages"
    end
  end

  def test_a_clean_drill_carries_no_forensics
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run
      assert_predicate report, :ok?
      assert_empty report.verify_issues
      assert_empty report.source_deltas
      refute_includes report.render, "verify failures", "a clean report prints no forensic sections"
    end
  end

  # The rendering caps at 10 named entries per forensic section and
  # ANNOUNCES the truncation — never a silent cut (house doctrine).
  def test_forensic_rendering_names_issues_and_announces_truncation
    issues = (1..12).map do |i|
      Nabu::Verify::DocumentIssue.new(urn: "urn:nabu:corpus:doc#{i}", canonical_path: nil,
                                      kind: :mismatch, detail: "sha diverged")
    end
    report = forensic_report(verify_issues: issues,
                             source_deltas: [["corpus",
                                              Nabu::Ops::Drill::Counts.new(documents: 2, passages: 2),
                                              Nabu::Ops::Drill::Counts.new(documents: 2, passages: 3)]])
    rendered = report.render
    assert_includes rendered, "urn:nabu:corpus:doc1 (mismatch: sha diverged)"
    assert_includes rendered, "urn:nabu:corpus:doc10"
    refute_includes rendered, "urn:nabu:corpus:doc11", "capped at 10 named issues"
    assert_includes rendered, "… and 2 more", "the truncation is announced, never silent"
  end

  # -- P77-r10: a failing drill RETAINS its evidence ------------------------

  def test_a_failing_drill_persists_uncapped_evidence_into_the_workspace
    File.write(File.join(@root, "config", "sources.yml"),
               "corpus:\n  adapter: CollidingDrillAdapter\n  wired: true\n")
    Nabu::Rebuild.new(config: live_config, registry: registry).run
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run

      refute_predicate report, :ok?, "a duplicate-urn mint is not restorable-as-is"
      assert_equal 1, report.rebuild_collided,
                   "the loader's collision counter surfaces in the drill report (P77-r11)"
      assert_includes report.render, "URN COLLISION"
      assert_equal [:duplicate_urn], report.verify_issues.map(&:kind).uniq
      report_txt = File.join(workspace, "report.txt")
      issues_tsv = File.join(workspace, "verify-issues.tsv")
      assert File.exist?(report_txt), "the full report survives the run"
      assert File.exist?(issues_tsv), "every verify issue survives, machine-readable"
      assert_includes File.read(issues_tsv), "duplicate_urn"
      assert_includes report.render, "evidence", "the render points at the retained evidence"
    end
  end

  def test_the_persisted_report_is_uncapped_where_the_terminal_render_caps
    issues = (1..12).map do |i|
      Nabu::Verify::DocumentIssue.new(urn: "urn:nabu:corpus:doc#{i}", canonical_path: nil,
                                      kind: :mismatch, detail: "sha diverged")
    end
    report = forensic_report(verify_issues: issues, source_deltas: [])
    refute_includes report.render, "urn:nabu:corpus:doc11", "terminal render stays capped"
    assert_includes report.render(capped: false), "urn:nabu:corpus:doc12",
                    "the persisted render names EVERY issue"
  end

  def test_quarantines_render_their_per_source_breakdown
    report = forensic_report(verify_issues: [], source_deltas: [],
                             rebuild_quarantined: 7,
                             quarantine_by_source: [["corpus", 5], ["other", 2]])
    rendered = report.render
    assert_includes rendered, "quarantined 7"
    assert_includes rendered, "corpus 5"
    assert_includes rendered, "other 2"
  end

  # P77-r13 (found live 2026-08-17, by the owner's post-fix drill): the
  # doctrine never hard-deletes, so a long-lived catalog keeps withdrawn
  # document/passage rows forever — pure HISTORY that a fresh derivation
  # legitimately never re-mints. The counts oracle must count the LIVING
  # corpus only, or every legitimate withdrawal reads NOT RESTORABLE
  # forever (live: two withdrawn derge phantoms + 3,616 passage
  # withdrawals made a fully CONVERGED catalog fail the drill).
  def test_withdrawn_history_rows_do_not_fail_the_counts_oracle
    # Upstream drops two.txt entirely (document withdrawal) and one.txt
    # loses its last line (passage withdrawal within a revision); the
    # incremental full-load sweep records both — rows kept, flagged.
    FileUtils.rm(File.join(@root, "canonical", "corpus", "two.txt"))
    File.write(File.join(@root, "canonical", "corpus", "one.txt"), "Iliad\nμῆνιν\n")
    live = Nabu::Store.connect(live_config.catalog_path)
    Nabu::Store.setup!(live)
    source = Nabu::Store::Source.first(slug: "corpus")
    report = Nabu::Store::Loader.new(db: live, source: source)
                                .load_from(TestAdapter.new, workdir: File.join(@root, "canonical", "corpus"))
    live.disconnect
    assert_equal 1, report.withdrawn, "the rig's premise: one document withdrawn, rows kept"

    Dir.mktmpdir("nabu-drill-work") do |workspace|
      drill = Nabu::Ops::Drill.new(config: live_config, workspace: workspace).run
      assert_predicate drill, :counts_match?,
                       "withdrawn history is not loss — the LIVING corpora match"
      assert_empty drill.source_deltas
      assert_predicate drill, :ok?
    end
  end

  # -- P77-r12: refuse up front, crash never ---------------------------------

  # The 2026-08-15 lesson: two drills rsync'd the boot disk to 100% and
  # died mid-copy with 521 GB of half-written workspaces. The guard must
  # measure the footprint (2× the permanent folders + a rebuilt db/) against
  # the workspace volume and refuse — with the numbers — before ANY write.
  def test_the_space_guard_refuses_with_the_numbers_before_writing_anything
    disk = FakeDisk.new(tree: 10 * (1024**3), free: 1 * (1024**3))
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      error = assert_raises(Nabu::Ops::Drill::Error) do
        Nabu::Ops::Drill.new(config: live_config, workspace: workspace, disk: disk).run
      end
      assert_match(/needs ~/, error.message, "the refusal states the required footprint")
      assert_match(/GB free/, error.message, "the refusal states what the volume has")
      assert_empty Dir.children(workspace), "the refusal precedes any write"
    end
  end

  # P77-r14 (the 2026-08-17 13:11 refusal): the guard said "free space"
  # while the actual hog was our OWN kept workspace from the previous
  # failing drill, sitting unnamed in the same tmp root. The refusal
  # must point at leftover drill workspaces so the operator sees the
  # cleanup target without a manual hunt.
  def test_the_space_guard_names_leftover_drill_workspaces
    disk = FakeDisk.new(tree: 10 * (1024**3), free: 1 * (1024**3))
    Dir.mktmpdir("nabu-drill-rig") do |tmp_root|
      leftover = File.join(tmp_root, "nabu-drill20260816-99999-kept")
      FileUtils.mkdir_p(leftover)
      workspace = Dir.mktmpdir("nabu-drill", tmp_root)
      error = assert_raises(Nabu::Ops::Drill::Error) do
        Nabu::Ops::Drill.new(config: live_config, workspace: workspace, disk: disk).run
      end
      note = error.message[/NOTE: .*/]
      refute_nil note, "the refusal carries the leftover note"
      assert_includes note, leftover, "the refusal names the leftover workspace"
      assert_match(/10\.0 GB/, note, "with its size")
      refute_includes note, File.basename(workspace),
                      "the CURRENT (empty, about-to-die) workspace is not a leftover"
    end
  end

  # P77-r14 (owner ruling 2026-08-17: "it's your mess to clean"): the
  # drill sweeps ITS OWN prior workspaces before a new run — a kept
  # failing-drill workspace is evidence only until the next run
  # supersedes it, and at ~290 GB it otherwise blocks that run's space
  # guard. The small evidence files survive (salvaged beside the drill
  # logs); the bulk dies.
  def test_the_sweep_removes_prior_workspaces_and_salvages_their_evidence
    Dir.mktmpdir("nabu-drill-rig") do |rig|
      tmp_root = File.join(rig, "tmp")
      salvage_root = File.join(rig, "logs")
      kept = File.join(tmp_root, "nabu-drill20260816-84905-kept")
      FileUtils.mkdir_p(File.join(kept, "machine"))
      File.write(File.join(kept, "report.txt"), "the uncapped report")
      File.write(File.join(kept, "verify-issues.tsv"), "urn\tkind\tdetail")
      crashed = File.join(tmp_root, "nabu-drill20260815-11111-crashed")
      FileUtils.mkdir_p(crashed)

      swept = Nabu::Ops::Drill.sweep_prior_workspaces!(tmp_root: tmp_root, salvage_root: salvage_root)

      refute_path_exists kept, "the bulk dies"
      refute_path_exists crashed
      assert_equal([crashed, kept], swept.map { |s| s[:workspace] })
      salvage = swept.last[:salvaged]
      assert_equal "the uncapped report", File.read(File.join(salvage, "report.txt"))
      assert_path_exists File.join(salvage, "verify-issues.tsv")
      assert_nil swept.first[:salvaged], "an evidence-less workspace salvages nothing"
    end
  end

  # A failed backup section used to be discovered only by ok? at the END —
  # after an hours-long doomed restore+rebuild+verify. It aborts BEFORE
  # restore now, naming the section and rsync's own words.
  def test_a_failed_backup_section_aborts_before_the_restore
    shell = SectionFailingShell.new(match: "canonical")
    Dir.mktmpdir("nabu-drill-work") do |workspace|
      error = assert_raises(Nabu::Ops::Drill::Error) do
        Nabu::Ops::Drill.new(config: live_config, workspace: workspace, shell: shell).run
      end
      assert_match(/backup failed/i, error.message)
      assert_match(/canonical/, error.message, "the failed section is named")
      assert_match(/no space left/i, error.message, "rsync's stderr rides in the message")
      refute_path_exists File.join(workspace, "machine"), "no doomed restore after a failed backup"
    end
  end

  private

  # A Shell stand-in: rsync invocations whose argv mentions +match+ fail
  # with an ENOSPC-shaped stderr; everything else runs for real.
  class SectionFailingShell
    def initialize(match:)
      @match = match
    end

    def run(*argv)
      if argv.first == "rsync" && argv.any? { |a| a.include?(@match) }
        raise Nabu::Shell::Error.new("command failed (exit 1): rsync — rsync: write failed: " \
                                     "No space left on device (28)",
                                     status: 1, stderr: "rsync: write failed: No space left on device (28)")
      end

      Nabu::Shell.run(*argv)
    end
  end

  # A Disk stand-in with fixed measurements — the guard's math, not the
  # box's actual du/df, is what the test pins.
  class FakeDisk
    def initialize(tree:, free:)
      @tree = tree
      @free = free
    end

    def tree_bytes(_path) = @tree
    def free_bytes(_path) = @free
  end

  def forensic_report(verify_issues:, source_deltas:, rebuild_quarantined: 0, quarantine_by_source: [])
    Nabu::Ops::Drill::Report.new(
      target: "/t", machine_root: "/m",
      backup: Nabu::Backup::Result.new(target: "/t", dry_run: false, sections: [], duration: 0),
      rebuild_quarantined: rebuild_quarantined,
      quarantine_by_source: quarantine_by_source,
      rebuild_collided: 0,
      verify_clean: verify_issues.empty?,
      golden_found: 0, golden_lost: 0, golden_skipped: 0,
      source_counts: nil, restored_counts: nil,
      lects_match: true, links_match: true,
      grants_quiet: true, creep_quiet: true,
      verify_issues: verify_issues, source_deltas: source_deltas
    )
  end

  def registry
    Nabu::SourceRegistry.load(File.join(@root, "config", "sources.yml"))
  end

  def live_config
    Nabu::Config.new(
      canonical_dir: File.join(@root, "canonical"),
      db_dir: File.join(@root, "db"),
      sources_path: File.join(@root, "config", "sources.yml"),
      config_path: File.join(@root, "config", "nabu.yml")
    )
  end

  def build_corpus
    corpus = File.join(@root, "canonical", "corpus")
    FileUtils.mkdir_p(corpus)
    File.write(File.join(corpus, "one.txt"), ILIAD)
    File.write(File.join(corpus, "two.txt"), ODYSSEY)

    cfg = File.join(@root, "config")
    FileUtils.mkdir_p(cfg)
    File.write(File.join(cfg, "sources.yml"), "corpus:\n  adapter: TestAdapter\n  wired: true\n")
    File.write(File.join(cfg, "nabu.yml"), "# nabu config\n")
  end

  # Content of every canonical file, to prove the drill never mutates the source.
  def source_snapshot
    base = File.join(@root, "canonical")
    Dir.glob("**/*", File::FNM_DOTMATCH, base: base)
       .map { |rel| File.join(base, rel) }
       .select { |path| File.file?(path) }
       .to_h { |path| [path, File.read(path)] }
  end
end
