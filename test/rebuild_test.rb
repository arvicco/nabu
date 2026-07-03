# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu rebuild` core (P1-5). Rebuild manages its own file-backed SQLite, so —
# unlike the in-memory store tests — these build a real db file under a tmpdir
# and reconnect to it to inspect the result. TestAdapter is the source; the
# registry is built from a sources.yml written into the tmpdir.
class RebuildTest < Minitest::Test
  # TestAdapter variant that quarantines one specific ref (a "parser
  # regression" on rebuild). Top-level-resolvable via its full nested name.
  class PoisonAdapter < TestAdapter
    def parse(document_ref)
      raise Nabu::ParseError, "poisoned" if document_ref.id == "urn:nabu:test_adapter:bad"

      super
    end
  end

  # A short TestAdapter document: line 1 title, remaining lines passages.
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"
  ODYSSEY = "Odyssey\nἄνδρα\n"

  def setup
    @root = Dir.mktmpdir("nabu-rebuild")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- acceptance: reproducible modulo ids ---------------------------------

  def test_rebuild_reproduces_identical_passage_rows_modulo_ids
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD, "two.txt" => ODYSSEY)

    first = rebuilder.run
    assert_equal %w[corpus], first.outcomes.map(&:slug)
    assert_equal 2, first.outcomes.first.report.added # two documents
    snapshot_before = passage_snapshot
    assert_equal 3, snapshot_before.size # μῆνιν, ἄειδε, ἄνδρα

    second = rebuilder.run

    # A second rebuild off the same canonical dir yields byte-identical passage
    # content, and revisions reset to 1 both times (fresh load, never revised).
    assert_equal snapshot_before, passage_snapshot
    assert(snapshot_before.all? { |row| row.fetch(:revision) == 1 })
    assert_equal %w[corpus], second.outcomes.map(&:slug)
  end

  # -- dry-run touches nothing ---------------------------------------------

  def test_plan_lists_actions_and_changes_nothing
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
      ghost:
        adapter: TestAdapter
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    rebuilder.run # build a db first
    path = catalog_path
    before_mtime = File.mtime(path)
    before_bytes = File.binread(path)

    plan = rebuilder.plan

    assert_equal path, plan.db_path
    assert plan.db_exists
    assert_equal [["corpus", :replay], ["ghost", :skip_no_canonical]], plan.items
    # The db file is untouched: same mtime, same bytes.
    assert_equal before_mtime, File.mtime(path)
    assert_equal before_bytes, File.binread(path)
  end

  # -- skip when no canonical data -----------------------------------------

  def test_sources_without_canonical_data_are_skipped
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
      empty-src:
        adapter: TestAdapter
      absent-src:
        adapter: TestAdapter
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)
    FileUtils.mkdir_p(File.join(@canonical, "empty-src")) # exists but empty

    result = rebuilder.run

    assert_equal %w[corpus], result.outcomes.map(&:slug)
    assert_equal %w[absent-src empty-src], result.skips.map(&:slug).sort
    assert(result.skips.all? { |skip| skip.reason == :no_canonical })
    # A skip is not a run: only the replayed source gets a runs row / sources row.
    with_db do
      assert_equal 1, Nabu::Store::Run.count
      assert_equal %w[corpus], Nabu::Store::Source.select_order_map(:slug)
    end
  end

  # -- errored > 0 surfaces a warning --------------------------------------

  def test_quarantined_document_surfaces_a_warning
    write_sources(<<~YAML)
      corpus:
        adapter: RebuildTest::PoisonAdapter
    YAML
    write_canonical("corpus", "good.txt" => ILIAD, "bad.txt" => "Bad\nx\n")

    result = rebuilder.run

    outcome = result.outcomes.fetch(0)
    assert_equal 1, outcome.report.added   # good.txt loaded
    assert_equal 1, outcome.report.errored # bad.txt quarantined
    assert_predicate outcome, :warning?
    assert_equal [outcome], result.warnings
    # The batch still succeeded (quarantine never aborts): a run row exists.
    with_db { assert_equal 1, Nabu::Store::Run.where(status: "succeeded").count }
  end

  # -- disabled source with local data is still replayed -------------------

  def test_disabled_source_with_canonical_data_is_replayed
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: false
    YAML
    write_canonical("corpus", "one.txt" => ILIAD)

    result = rebuilder.run

    assert_equal %w[corpus], result.outcomes.map(&:slug)
    assert_empty result.skips
    assert_equal 2, passage_snapshot.size
    # sync_source! seeds the row's enabled from the registry entry (disabled).
    with_db { refute Nabu::Store::Source.first(slug: "corpus").enabled }
  end

  # -- one succeeded run row per rebuilt source ----------------------------

  def test_writes_one_succeeded_run_row_per_rebuilt_source
    write_sources(<<~YAML)
      alpha:
        adapter: TestAdapter
      beta:
        adapter: TestAdapter
    YAML
    # Distinct filenames per source keep the minted urns from colliding on the
    # global documents.urn index (TestAdapter mints urns from the filename).
    write_canonical("alpha", "a.txt" => ILIAD)
    write_canonical("beta", "b.txt" => ODYSSEY)

    result = rebuilder.run

    assert_equal %w[alpha beta], result.outcomes.map(&:slug)
    runs = with_db do
      Nabu::Store::Run.order(:id).all.map { |run| [run.source_id, run.status] }
    end
    assert_equal 2, runs.size
    assert(runs.all? { |(_source_id, status)| status == "succeeded" })
    assert_equal 2, runs.map(&:first).uniq.size # one per source
  end

  # -- helpers -------------------------------------------------------------

  private

  def rebuilder
    Nabu::Rebuild.new(config: config, registry: Nabu::SourceRegistry.load(@sources_path))
  end

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: @db_dir,
      sources_path: @sources_path, config_path: "(test)"
    )
  end

  def catalog_path = config.catalog_path

  def write_sources(yaml) = File.write(@sources_path, yaml)

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  # Reconnect to the rebuilt file db and yield it, rebinding the models.
  def with_db
    db = Nabu::Store.connect(catalog_path)
    Nabu::Store.setup!(db)
    yield db
  ensure
    db&.disconnect
  end

  # Passage rows reduced to the content-bearing columns (ids excluded).
  def passage_snapshot
    with_db do
      Nabu::Store::Passage.order(:urn).all.map do |passage|
        passage.values.slice(
          :urn, :sequence, :language, :text, :text_normalized,
          :annotations_json, :content_sha256, :revision
        )
      end
    end
  end
end
