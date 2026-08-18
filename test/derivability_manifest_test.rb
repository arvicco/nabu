# frozen_string_literal: true

require "test_helper"
require "sequel/extensions/migration"

# THE DERIVABILITY LAW's teeth (P71-4, owner-ruled 2026-08-11): every
# table in every store maps to exactly one declared kind, and every
# DERIVED store names the rebuild stage that re-mints it. A new
# migration minting a table WITHOUT a classification here fails the
# suite the day it lands — the moment the law must be answered (this is
# the posture discipline applied to persistence). The ledger's tables
# classify LOCAL-INSTANCE: the file lives at local/history.sqlite3,
# part of the backup's permanent set, never under db/.
class DerivabilityManifestTest < Minitest::Test
  # kind ∈ :derived (db/ — pure f(canonical, config, local); re-minted
  # by the named rebuild stage) | :local_instance (local/ — permanent,
  # backed up, never derived).
  # fulltext.sqlite3 carries no migration track at all — the Indexer
  # mints every table inside a rebuild, so it is derived BY CONSTRUCTION
  # and a new fulltext table cannot land outside a rebuild stage.
  MANIFEST = {
    catalog: {
      kind: :derived, stage: "the whole corpus replay + derived lanes",
      tables: %w[
        derivation_stamps dictionaries dictionary_citations
        dictionary_entries dictionary_reflexes document_axes
        document_facets documents enrichments language_names
        language_records lect_stats passages place_crosswalk place_index
        place_index_names provenance source_records source_stats
        source_stats_languages sources urn_notes
      ]
    },
    links: {
      kind: :derived, stage: "links",
      tables: %w[links link_runs]
    },
    lects: {
      kind: :derived, stage: "lect journal",
      tables: %w[lect_assignments]
    },
    ledger: {
      kind: :local_instance, stage: nil,
      tables: %w[
        runs pins revisions language_notes quarantine_baselines
        source_probes grant_acknowledgments creep_acceptances
        stage_timings
      ]
    }
  }.freeze

  # FTS5/internal shadow tables the classifications don't enumerate.
  SHADOW = /\A(schema_info|sqlite_\w+|\w+_(config|data|docsize|idx|content|segments|segdir))\z/

  def tables_of(db)
    db.tables.map(&:to_s).grep_v(SHADOW).sort
  end

  def test_every_catalog_table_is_classified
    db = Sequel.sqlite
    Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, allow_missing_migration_files: true)
    assert_classified :catalog, tables_of(db)
  ensure
    db&.disconnect
  end

  def test_every_links_table_is_classified
    db = Sequel.sqlite
    Sequel::Migrator.run(db, Nabu::Store::LinksJournal::MIGRATIONS_DIR)
    assert_classified :links, tables_of(db)
  ensure
    db&.disconnect
  end

  def test_every_lects_table_is_classified
    db = Sequel.sqlite
    Sequel::Migrator.run(db, Nabu::Store::LectJournal::MIGRATIONS_DIR)
    assert_classified :lects, tables_of(db)
  ensure
    db&.disconnect
  end

  def test_every_ledger_table_is_classified
    db = Sequel.sqlite
    Sequel::Migrator.run(db, Nabu::Store::Ledger::MIGRATIONS_DIR)
    assert_classified :ledger, tables_of(db)
  ensure
    db&.disconnect
  end

  # Every DERIVED store's stage really exists in the full rebuild — a
  # derived store without a rebuild stage is a bug, not a posture. (A
  # grep pin, honest about being one: the stage strings are the
  # progress-reporter names rebuild.rb declares.)
  def test_every_derived_store_names_a_live_rebuild_stage
    rebuild_src = File.read(File.expand_path("../lib/nabu/rebuild.rb", __dir__))
    assert_includes rebuild_src, 'progress&.stage("links")'
    assert_includes rebuild_src, 'progress&.stage("lect journal")'
    # The catalog's "stage" is the replay itself + its derived lanes.
    assert_includes rebuild_src, "progress&.stage(entry.slug)"
  end

  private

  def assert_classified(store, actual)
    declared = MANIFEST.fetch(store).fetch(:tables).sort
    unclassified = actual - declared
    vanished = declared - actual
    assert_empty unclassified,
                 "#{store}: UNCLASSIFIED table(s) #{unclassified.join(', ')} — a new table must " \
                 "declare its kind in this manifest the day it lands (the derivability law)"
    assert_empty vanished,
                 "#{store}: manifest lists #{vanished.join(', ')} but the migrations mint no such " \
                 "table — prune the manifest"
  end
end
