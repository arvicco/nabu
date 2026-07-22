# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The focus-profile FILE store (config/profile.yml, P40-f). The registry-aware
# behavior (resolution, scoping) lives in FocusTest; this pins the file seam.
class ProfileTest < Minitest::Test
  def test_absent_file_is_the_empty_profile
    Dir.mktmpdir do |dir|
      profile = Nabu::Profile.load(File.join(dir, "profile.yml"))
      assert_predicate profile, :empty?
      assert_empty profile.entries
    end
  end

  def test_entries_are_sorted_deduped_and_stripped
    profile = Nabu::Profile.new(["  slavic ", "germanic", "slavic", "", "rem"])
    assert_equal %w[germanic rem slavic], profile.entries
    refute_predicate profile, :empty?
  end

  def test_round_trip_through_disk
    Dir.mktmpdir do |dir|
      path = File.join(dir, "profile.yml")
      Nabu::Profile.new(%w[germanic rem]).save(path)
      reloaded = Nabu::Profile.load(path)
      assert_equal %w[germanic rem], reloaded.entries
    end
  end

  def test_saved_file_carries_the_commented_header_and_a_block_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "profile.yml")
      Nabu::Profile.new(%w[germanic rem]).save(path)
      text = File.read(path)
      assert_match(/\A# nabu focus profile/, text)
      assert_match(/gitignored/i, text)
      assert_match(/^focus:\n  - germanic\n  - rem\n/, text)
    end
  end

  def test_cleared_profile_writes_an_empty_but_legible_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "profile.yml")
      Nabu::Profile.new([]).save(path)
      assert_match(/^focus: \[\]$/, File.read(path))
      assert_predicate Nabu::Profile.load(path), :empty?
    end
  end

  def test_save_creates_the_parent_directory
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config", "profile.yml")
      Nabu::Profile.new(%w[rem]).save(path)
      assert_path_exists path
    end
  end

  def test_malformed_file_reads_as_empty_never_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "profile.yml")
      File.write(path, "just a scalar, not a mapping\n")
      assert_predicate Nabu::Profile.load(path), :empty?

      File.write(path, "other_key: [a, b]\n")
      assert_predicate Nabu::Profile.load(path), :empty?
    end
  end
end
