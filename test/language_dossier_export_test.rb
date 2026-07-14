# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LanguageDossierExport (P19-1): THE one-shot canonical-memory
# migration — ledger language_notes (+ an optional seed yml for checkouts
# whose ledger never seeded) → dossier files. Latest-per-(code, kind),
# curated kinds as front matter/prose, programmatic kinds as provenance
# sections, absence-filling only, idempotent, dry-run honest.
class LanguageDossierExportTest < Minitest::Test
  include StoreTestDB

  def setup
    @ledger = ledger_test_db
  end

  def note!(code, kind, body, source: "seed:config/languages.yml", at: Time.new(2026, 7, 13))
    @ledger[:language_notes].insert(lang_code: code, kind: kind, body: body,
                                    source: source, created_at: at)
  end

  def export(dir, seed_path: nil, dry_run: false)
    Nabu::LanguageDossierExport.new(ledger: @ledger, dir: dir, seed_path: seed_path,
                                    now: Time.new(2026, 7, 14)).run!(dry_run: dry_run)
  end

  def test_exports_latest_notes_as_dossiers_with_provenance_sections
    note!("chu", "name", "Old Church Slavonic")
    note!("chu", "family", "South Slavic")
    note!("chu", "context", "The OCS canon (superseded).")
    note!("chu", "context", "The OCS canon, 9th–11th c.")
    note!("chu", "iecor", "IE-CoR variety: Old Church Slavonic.", source: "iecor")
    note!("ine-pro", "witness:liv", "305 PIE verbal roots.", source: "liv")
    Dir.mktmpdir do |dir|
      report = export(dir)
      assert_equal 2, report.written
      assert_equal 0, report.unchanged

      chu = Nabu::LanguageDossier.parse(File.read(File.join(dir, "chu.md")), code: "chu")
      assert_equal "Old Church Slavonic", chu.name
      assert_equal "South Slavic", chu.family
      assert_equal "The OCS canon, 9th–11th c.", chu.context, "the latest note per (code, kind) wins"
      section = chu.section("iecor")
      assert_equal "iecor", section.source
      assert_equal "2026-07-13", section.date, "per-record provenance dates ride the section headers"

      liv = Nabu::LanguageDossier.parse(File.read(File.join(dir, "ine-pro.md")), code: "ine-pro")
      assert_equal "liv", liv.section("witness:liv").source
    end
  end

  def test_export_is_idempotent
    note!("chu", "name", "Old Church Slavonic")
    Dir.mktmpdir do |dir|
      assert_equal 1, export(dir).written
      report = export(dir)
      assert_equal 0, report.written
      assert_equal 1, report.unchanged
    end
  end

  def test_export_fills_absences_only_and_never_clobbers_a_dossier
    note!("chu", "name", "Old Church Slavonic (ledger)")
    note!("chu", "family", "South Slavic")
    note!("chu", "iecor", "IE-CoR variety (ledger, older).", source: "iecor")
    Dir.mktmpdir do |dir|
      shelf = Nabu::LanguageShelf.new(dir: dir)
      shelf.write!(Nabu::LanguageDossier.new(
                     code: "chu", name: "Old Church Slavonic (owner-edited)",
                     sections: [Nabu::LanguageDossier::Section.new(
                       kind: "iecor", source: "iecor", date: "2026-07-14",
                       body: "IE-CoR variety (accreted after the redirect — newer than the ledger)."
                     )]
                   ))
      report = export(dir)
      assert_equal 2, report.lanes_kept, "the owner's name and the fresher iecor section are kept"
      dossier = shelf.load("chu")
      assert_equal "Old Church Slavonic (owner-edited)", dossier.name
      assert_match(/newer than the ledger/, dossier.section("iecor").body)
      assert_equal "South Slavic", dossier.family, "the absent lane is filled"
    end
  end

  def test_dry_run_reports_without_writing
    note!("chu", "name", "Old Church Slavonic")
    Dir.mktmpdir do |dir|
      report = export(dir, dry_run: true)
      assert_equal 1, report.written
      refute File.exist?(File.join(dir, "chu.md")), "dry-run touches nothing"
    end
  end

  def test_seed_yml_fills_gaps_the_ledger_does_not_cover
    note!("chu", "name", "Old Church Slavonic (ledger wins)")
    Dir.mktmpdir do |dir|
      seed = File.join(dir, "languages.yml")
      File.write(seed, <<~YAML)
        languages:
          chu:
            name: Old Church Slavonic (yml)
            context: Yml-only context.
        families:
          zle:
            name: East Slavic
      YAML
      shelf_dir = File.join(dir, "shelf")
      export(shelf_dir, seed_path: seed)
      shelf = Nabu::LanguageShelf.new(dir: shelf_dir)
      chu = shelf.load("chu")
      assert_equal "Old Church Slavonic (ledger wins)", chu.name
      assert_equal "Yml-only context.", chu.context
      assert_equal "East Slavic", shelf.load("zle").name, "family entries export at family grain"
    end
  end

  def test_degrades_on_a_ledger_predating_the_notes_table_and_without_a_ledger
    Dir.mktmpdir do |dir|
      report = Nabu::LanguageDossierExport.new(ledger: Sequel.sqlite, dir: dir).run!
      assert_equal 0, report.written
      report = Nabu::LanguageDossierExport.new(ledger: nil, dir: dir).run!
      assert_equal 0, report.written
    end
  end
end
