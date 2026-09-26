# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::FacetMap (P104-1, under №R-70's aggressive-mining policy): the
# metadata-field → facet projection config — per-source declarations of
# which documents.metadata_json fields project into document_facets rows,
# so a source whose axis-shaped fields already ride the catalog gets its
# facets as a pure projection (no canonical re-parse). The kind_map
# discipline: config is the rule surface, validated at load.
class FacetMapTest < Minitest::Test
  def build(doc)
    Nabu::FacetMap.new(doc)
  end

  def test_loads_fields_per_source
    map = build("sources" => { "okhc" => { "fields" => { "corpus" => "collection" } } })
    assert_equal %w[okhc], map.sources
    assert_equal({ "corpus" => "collection" }, map.fields_for("okhc"))
  end

  def test_unruled_source_has_no_fields
    map = build("sources" => {})
    assert_nil map.fields_for("nope")
    assert_empty map.sources
  end

  def test_source_without_fields_is_a_config_error
    error = assert_raises(Nabu::FacetMap::ConfigError) { build("sources" => { "okhc" => {} }) }
    assert_match(/okhc/, error.message)
  end

  def test_blank_facet_name_is_a_config_error
    assert_raises(Nabu::FacetMap::ConfigError) do
      build("sources" => { "okhc" => { "fields" => { "corpus" => "" } } })
    end
  end

  def test_load_default_reads_the_config_file_and_absent_file_is_nil
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, "config")
      FileUtils.mkdir_p(config_dir)
      config = Struct.new(:config_dir).new(config_dir)
      assert_nil Nabu::FacetMap.load_default(config: config)

      File.write(File.join(config_dir, "facet_map.yml"),
                 "sources:\n  seal:\n    fields:\n      genre: genre\n")
      map = Nabu::FacetMap.load_default(config: config)
      assert_equal({ "genre" => "genre" }, map.fields_for("seal"))
    end
  end

  # The shipped config/facet_map.yml must load and target only real
  # sources (the kind_map hygiene stance).
  # P105-5b (Q87): every local-library doc carries a multi-language
  # manifest but only the first code becomes documents.language — the
  # trailing claims (ett under eng facsimiles, xum…) must stay visible
  # through the facet lane.
  def test_shipped_config_projects_library_manifest_languages
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    assert_equal({ "languages" => "language" }, Nabu::FacetMap.load(path).fields_for("local-library"))
  end

  def test_shipped_config_loads
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml")
    map = Nabu::FacetMap.load(path)
    refute_nil map
    slugs = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")).keys
    map.sources.each do |slug|
      assert_includes slugs, slug, "facet_map.yml names #{slug}, which is not a registered source"
    end
  end
end
