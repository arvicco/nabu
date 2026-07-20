# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# P35-0: the research-axes definitions registry (config/axes.yml) — name,
# persona one-liner, desc, order. Definitions live in their OWN file so
# sources.yml keeps its pure slug => entry contract (no reserved keys);
# membership rides each source row's `axes:` list (SourceRegistryTest).
class AxisRegistryTest < Minitest::Test
  def test_parses_definitions_with_persona_desc_and_positional_order
    registry = load_axes(<<~YAML)
      classical:
        persona: "The Classicist — Greek and Latin letters read whole."
        desc: "The Greco-Roman literary lane."
      epigraphy:
        persona: "The Epigraphist — reads what survives on stone."
        desc: "Documentary corpora at the artifact grain."
    YAML

    assert_equal %w[classical epigraphy], registry.names
    assert_equal 2, registry.size
    refute_predicate registry, :empty?

    classical = registry["classical"]
    assert_equal "classical", classical.name
    assert_equal "The Classicist — Greek and Latin letters read whole.", classical.persona
    assert_equal "The Greco-Roman literary lane.", classical.desc
    assert_equal 0, classical.order
    assert_equal 1, registry["epigraphy"].order, "order is the file's own position — the render order"
    assert_equal %w[classical epigraphy], registry.each_axis.map(&:name)
  end

  def test_missing_file_is_empty_valid_registry
    Dir.mktmpdir do |dir|
      registry = Nabu::AxisRegistry.load(File.join(dir, "does-not-exist.yml"))
      assert_predicate registry, :empty?
      assert_equal 0, registry.size
    end
  end

  def test_top_level_non_mapping_raises
    assert_raises(Nabu::ValidationError) { load_axes("- just\n- a\n- list\n") }
  end

  def test_bad_axis_name_raises_naming_the_axis
    error = assert_raises(Nabu::ValidationError) do
      load_axes(<<~YAML)
        Bad Axis:
          persona: "The Nobody."
          desc: "Nothing."
      YAML
    end
    assert_match(/Bad Axis/, error.message)
    assert_match(/name/, error.message)
  end

  def test_non_mapping_definition_raises_naming_the_axis
    error = assert_raises(Nabu::ValidationError) { load_axes("classical: just-a-string\n") }
    assert_match(/classical/, error.message)
  end

  def test_missing_or_blank_persona_raises_naming_the_axis
    error = assert_raises(Nabu::ValidationError) do
      load_axes(<<~YAML)
        classical:
          desc: "The Greco-Roman literary lane."
      YAML
    end
    assert_match(/classical/, error.message)
    assert_match(/persona/, error.message)

    error = assert_raises(Nabu::ValidationError) do
      load_axes(<<~YAML)
        classical:
          persona: "   "
          desc: "The Greco-Roman literary lane."
      YAML
    end
    assert_match(/persona/, error.message)
  end

  def test_missing_desc_raises_naming_the_axis
    error = assert_raises(Nabu::ValidationError) do
      load_axes(<<~YAML)
        classical:
          persona: "The Classicist."
      YAML
    end
    assert_match(/classical/, error.message)
    assert_match(/desc/, error.message)
  end

  private

  def load_axes(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "axes.yml")
      File.write(path, yaml)
      return Nabu::AxisRegistry.load(path)
    end
  end
end
