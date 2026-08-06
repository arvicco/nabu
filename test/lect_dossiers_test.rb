# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LectDossiers (P60 rider, the P58-6/P59-3 deferral): the registry
# stage ladder accreted into EXISTING language dossiers as a structured
# "stages" section, through the sanctioned LanguageShelf gateway. Registry
# facts only — bands, names, modes; never live counts (those stay on the
# live card: a count snapshot in permanent canonical memory would only go
# stale). Anchors without a dossier file are skipped, never skeletonized —
# family codes (ine, gmw) are not language dossiers.
class LectDossiersTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")

  def lects
    @lects ||= Nabu::Lects.load(FIXTURES)
  end

  def with_shelf
    Dir.mktmpdir do |dir|
      shelf = Nabu::LanguageShelf.new(dir: dir)
      yield shelf, dir
    end
  end

  def seed_dossier(dir, code, name)
    File.write(File.join(dir, "#{code}.md"), <<~MD)
      ---
      code: #{code}
      name: #{name}
      ---
      Curated prose that must survive verbatim.
    MD
  end

  def test_accretes_a_stages_section_into_existing_dossiers_only
    with_shelf do |shelf, dir|
      seed_dossier(dir, "lat", "Latin")
      report = Nabu::LectDossiers.new(lects: lects, shelf: shelf).run!(now: Time.utc(2026, 8, 6))

      assert_equal %w[lat], report.written
      refute File.file?(File.join(dir, "sux.md")), "no skeleton spam — absent dossiers are skipped"
      assert_includes report.skipped, "sux"

      rendered = File.read(File.join(dir, "lat.md"))
      assert_includes rendered, "Curated prose that must survive verbatim."
      assert_includes rendered, "## stages (nabu-lects, 2026-08-06)"
      assert_includes rendered, "- arch — Old Latin (700–75 BCE)"
      assert_includes rendered, "- med — Medieval Latin"
      assert_includes rendered, "registers:"
      assert_includes rendered, "- /vul — Vulgar Latin (attested substandard)",
                      "the variety line drops the redundant anchor prefix"
    end
  end

  def test_reconstructed_stages_carry_the_asterisk_convention
    with_shelf do |shelf, dir|
      seed_dossier(dir, "ine", "Indo-European")
      Nabu::LectDossiers.new(lects: lects, shelf: shelf).run!(now: Time.utc(2026, 8, 6))
      assert_includes File.read(File.join(dir, "ine.md")), "- *pro — Proto-Indo-European",
                      "mode: reconstructed renders the etym/define shelves' leading asterisk"
    end
  end

  def test_idempotent_second_run_writes_nothing
    with_shelf do |shelf, dir|
      seed_dossier(dir, "lat", "Latin")
      runner = Nabu::LectDossiers.new(lects: lects, shelf: shelf)
      runner.run!(now: Time.utc(2026, 8, 6))
      before = File.read(File.join(dir, "lat.md"))

      report = runner.run!(now: Time.utc(2026, 8, 7))
      assert_empty report.written, "unchanged registry body must not re-accrete (date must not churn)"
      assert_equal before, File.read(File.join(dir, "lat.md"))
    end
  end

  def test_dry_run_reports_without_writing
    with_shelf do |shelf, dir|
      seed_dossier(dir, "lat", "Latin")
      before = File.read(File.join(dir, "lat.md"))
      report = Nabu::LectDossiers.new(lects: lects, shelf: shelf).run!(dry_run: true)

      assert_equal %w[lat], report.written
      assert_equal before, File.read(File.join(dir, "lat.md")), "dry-run never touches the shelf"
    end
  end

  def test_an_anchor_without_stages_or_varieties_accretes_nothing
    with_shelf do |shelf, dir|
      seed_dossier(dir, "got", "Gothic")
      report = Nabu::LectDossiers.new(lects: lects, shelf: shelf).run!

      refute_includes report.written, "got", "a bare chain anchor has no ladder to accrete"
      refute_includes File.read(File.join(dir, "got.md")), "## stages"
    end
  end
end
