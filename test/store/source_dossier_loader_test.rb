# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Store::SourceDossierLoader (P24-0): dossiers → derived source_records —
# replace-per-slug semantics, record-grained counts, idempotency, the
# quarantine path, the absent-slug sweep, and the replace_for_slug! seam
# the accretion path refreshes through.
class SourceDossierLoaderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("local-source")

  def setup
    @db = store_test_db
    @source = Nabu::Store::Source.create(
      slug: "local-source", name: "Source dossiers (local shelf)",
      adapter_class: "Nabu::Adapters::LocalSource", license_class: "open"
    )
  end

  def adapter = Nabu::Adapters::LocalSource.new

  def loader = Nabu::Store::SourceDossierLoader.new(db: @db, source: @source)

  def test_load_from_replaces_records_per_slug_and_is_idempotent
    report = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, report.errored
    assert_equal 0, report.withdrawn
    added = report.added
    assert_operator added, :>=, 8, "three dossiers' lanes (description/themes/notes/extras/sections)"
    assert_equal %w[edh lexica local-language],
                 @db[:source_records].distinct.select_order_map(:slug)
    assert_equal "edh-survey",
                 @db[:source_records].where(slug: "edh", kind: "witness:survey").get(:provenance)

    again = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, again.added
    assert_equal 0, again.updated
    assert_equal added, again.skipped, "a reload of unchanged dossiers writes nothing"
  end

  def test_quarantine_counts_the_file_and_never_blocks_the_batch
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      FileUtils.mv(File.join(dir, "broken.md.quarantine"), File.join(dir, "bro.md"))
      report = loader.load_from(adapter, workdir: dir)
      assert_equal 1, report.errored
      assert_equal %w[edh lexica local-language],
                   @db[:source_records].distinct.select_order_map(:slug),
                   "the three good dossiers load; the broken one quarantines"
    end
  end

  def test_full_load_sweeps_slugs_whose_dossier_vanished_unatticked
    loader.load_from(adapter, workdir: FIXTURES)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      FileUtils.rm(File.join(dir, "lexica.md"))
      report = loader.load_from(adapter, workdir: dir)
      assert_operator report.withdrawn, :>=, 1
      refute_includes @db[:source_records].distinct.select_map(:slug), "lexica"
    end
  end

  def test_atticked_dossiers_keep_loading_as_retained
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      attic = File.join(dir, Nabu::Adapter::ATTIC_DIRNAME)
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(dir, "lexica.md"), File.join(attic, "lexica.md"))
      report = loader.load_from(adapter, workdir: dir)
      assert_equal 0, report.withdrawn
      assert_includes @db[:source_records].distinct.select_map(:slug), "lexica",
                      "a retired dossier's knowledge never vanishes"
    end
  end

  def test_replace_for_slug_updates_in_place_and_drops_stale_kinds
    dossier = Nabu::SourceDossier.new(slug: "gretil", description: "Sanskrit corpus.", note: "GRETIL.")
    counts = Nabu::Store::SourceDossierLoader.replace_for_slug!(@db, dossier)
    assert_equal({ added: 2, updated: 0, skipped: 0 }, counts)

    revised = Nabu::SourceDossier.new(slug: "gretil", description: "Sanskrit corpus (revised).")
    counts = Nabu::Store::SourceDossierLoader.replace_for_slug!(@db, revised)
    assert_equal({ added: 0, updated: 1, skipped: 0 }, counts)
    rows = @db[:source_records].where(slug: "gretil").to_h { |row| [row[:kind], row[:body]] }
    assert_equal({ "description" => "Sanskrit corpus (revised)." }, rows, "the stale note lane is dropped")
  end

  def test_replace_for_slug_degrades_on_a_catalog_predating_the_records_migration
    old_catalog = Sequel.sqlite
    dossier = Nabu::SourceDossier.new(slug: "gretil", description: "Sanskrit corpus.")
    counts = Nabu::Store::SourceDossierLoader.replace_for_slug!(old_catalog, dossier)
    assert_equal({ added: 0, updated: 0, skipped: 0 }, counts)
  end
end
