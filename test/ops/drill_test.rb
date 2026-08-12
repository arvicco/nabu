# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `rake ops:drill` core (P7-2): the fresh-machine restore drill, end to end,
# against a small TestAdapter corpus built in tmp. Proves the whole chain —
# back up → restore into a fresh root → rebuild from restored canonical →
# verify → golden replay → counts match the source of truth — without touching
# the live setup or the network.
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
    end
    assert_equal before, source_snapshot, "the drill must read, never mutate, its source"
  end

  # P71-8, THE LAW'S PROOF: pure mode restores ONLY canonical/ + config/
  # + local/ (no db/) — the rebuild re-mints every derived store, the
  # lect journal matches the live instrument (the rulings replay), and
  # the grant/creep gates answer from local/config with NO ledger.
  def test_pure_drill_restores_the_three_folders_and_rederives_everything
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
      report = Nabu::Ops::Drill.new(config: live_config, workspace: workspace, pure: true).run

      refute_path_exists File.join(report.machine_root, "db", "history.sqlite3"),
                         "pure mode restores NO db/ files"
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

  private

  def forensic_report(verify_issues:, source_deltas:)
    Nabu::Ops::Drill::Report.new(
      target: "/t", machine_root: "/m",
      backup: Nabu::Backup::Result.new(target: "/t", dry_run: false, sections: [], duration: 0),
      rebuild_quarantined: 0, verify_clean: verify_issues.empty?,
      golden_found: 0, golden_lost: 0, golden_skipped: 0,
      source_counts: nil, restored_counts: nil,
      pure: false, lects_match: true, links_match: true,
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
