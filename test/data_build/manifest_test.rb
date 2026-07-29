# frozen_string_literal: true

require "test_helper"
require "json"

# datapackage.json (P50-W1): Frictionless Data Package v2 shape + the
# namespaced nabu block, byte-stable for diffability (golden file), with a
# derivation fingerprint that changes iff inputs or recipe change.
#
# The fixture is a GOLDEN OUTPUT, not an upstream sample (hence no fixture
# README.md/manifest.yml — that convention marks real-source dirs). Its
# inputs live in ONE place, DataBuildFake.golden_manifest_args, so test and
# fixture cannot drift. Regenerate after an INTENDED shape change (and say
# why in the commit):
#
#   bundle exec ruby -Itest -Ilib -e 'require "test_helper";
#     File.write("test/fixtures/data_build/datapackage.json",
#                Nabu::DataBuild::Manifest.generate(**DataBuildFake.golden_manifest_args))'
class DataBuildManifestTest < Minitest::Test
  MANIFEST = Nabu::DataBuild::Manifest
  FIXTURE = File.join(Nabu::TestSupport::FIXTURES_ROOT, "data_build", "datapackage.json")

  def golden_json
    MANIFEST.generate(**DataBuildFake.golden_manifest_args)
  end

  def test_golden_manifest_matches_the_fixture_byte_for_byte
    assert_equal File.read(FIXTURE, encoding: Encoding::UTF_8), golden_json
  end

  def test_generation_is_byte_stable
    assert_equal golden_json, MANIFEST.generate(**DataBuildFake.golden_manifest_args)
  end

  def test_top_level_key_order_is_the_committed_template_order
    assert_equal ["$schema", "name", "title", "version", "licenses", "contributors",
                  "sources", "resources", "nabu"],
                 JSON.parse(golden_json).keys
  end

  def test_the_nabu_block_carries_derivation_anchoring_tier_and_counts
    nabu = JSON.parse(golden_json).fetch("nabu")
    args = DataBuildFake.golden_manifest_args
    assert_equal "nabu data build #{args[:feature].slug}", nabu["producer"]
    assert_equal "0.0.0-golden", nabu["nabu_version"]
    assert_equal({ "canonical_sha" => args[:input_shas].fetch("dcs"), "cone" => "dcs" },
                 nabu.dig("derivation", "inputs", "dcs"))
    assert_equal args[:recipe], nabu.dig("derivation", "recipe")
    assert_equal MANIFEST.fingerprint(input_shas: args[:input_shas], recipe: args[:recipe]),
                 nabu.dig("derivation", "fingerprint")
    assert_equal({ "kind" => "none" }, nabu["anchoring"])
    assert_equal "gold-derived", nabu["tier"]
    assert_equal({ "rows" => 3 }, nabu["counts"], "2 forms rows + 1 languages row; the bib counts 0")
  end

  def test_an_evaluation_rides_the_nabu_block_as_eval_and_is_absent_when_nil
    evaluation = { "boundary_f1" => 0.9622, "against" => "soas-tibetan gold",
                   "contamination" => "clean" }
    with_eval = MANIFEST.generate(**DataBuildFake.golden_manifest_args, evaluation: evaluation)
    assert_equal evaluation, JSON.parse(with_eval).dig("nabu", "eval")

    refute JSON.parse(golden_json).fetch("nabu").key?("eval"),
           "no evaluation → no eval key (the golden fixture stays eval-free)"
  end

  def test_non_tabular_resources_are_legal_and_tabular_ones_carry_schema
    resources = JSON.parse(golden_json).fetch("resources")

    bib = resources.find { |resource| resource["name"] == "sources" }
    refute_nil bib
    refute bib.key?("schema"), "a non-tabular resource carries no schema"
    assert_equal "bibtex", bib["format"]
    assert_equal "text/x-bibtex", bib["mediatype"]

    forms = resources.find { |resource| resource["name"] == "forms" }
    assert_equal ["ID"], forms.dig("schema", "primaryKey")
    assert_equal "ID", forms.dig("schema", "fields", 0, "name")
    refute forms.key?("format")
  end

  def test_sources_carry_title_path_version_and_licenses
    source = JSON.parse(golden_json).fetch("sources").first
    assert_equal %w[title path version licenses], source.keys
    assert_equal "1111222233334444555566667777888899990000", source["version"]
  end

  def test_fingerprint_changes_iff_inputs_or_recipe_change
    base = MANIFEST.fingerprint(input_shas: { "dcs" => "aaa" }, recipe: "r1")
    assert_equal base, MANIFEST.fingerprint(input_shas: { "dcs" => "aaa" }, recipe: "r1")
    refute_equal base, MANIFEST.fingerprint(input_shas: { "dcs" => "bbb" }, recipe: "r1")
    refute_equal base, MANIFEST.fingerprint(input_shas: { "dcs" => "aaa" }, recipe: "r2")
    refute_equal base, MANIFEST.fingerprint(input_shas: { "dcs" => "aaa", "extra" => "c" }, recipe: "r1")
    assert_equal MANIFEST.fingerprint(input_shas: { "a" => "1", "b" => "2" }, recipe: "r"),
                 MANIFEST.fingerprint(input_shas: { "b" => "2", "a" => "1" }, recipe: "r"),
                 "input order must not matter — only content"
  end
end
