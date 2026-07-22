# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# End-to-end retention contract (P5-2): if a document is scrapped upstream,
# local storage marks it and KEEPS it usable — through sync, search, show,
# status, verify and rebuild. Upstream is a local fixture git repo of
# TestAdapter documents; canonical/<slug>/ is its clone via the shared
# GitFetch path (no network anywhere).
class RetentionTest < Minitest::Test
  include StoreTestDB

  SLUG = "test_adapter"
  DOCS = {
    "alpha.txt" => "Alpha\nμῆνιν ἄειδε θεά\n",
    "beta.txt" => "Beta\nἄνδρα μοι ἔννεπε\n",
    "gamma.txt" => "Gamma\nπολύτροπον μάλα\n",
    "delta.txt" => "Delta\nὃς πολλὰ πλάγχθη\n",
    "epsilon.txt" => "Epsilon\nΤροίης ἱερὸν πτολίεθρον\n"
  }.freeze

  # TestAdapter armed with the shared git fetch (the same path every real
  # git-based adapter delegates to), pointed at a local upstream repo.
  class GitTestAdapter < TestAdapter
    class << self
      attr_accessor :upstream_url
    end

    def fetch(workdir, progress: nil, force: false)
      git_fetch!(repo_url: self.class.upstream_url, workdir: workdir, progress: progress, force: force)
    end
  end

  def setup
    @ledger = ledger_test_db
    @db = store_test_db
    @root = Dir.mktmpdir("nabu-retention")
    @canonical = File.join(@root, "canonical")
    @upstream = File.join(@root, "upstream")
    FileUtils.mkdir_p(@canonical)
    make_repo(@upstream, DOCS)
    GitTestAdapter.upstream_url = @upstream
    @runner = Nabu::SyncRunner.new(config: config, registry: registry, db: @db, ledger: @ledger)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # --- the owner requirement, end to end -----------------------------------

  def test_upstream_deletion_attics_the_file_and_retires_the_document_still_live
    assert_equal 5, @runner.sync(SLUG).load_report.added

    delete_upstream("alpha.txt") # 1 of 5 = 20%, at the threshold: no trip
    vanished_at = head(@upstream)
    outcome = @runner.sync(SLUG)

    refute outcome.aborted?
    assert_equal 0, outcome.load_report.withdrawn, "retired is not withdrawn"

    # The canonical file survives under the attic, relative path preserved.
    attic_file = File.join(workdir, ".attic", "alpha.txt")
    assert File.file?(attic_file)
    assert_equal DOCS["alpha.txt"], File.read(attic_file)
    refute File.exist?(File.join(workdir, "alpha.txt")), "the live tree follows upstream"

    # The document is retired, NOT withdrawn — and journaled with the sha it
    # vanished at.
    doc = doc_row("alpha")
    assert doc.retired_upstream
    refute doc.withdrawn
    assert_equal doc.id, doc.passages.first.document_id
    refute doc.passages.first.withdrawn
    retired = Nabu::Store::Provenance.where(document_id: doc.id, event: "retired").all
    assert_equal 1, retired.size
    assert_equal({ "upstream_sha" => vanished_at }, JSON.parse(retired.first.params_json))

    # Retired documents stay in the corpus: indexed, searchable, exportable.
    assert_search_hit "μῆνιν", urn("alpha")
    export = Nabu::Query::Export.new(catalog: @db).run(format: "plain", lang: nil, license: nil).to_a
    assert(export.any? { |line| line.include?("μῆνιν") }, "retired passages export normally")

    # status counts it; show labels it.
    status = Nabu::StatusReport.render(registry: registry, db: @db, ledger: @ledger)
    assert_match(/docs=5 pass=5 retired=1/, status)
    shown = Nabu::Query::Show.new(catalog: @db).run(urn("alpha"))
    assert shown.retired_upstream
    refute shown.withdrawn

    # verify re-hashes the attic copy cleanly (canonical_path moved with it).
    assert_predicate Nabu::Verify.new(config: config, registry: registry, db: @db).run, :clean?

    # Re-sync is idempotent: no new provenance, still retired.
    events_before = Nabu::Store::Provenance.count
    assert_equal 5, @runner.sync(SLUG).load_report.skipped
    assert_equal events_before, Nabu::Store::Provenance.count
    assert doc_row("alpha").refresh.retired_upstream
  end

  def test_rebuild_replays_the_attic_so_retired_documents_survive
    @runner.sync(SLUG)
    delete_upstream("alpha.txt")
    @runner.sync(SLUG)

    Nabu::Rebuild.new(config: config, registry: registry).run

    fresh = Nabu::Store.connect(config.catalog_path)
    begin
      row = fresh[:documents].where(urn: urn("alpha")).first
      refute_nil row, "the attic document must replay through rebuild"
      assert row.fetch(:retired_upstream), "still flagged retired after rebuild"
      refute row.fetch(:withdrawn)
      assert_equal 5, fresh[:documents].where(withdrawn: false).count
      retired_events = fresh[:provenance].where(document_id: row.fetch(:id), event: "retired").count
      assert_equal 1, retired_events, "rebuild re-journals retirement from the attic manifest"
    ensure
      fresh.disconnect
    end
  end

  # --- the breaker, relocated before the merge ------------------------------

  def test_mass_deletion_trips_the_breaker_with_the_canonical_tree_byte_unchanged
    @runner.sync(SLUG)
    delete_upstream("alpha.txt", "beta.txt") # 2 of 5 = 40% > 20%
    before = tree_snapshot(workdir)

    outcome = @runner.sync(SLUG)

    assert outcome.aborted?
    assert_equal 5, outcome.breaker.existing_count
    assert_equal 2, outcome.breaker.would_withdraw_count
    assert_equal "aborted", Nabu::Store::Run.order(:id).last.status
    assert_equal before, tree_snapshot(workdir),
                 "a tripped breaker aborts with the canonical tree byte-unchanged (no merge, no attic)"
    refute doc_row("alpha").retired_upstream
    assert_equal 5, Nabu::Store::Document.where(withdrawn: false).count

    # --force proceeds: files atticked, docs retired — nothing is lost.
    forced = @runner.sync(SLUG, force: true)
    refute forced.aborted?
    assert_equal 0, forced.load_report.withdrawn
    assert File.file?(File.join(workdir, ".attic", "alpha.txt"))
    assert File.file?(File.join(workdir, ".attic", "beta.txt"))
    assert doc_row("alpha").retired_upstream
    assert doc_row("beta").retired_upstream
    assert_equal 5, Nabu::Store::Document.where(withdrawn: false).count, "nothing was lost"
    assert_equal 2, Nabu::Store::Document.where(retired_upstream: true).count
  end

  # --- self-healing ----------------------------------------------------------

  def test_reappearing_document_unretires_and_supersedes_its_attic_copy
    @runner.sync(SLUG)
    delete_upstream("alpha.txt")
    @runner.sync(SLUG)
    assert doc_row("alpha").retired_upstream

    commit_upstream("alpha.txt" => DOCS["alpha.txt"]) # upstream restores it
    @runner.sync(SLUG)

    doc = doc_row("alpha")
    refute doc.retired_upstream, "a urn discovered live again flips back"
    refute doc.withdrawn
    assert_equal 1, Nabu::Store::Provenance.where(document_id: doc.id, event: "unretired").count
    # The attic copy still exists (first copy wins) but is superseded by the
    # live file — journaled once, then silent.
    assert File.file?(File.join(workdir, ".attic", "alpha.txt"))
    assert_equal 1, Nabu::Store::Provenance.where(document_id: doc.id, event: "superseded").count
    @runner.sync(SLUG)
    assert_equal 1, Nabu::Store::Provenance.where(document_id: doc.id, event: "superseded").count,
                 "superseded is journaled once, not per sync"
  end

  private

  def config
    Nabu::Config.new(canonical_dir: @canonical, db_dir: File.join(@root, "db"),
                     sources_path: "(n/a)", config_path: "(test)")
  end

  def registry
    Nabu::SourceRegistry.new(
      [Nabu::SourceRegistry::Entry.new(slug: SLUG, adapter_class_name: GitTestAdapter.name,
                                       enabled: true, sync_policy: "auto")]
    )
  end

  def workdir = File.join(@canonical, SLUG)

  def urn(slug) = "urn:nabu:test_adapter:#{slug}"

  def doc_row(slug) = Nabu::Store::Document.first(urn: urn(slug))

  def assert_search_hit(token, expected_urn)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    results = Nabu::Query::Search.new(catalog: @db, fulltext: fulltext).run(token, lang: nil, license: nil, limit: 20)
    assert(results.any? { |hit| hit.urn.start_with?(expected_urn) },
           "expected a fulltext hit for #{token.inspect} in #{expected_urn}")
  ensure
    fulltext&.disconnect
  end

  def make_repo(dir, files)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    write_files(dir, files)
    git(dir, "add", ".")
    commit(dir, "seed")
  end

  def commit_upstream(files)
    write_files(@upstream, files)
    git(@upstream, "add", ".")
    commit(@upstream, "update")
  end

  def delete_upstream(*relpaths)
    git(@upstream, "rm", "-q", *relpaths)
    commit(@upstream, "delete #{relpaths.join(', ')}")
  end

  def write_files(dir, files)
    files.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def commit(dir, message)
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end

  def head(dir) = git(dir, "rev-parse", "HEAD")

  def tree_snapshot(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir)
       .reject { |rel| rel == ".git" || rel.start_with?(".git/") || rel.end_with?("/.", "/..") }
       .sort
       .map { |rel| [rel, File.file?(File.join(dir, rel)) ? File.binread(File.join(dir, rel)) : :dir] }
  end
end
