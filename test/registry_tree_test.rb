# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# The split-registry reader (config/sources/ and config/postures/): one
# file per slug, globbed in sorted slug order, with the guards that
# replace YAML's silent duplicate-key drop.
class RegistryTreeTest < Minitest::Test
  def test_file_mode_reads_a_single_registry_file_verbatim
    with_dir do |dir|
      path = File.join(dir, "sources.yml")
      File.write(path, "b:\n  adapter: B\na:\n  adapter: A\n")
      assert_equal({ "b" => { "adapter" => "B" }, "a" => { "adapter" => "A" } }, Nabu::RegistryTree.load(path))
    end
  end

  def test_missing_path_and_empty_file_are_an_empty_registry
    with_dir do |dir|
      assert_equal({}, Nabu::RegistryTree.load(File.join(dir, "absent.yml")))
      File.write(File.join(dir, "empty.yml"), "# nothing\n")
      assert_equal({}, Nabu::RegistryTree.load(File.join(dir, "empty.yml")))
    end
  end

  def test_directory_mode_unions_per_slug_files_in_sorted_slug_order
    with_tree("zeta" => "zeta:\n  adapter: Z\n", "alpha" => "alpha:\n  adapter: A\n",
              "alpha-b" => "alpha-b:\n  adapter: AB\n") do |dir|
      data = Nabu::RegistryTree.load(dir)
      # slug order, not filename order ("alpha-b.yml" sorts before "alpha.yml")
      assert_equal %w[alpha alpha-b zeta], data.keys
      assert_equal({ "adapter" => "AB" }, data["alpha-b"])
    end
  end

  def test_header_files_are_comment_only_documentation
    with_tree("_header" => "# the shape\n#   <slug>:\n", "acd" => "acd:\n  adapter: A\n") do |dir|
      assert_equal %w[acd], Nabu::RegistryTree.load(dir).keys
    end
  end

  def test_a_header_carrying_data_is_refused
    with_tree("_header" => "stray:\n  adapter: S\n", "acd" => "acd:\n  adapter: A\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir) }
      assert_match(/_header\.yml.*comment-only/, error.message)
    end
  end

  def test_a_slug_key_mismatching_its_filename_is_refused
    with_tree("acd" => "acx:\n  adapter: A\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir) }
      assert_match(/acd\.yml.*"acx".*filename/, error.message)
    end
  end

  def test_a_file_defining_a_second_slug_is_refused
    with_tree("acd" => "acd:\n  adapter: A\naed:\n  adapter: E\n", "aed" => "aed:\n  adapter: E\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir) }
      assert_match(/acd\.yml.*exactly one/, error.message)
    end
  end

  # YAML keeps the LAST of two equal keys without a word — the hazard the
  # split replaces; the guard counts top-level key lines in the text.
  def test_a_duplicated_slug_key_inside_one_file_is_refused
    with_tree("acd" => "acd:\n  adapter: A\nacd:\n  adapter: B\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir) }
      assert_match(/acd\.yml.*defined 2 times/, error.message)
    end
  end

  # Unreachable through one case-sensitive directory (the filename guard
  # pins one slug per file), but a case-insensitive volume or a key that
  # stringifies like another must still never merge silently — the
  # union step itself refuses.
  def test_a_slug_defined_by_two_files_is_refused
    merged = { "acd" => { "adapter" => "A" } }
    owners = { "acd" => "/tree/acd.yml" }
    error = assert_raises(Nabu::ValidationError) do
      Nabu::RegistryTree.send(:merge_slug!, merged, owners, "acd", "/tree/ACD.yml", { "adapter" => "B" })
    end
    assert_match(/"acd" is defined by both acd\.yml and ACD\.yml/, error.message)
    assert_equal({ "adapter" => "A" }, merged["acd"])
  end

  def test_a_yaml_extension_file_is_refused_rather_than_silently_ignored
    with_tree("acd" => "acd:\n  adapter: A\n") do |dir|
      File.write(File.join(dir, "aed.yaml"), "aed:\n  adapter: E\n")
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir) }
      assert_match(/aed\.yaml/, error.message)
    end
  end

  def test_wrapped_trees_carry_the_wrapper_key_per_file
    with_tree("ceipom" => "sources:\n  ceipom:\n    lect: {posture: dates}\n",
              "acd" => "sources:\n  acd:\n    lect: {posture: identity}\n") do |dir|
      data = Nabu::RegistryTree.load(dir, wrapper: "sources")
      assert_equal %w[sources], data.keys
      assert_equal %w[acd ceipom], data["sources"].keys
    end
  end

  def test_wrapped_trees_refuse_files_without_the_wrapper
    with_tree("acd" => "acd:\n  lect: {posture: identity}\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir, wrapper: "sources") }
      assert_match(/acd\.yml.*sources:/, error.message)
    end
  end

  def test_wrapped_trees_refuse_a_duplicated_inner_key
    with_tree("acd" => "sources:\n  acd:\n    lect: {posture: identity}\n  acd:\n    lect: {posture: dates}\n") do |dir|
      error = assert_raises(Nabu::ValidationError) { Nabu::RegistryTree.load(dir, wrapper: "sources") }
      assert_match(/acd\.yml.*defined 2 times/, error.message)
    end
  end

  def test_text_concatenates_headers_then_slug_files
    with_tree("_header" => "# head\n", "b" => "b:\n  x: 1\n", "a" => "a:\n  x: 2\n") do |dir|
      assert_equal "# head\n\na:\n  x: 2\n\nb:\n  x: 1\n", Nabu::RegistryTree.text(dir)
    end
  end

  def test_text_of_a_file_is_its_content
    with_dir do |dir|
      path = File.join(dir, "sources.yml")
      File.write(path, "a:\n  x: 1\n")
      assert_equal "a:\n  x: 1\n", Nabu::RegistryTree.text(path)
      assert_equal "", Nabu::RegistryTree.text(File.join(dir, "absent.yml"))
    end
  end

  def test_exists_covers_both_shapes
    with_tree("a" => "a:\n  x: 1\n") do |dir|
      assert Nabu::RegistryTree.exist?(dir)
      refute Nabu::RegistryTree.exist?(File.join(dir, "nope"))
      assert Nabu::RegistryTree.exist?(File.join(dir, "a.yml"))
    end
  end

  private

  def with_dir(&)
    Dir.mktmpdir("registry-tree", &)
  end

  def with_tree(files)
    with_dir do |root|
      dir = File.join(root, "sources")
      FileUtils.mkdir_p(dir)
      files.each { |name, body| File.write(File.join(dir, "#{name}.yml"), body) }
      yield dir
    end
  end
end
