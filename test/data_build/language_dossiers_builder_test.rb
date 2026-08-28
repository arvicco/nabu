# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/language-dossiers builder (P85-A, №R-47/48): publish the curated
# dossier layer (name/family/context/extras/provenance) as a CLDF ValueTable,
# so a fresh install gets the same human-written context. Section accretions
# (iecor/witness/lect-ladder) are deliberately excluded — each install rebuilds
# them from its own synced sources.
class LanguageDossiersBuilderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("nabu-dossiers")
    @out = Dir.mktmpdir("nabu-dossiers-out")
    seed_dossiers
  end

  def teardown
    FileUtils.remove_entry(@dir)
    FileUtils.remove_entry(@out)
  end

  # A rich dossier (curated lanes + an accretion section that must NOT travel),
  # a Wikipedia-derived one, and a bare stub — the shapes the builder must span.
  def seed_dossiers
    write_dossier(Nabu::LanguageDossier.new(
                    code: "chu", name: "Old Church Slavonic", family: "South Slavic",
                    context: "The oldest attested Slavic literary language.",
                    extras: { "period" => "9th–11th c.", "scripts" => "Cyrs, Glag" },
                    provenance: { "exported" => "2026-07-14", "noted" => "2026-08-02 (curated)" },
                    sections: [Nabu::LanguageDossier::Section.new(
                      kind: "iecor", source: "iecor", date: "2026-07-14", body: "IE-CoR variety: Slavic."
                    )]
                  ))
    write_dossier(Nabu::LanguageDossier.new(
                    code: "aae", name: "Arbëresh Albanian", family: "Albanian (Tosk)",
                    context: "Arbëresh is the Albanian of southern Italy.",
                    provenance: { "noted" => "2026-08-02 (Wikipedia-derived)" }
                  ))
    write_dossier(Nabu::LanguageDossier.new(code: "xyz", name: "Stub Language"))
  end

  def write_dossier(dossier)
    File.write(File.join(@dir, "#{dossier.code}.md"), dossier.render)
  end

  def build
    Nabu::DataBuild::LanguageDossiersBuilder.new(dir: @dir).build(catalog: nil, out_dir: @out)
  end

  def rows
    CSV.read(File.join(@out, "language-dossiers.csv"), headers: true).map(&:to_h)
  end

  def test_columns_are_the_cldf_value_table_shape
    build
    assert_equal %w[ID Language_ID Parameter_ID Value], CSV.read(File.join(@out, "language-dossiers.csv")).first
  end

  def test_curated_lanes_publish_one_row_per_attribute
    build
    chu = rows.select { |r| r["Language_ID"] == "chu" }
    params = chu.to_h { |r| [r["Parameter_ID"], r["Value"]] }
    assert_equal "Old Church Slavonic", params["name"]
    assert_equal "South Slavic", params["family"]
    assert_equal "The oldest attested Slavic literary language.", params["context"]
    assert_equal "9th–11th c.", params["period"]
    assert_equal "Cyrs, Glag", params["scripts"]
    assert_match(/exported: 2026-07-14; noted:/, params["provenance"])
  end

  def test_section_accretions_are_never_published
    build
    refute(rows.any? { |r| r["Parameter_ID"] == "iecor" }, "iecor is a per-install-derivable section")
    refute(rows.any? { |r| r["Value"].include?("IE-CoR variety") }, "no section body may travel")
  end

  def test_ids_are_minted_per_code_and_attribute
    build
    ids = rows.map { |r| r["ID"] }
    assert_includes ids, "chu-name"
    assert_includes ids, "chu-context"
    assert_equal ids.uniq, ids, "IDs are unique"
    ids.each { |id| assert_match(Nabu::DataBuild::CsvWriter::ID_PATTERN, id) }
  end

  def test_a_stub_dossier_publishes_only_what_it_carries
    build
    xyz = rows.select { |r| r["Language_ID"] == "xyz" }
    assert_equal ["name"], xyz.map { |r| r["Parameter_ID"] }, "absent lanes stay absent"
  end

  def test_evaluation_censuses_scan_publish_and_wikipedia_share
    census = build.evaluation
    assert_equal 3, census["dossiers_scanned"]
    assert_equal 3, census["dossiers_published"]
    assert_equal 1, census["wikipedia_derived_dossiers"], "only aae is Wikipedia-derived"
    assert_operator census["rows_by_parameter"]["name"], :==, 3
    assert_equal census["published_rows"], rows.size
  end

  def test_recipe_embeds_a_published_slice_digest_and_is_deterministic
    first = build.recipe
    assert_match(/published-slice sha256=\h{64}/, first)
    FileUtils.remove_entry(@out)
    @out = Dir.mktmpdir("nabu-dossiers-out")
    assert_equal first, build.recipe, "an unchanged dossier corpus is a fingerprint no-op"
  end

  def test_build_result_declares_the_tabular_resource
    resource = build.resources.first
    assert_equal "language-dossiers.csv", resource.path
    assert_equal ["ID"], resource.primary_key
    assert resource.tabular?
  end
end
