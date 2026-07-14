# frozen_string_literal: true

require "test_helper"

# Nabu::LanguageDossier (P19-1): the dossier format — YAML front matter +
# context prose + provenance-headed accretion sections — its derived-record
# flattening, the own-section supersession seam, and the parse/render
# round-trip the sanctioned write paths depend on.
class LanguageDossierTest < Minitest::Test
  FIXTURE = File.read(File.join(Nabu::TestSupport.fixtures("local-language"), "ine-pro.md"))

  def test_parse_reads_front_matter_context_extras_and_sections
    dossier = Nabu::LanguageDossier.parse(FIXTURE, code: "ine-pro")
    assert_equal "ine-pro", dossier.code
    assert_equal "Proto-Indo-European", dossier.name
    assert_equal "Indo-European trunk (reconstructed)", dossier.family
    assert_match(/\A~1\.9k roots/, dossier.context)
    assert_equal({ "period" => "reconstructed, ca. 4500–2500 BCE" }, dossier.extras)
    section = dossier.section("witness:liv")
    assert_equal "liv", section.source
    assert_equal "2026-07-14", section.date
    assert_match(/Lexikon der indogermanischen Verben/, section.body)
  end

  def test_records_flatten_every_lane_with_provenance
    records = Nabu::LanguageDossier.parse(FIXTURE, code: "ine-pro").records
    by_kind = records.to_h { |record| [record.kind, record] }
    assert_equal %w[name family context period witness:liv], records.map(&:kind)
    assert_equal Nabu::LanguageDossier::CURATED_SOURCE, by_kind["context"].source
    assert_equal Nabu::LanguageDossier::CURATED_SOURCE, by_kind["period"].source
    assert_equal "liv", by_kind["witness:liv"].source
  end

  def test_parse_render_round_trips
    dossier = Nabu::LanguageDossier.parse(FIXTURE, code: "ine-pro")
    reparsed = Nabu::LanguageDossier.parse(dossier.render, code: "ine-pro")
    assert_equal dossier.records, reparsed.records
    assert_equal dossier.render, reparsed.render, "render must be a fixed point"
  end

  def test_scripts_list_joins_into_one_extra_lane
    dossier = Nabu::LanguageDossier.parse(
      File.read(File.join(Nabu::TestSupport.fixtures("local-language"), "chu.md")), code: "chu"
    )
    assert_equal "Cyrs, Glag", dossier.extras["scripts"]
  end

  def test_with_section_replaces_only_its_own_kind
    dossier = Nabu::LanguageDossier.parse(FIXTURE, code: "ine-pro")
    revised = dossier.with_section(
      Nabu::LanguageDossier::Section.new(kind: "witness:liv", source: "liv",
                                         date: "2026-08-01", body: "Revised wording.")
    )
    assert_equal "Revised wording.", revised.section("witness:liv").body
    assert_equal dossier.context, revised.context, "curated prose untouched"
    added = revised.with_section(
      Nabu::LanguageDossier::Section.new(kind: "iecor", source: "iecor",
                                         date: "2026-08-01", body: "IE-CoR variety: PIE.")
    )
    assert_equal %w[witness:liv iecor], added.sections.map(&:kind)
  end

  def test_parse_normalizes_to_nfc
    decomposed = "e\u0301tude" # e + combining acute
    text = "---\ncode: fro\nname: #{decomposed}\n---\n#{decomposed} prose\n"
    dossier = Nabu::LanguageDossier.parse(text, code: "fro")
    assert dossier.name.unicode_normalized?(:nfc)
    assert dossier.context.unicode_normalized?(:nfc)
  end

  def test_format_errors_name_the_defect
    error = assert_raises(Nabu::LanguageDossier::FormatError) do
      Nabu::LanguageDossier.parse("no front matter", code: "chu")
    end
    assert_match(/front matter/, error.message)

    error = assert_raises(Nabu::LanguageDossier::FormatError) do
      Nabu::LanguageDossier.parse("---\ncode: chu\n---\n", code: "zle")
    end
    assert_match(/does not match filename/, error.message)

    error = assert_raises(Nabu::LanguageDossier::FormatError) do
      Nabu::LanguageDossier.parse("---\nname: no code\n---\n", code: nil)
    end
    assert_match(/no code/, error.message)

    duplicated = "---\ncode: chu\n---\n## iecor (iecor, 2026-07-14)\n\na\n" \
                 "\n## iecor (iecor, 2026-07-15)\n\nb\n"
    error = assert_raises(Nabu::LanguageDossier::FormatError) do
      Nabu::LanguageDossier.parse(duplicated, code: "chu")
    end
    assert_match(/duplicate section kind/, error.message)

    error = assert_raises(Nabu::LanguageDossier::FormatError) do
      Nabu::LanguageDossier.parse("---\ncode: chu\n---\n## headerless section\n\nbody\n", code: "chu")
    end
    assert_match(/malformed section header/, error.message)
  end
end
