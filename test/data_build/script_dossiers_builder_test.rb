# frozen_string_literal: true

require "test_helper"
require "csv"
require "tmpdir"

# The mul/script-dossiers builder (P86-4c): publishes the config fact file's
# curated per-script layer as a tidy ValueTable — every registry script, one
# row per carried attribute, desk lanes absent-honest, deterministic digest.
class ScriptDossiersBuilderTest < Minitest::Test
  def setup
    @out = Dir.mktmpdir("nabu-script-dossiers")
  end

  def teardown
    FileUtils.remove_entry(@out)
  end

  def build
    Nabu::DataBuild::ScriptDossiersBuilder.new.build(catalog: nil, out_dir: @out)
  end

  def test_publishes_every_registry_script_with_absent_honest_desk_lanes
    result = build
    rows = CSV.read(File.join(@out, "script-dossiers.csv"), headers: true)
    tags = rows.map { |row| row["Script_Tag"] }.uniq.sort
    registry = Nabu::Lects.load(File.expand_path("../fixtures/nabu-lects", __dir__))
    assert_equal registry.script_tags, tags, "every registry script publishes"

    runr = rows.select { |row| row["Script_Tag"] == "runr" }.to_h do |row|
      [row["Parameter_ID"], row["Value"]]
    end
    assert_equal "Runic", runr["name"]
    assert_match(/futhark/i, runr["context"])
    armn = rows.select { |row| row["Script_Tag"] == "armn" }.map { |row| row["Parameter_ID"] }
    refute_includes armn, "desk", "an absent desk lane emits NO row — never a placeholder"

    assert_equal rows.size, result.resources.first.rows
    assert_equal 26, result.evaluation.fetch("scripts")
  end

  def test_recipe_carries_the_published_slice_digest_and_is_deterministic
    first = build
    digest = first.recipe[/sha256=(\h{64})/, 1]
    refute_nil digest, "the recipe embeds the published-slice sha256"
    assert_equal digest, build.recipe[/sha256=(\h{64})/, 1], "an unchanged table is a no-op"
  end
end
