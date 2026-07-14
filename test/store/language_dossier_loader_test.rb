# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Store::LanguageDossierLoader (P19-1): dossiers → derived language_records —
# replace-per-code semantics, record-grained counts, idempotency, the
# quarantine path, the absent-code sweep, and the replace_for_code! seam the
# accretion redirect refreshes through.
class LanguageDossierLoaderTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("local-language")

  def setup
    @db = store_test_db
    @source = Nabu::Store::Source.create(
      slug: "local-language", name: "Language dossiers (local shelf)",
      adapter_class: "Nabu::Adapters::LocalLanguage", license_class: "open"
    )
  end

  def adapter = Nabu::Adapters::LocalLanguage.new

  def loader = Nabu::Store::LanguageDossierLoader.new(db: @db, source: @source)

  def test_load_from_replaces_records_per_code_and_is_idempotent
    report = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, report.errored
    assert_equal 0, report.withdrawn
    added = report.added
    assert_operator added, :>=, 13, "five dossiers' lanes (name/family/context/extras/sections)"
    assert_equal %w[chu ine-pro sla-pro zle zlw],
                 @db[:language_records].distinct.select_order_map(:lang_code)
    assert_equal "liv", @db[:language_records].where(lang_code: "ine-pro", kind: "witness:liv").get(:source)

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
      assert_equal %w[chu ine-pro sla-pro zle zlw],
                   @db[:language_records].distinct.select_order_map(:lang_code),
                   "the five good dossiers load; the broken one quarantines"
    end
  end

  def test_full_load_sweeps_codes_whose_dossier_vanished_unatticked
    loader.load_from(adapter, workdir: FIXTURES)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      FileUtils.rm(File.join(dir, "zlw.md"))
      report = loader.load_from(adapter, workdir: dir)
      assert_operator report.withdrawn, :>=, 1
      refute_includes @db[:language_records].distinct.select_map(:lang_code), "zlw"
    end
  end

  def test_atticked_dossiers_keep_loading_as_retained
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      attic = File.join(dir, Nabu::Adapter::ATTIC_DIRNAME)
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(dir, "zlw.md"), File.join(attic, "zlw.md"))
      report = loader.load_from(adapter, workdir: dir)
      assert_equal 0, report.withdrawn
      assert_includes @db[:language_records].distinct.select_map(:lang_code), "zlw",
                      "a retired dossier's knowledge never vanishes"
    end
  end

  def test_replace_for_code_updates_in_place_and_drops_stale_kinds
    dossier = Nabu::LanguageDossier.new(code: "lit", name: "Lithuanian", context: "Baltic.")
    counts = Nabu::Store::LanguageDossierLoader.replace_for_code!(@db, dossier)
    assert_equal({ added: 2, updated: 0, skipped: 0 }, counts)

    revised = Nabu::LanguageDossier.new(code: "lit", name: "Lithuanian (revised)")
    counts = Nabu::Store::LanguageDossierLoader.replace_for_code!(@db, revised)
    assert_equal({ added: 0, updated: 1, skipped: 0 }, counts)
    rows = @db[:language_records].where(lang_code: "lit").to_h { |row| [row[:kind], row[:body]] }
    assert_equal({ "name" => "Lithuanian (revised)" }, rows, "the stale context lane is dropped")
  end

  def test_replace_for_code_degrades_on_a_catalog_predating_the_records_migration
    old_catalog = Sequel.sqlite
    dossier = Nabu::LanguageDossier.new(code: "lit", name: "Lithuanian")
    counts = Nabu::Store::LanguageDossierLoader.replace_for_code!(old_catalog, dossier)
    assert_equal({ added: 0, updated: 0, skipped: 0 }, counts)
  end
end
