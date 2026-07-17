# frozen_string_literal: true

require "test_helper"

# Nabu::SourceDossier (P24-0): the source-dossier format — YAML front matter
# (slug/description/themes/key_works + scalar extras) + note prose +
# provenance-headed accretion sections — its derived-record flattening, the
# own-section supersession seam, and the parse/render round-trip the
# sanctioned write paths depend on. The language dossier's twin at the
# source grain.
class SourceDossierTest < Minitest::Test
  FIXTURE = File.read(File.join(Nabu::TestSupport.fixtures("local-source"), "edh.md"))

  def test_parse_reads_front_matter_note_extras_and_sections
    dossier = Nabu::SourceDossier.parse(FIXTURE, slug: "edh")
    assert_equal "edh", dossier.slug
    assert_match(/\AThe third documentary genre/, dossier.description)
    assert_equal %w[epigraphy prosopography roman-provinces], dossier.themes
    assert_equal %w[urn:nabu:edh:hd029093], dossier.key_works
    assert_match(/\AFrozen one-shot preservation snapshot/, dossier.note)
    assert_equal({ "period" => "Republic – Late Antiquity" }, dossier.extras)
    section = dossier.section("witness:survey")
    assert_equal "edh-survey", section.provenance
    assert_equal "2026-07-13", section.date
    assert_match(/27-quarantine triage/, section.body)
  end

  def test_records_flatten_every_lane_with_provenance
    records = Nabu::SourceDossier.parse(FIXTURE, slug: "edh").records
    by_kind = records.to_h { |record| [record.kind, record] }
    assert_equal %w[description theme key_work note period witness:survey], records.map(&:kind)
    assert_equal Nabu::SourceDossier::CURATED_PROVENANCE, by_kind["description"].provenance
    assert_equal "epigraphy, prosopography, roman-provinces", by_kind["theme"].body,
                 "list lanes join into one row per kind — the loader's replace key"
    assert_equal "edh-survey", by_kind["witness:survey"].provenance
  end

  def test_parse_render_round_trips
    dossier = Nabu::SourceDossier.parse(FIXTURE, slug: "edh")
    reparsed = Nabu::SourceDossier.parse(dossier.render, slug: "edh")
    assert_equal dossier.records, reparsed.records
    assert_equal dossier.render, reparsed.render, "render must be a fixed point"
  end

  def test_with_section_replaces_only_its_own_kind
    dossier = Nabu::SourceDossier.parse(FIXTURE, slug: "edh")
    revised = dossier.with_section(
      Nabu::SourceDossier::Section.new(kind: "witness:survey", provenance: "edh-survey",
                                       date: "2026-08-01", body: "Revised wording.")
    )
    assert_equal "Revised wording.", revised.section("witness:survey").body
    assert_equal dossier.note, revised.note, "curated prose untouched"
    assert_equal dossier.description, revised.description
    added = revised.with_section(
      Nabu::SourceDossier::Section.new(kind: "witness:gate", provenance: "gate-24",
                                       date: "2026-08-01", body: "Gate note.")
    )
    assert_equal %w[witness:survey witness:gate], added.sections.map(&:kind)
  end

  def test_themes_accept_a_comma_string_and_normalize_to_nfc
    decomposed = "épigraphie" # e + combining acute
    text = "---\nslug: edh\nthemes: #{decomposed}, onomastics\n---\n"
    dossier = Nabu::SourceDossier.parse(text, slug: "edh")
    assert_equal 2, dossier.themes.size
    assert dossier.themes.first.unicode_normalized?(:nfc)
  end

  def test_parse_normalizes_description_and_note_to_nfc
    decomposed = "étude"
    text = "---\nslug: gretil\ndescription: #{decomposed}\n---\n#{decomposed} prose\n"
    dossier = Nabu::SourceDossier.parse(text, slug: "gretil")
    assert dossier.description.unicode_normalized?(:nfc)
    assert dossier.note.unicode_normalized?(:nfc)
  end

  def test_format_errors_name_the_defect
    error = assert_raises(Nabu::SourceDossier::FormatError) do
      Nabu::SourceDossier.parse("no front matter", slug: "edh")
    end
    assert_match(/front matter/, error.message)

    error = assert_raises(Nabu::SourceDossier::FormatError) do
      Nabu::SourceDossier.parse("---\nslug: edh\n---\n", slug: "lexica")
    end
    assert_match(/does not match filename/, error.message)

    error = assert_raises(Nabu::SourceDossier::FormatError) do
      Nabu::SourceDossier.parse("---\ndescription: no slug\n---\n", slug: nil)
    end
    assert_match(/no slug/, error.message)

    duplicated = "---\nslug: edh\n---\n## witness:survey (edh-survey, 2026-07-13)\n\na\n" \
                 "\n## witness:survey (edh-survey, 2026-07-14)\n\nb\n"
    error = assert_raises(Nabu::SourceDossier::FormatError) do
      Nabu::SourceDossier.parse(duplicated, slug: "edh")
    end
    assert_match(/duplicate section kind/, error.message)

    error = assert_raises(Nabu::SourceDossier::FormatError) do
      Nabu::SourceDossier.parse("---\nslug: edh\n---\n## headerless section\n\nbody\n", slug: "edh")
    end
    assert_match(/malformed section header/, error.message)
  end
end
