# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "yaml"

# The equivalence oracle for the split registries (P185): the shipped
# config/sources/ and config/postures/ trees are internally consistent
# (one slug per file, spelled as its filename, no slug twice), and the
# RE-CONCATENATED monolith — headers then slug files in load order,
# joined the way the old single file was laid out — parses to exactly
# the per-file union, through the raw reader AND through both consumer
# loaders. At the split itself the trees were byte-cut from the
# monoliths and proven identical to them; this test keeps the property
# that made that proof meaningful (concatenation == union) true for
# every later edit.
class RegistrySplitTest < Minitest::Test
  CONFIG = File.join(Nabu::Config::PROJECT_ROOT, "config")
  SOURCES = File.join(CONFIG, "sources")
  POSTURES = File.join(CONFIG, "postures")

  def test_every_source_file_defines_exactly_its_own_slug
    assert_one_slug_per_file(SOURCES, wrapper: nil)
  end

  def test_every_postures_file_defines_exactly_its_own_slug
    assert_one_slug_per_file(POSTURES, wrapper: "sources")
  end

  def test_the_trees_hold_only_slug_files_and_comment_only_headers
    [SOURCES, POSTURES].each do |dir|
      names = Dir.children(dir).reject { |name| name.start_with?(".") }
      assert names.all? { |name| name.end_with?(".yml") }, "#{dir}: only .yml files"
      headers = Nabu::RegistryTree.header_files(dir)
      assert_equal [File.join(dir, "_header.yml")], headers, "#{dir}: the one schema header"
      assert_nil YAML.safe_load_file(headers.first), "#{dir}/_header.yml must stay comment-only"
    end
  end

  def test_the_reconcatenated_source_registry_parses_to_the_per_file_union
    union = Nabu::RegistryTree.load(SOURCES)
    concatenated = YAML.safe_load(Nabu::RegistryTree.text(SOURCES))
    assert_equal union, concatenated
    assert_equal union.keys, concatenated.keys, "load order IS the concatenation order"
    assert_equal union.keys.sort, union.keys, "the registry reads in sorted slug order"
    assert_equal Nabu::RegistryTree.slug_files(SOURCES).size, union.size,
                 "no slug lost to a duplicate (the YAML silent-drop hazard)"
  end

  def test_the_reconcatenated_postures_record_parses_to_the_per_file_union
    union = Nabu::RegistryTree.load(POSTURES, wrapper: "sources")
    concatenated = YAML.safe_load(postures_monolith_text)
    assert_equal union, concatenated
    assert_equal Nabu::RegistryTree.slug_files(POSTURES).size, union.fetch("sources").size
  end

  def test_both_consumer_loaders_read_the_split_and_the_concatenation_identically
    Dir.mktmpdir do |dir|
      sources_file = File.join(dir, "sources.yml")
      File.write(sources_file, Nabu::RegistryTree.text(SOURCES))
      axes = File.join(CONFIG, "axes.yml")
      split = Nabu::SourceRegistry.load(SOURCES, axes_path: axes, provenance_path: false)
      single = Nabu::SourceRegistry.load(sources_file, axes_path: axes, provenance_path: false)
      assert_equal single.each_source.to_a, split.each_source.to_a

      postures_file = File.join(dir, "postures.yml")
      File.write(postures_file, postures_monolith_text)
      by_key = ->(record) { record.declarations.sort_by { |d| [d.slug, d.layer] } }
      assert_equal by_key.call(Nabu::Postures.load(postures_file)), by_key.call(Nabu::Postures.load(POSTURES))
    end
  end

  private

  def assert_one_slug_per_file(dir, wrapper:)
    Nabu::RegistryTree.slug_files(dir).each do |slug, file|
      data = YAML.safe_load_file(file)
      data = data.fetch(wrapper) if wrapper
      assert_equal [slug], data.keys.map(&:to_s), "#{file} must define exactly #{slug.inspect}"
    end
    Nabu::RegistryTree.load(dir, wrapper: wrapper) # the loader's own guards, end to end
  end

  # Each postures file carries its own `sources:` wrapper line; the
  # monolith carried it once — strip per file, wrap once.
  def postures_monolith_text
    bodies = Nabu::RegistryTree.slug_files(POSTURES).map do |_slug, file|
      File.read(file, encoding: "UTF-8").sub(/\Asources:\n/, "")
    end
    header = Nabu::RegistryTree.header_files(POSTURES).map { |file| File.read(file, encoding: "UTF-8") }
    "#{header.join}sources:\n#{bodies.join("\n")}"
  end
end
