# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class ConfigTest < Minitest::Test
  def test_defaults_when_file_absent
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "canonical"), config.canonical_dir
      assert_equal File.join(root, "db"), config.db_dir
    end
  end

  def test_relative_paths_from_file_resolve_against_root
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          canonical: corpus
          db: derived
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "corpus"), config.canonical_dir
      assert_equal File.join(root, "derived"), config.db_dir
    end
  end

  def test_absolute_paths_from_file_are_used_verbatim
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          canonical: /srv/nabu/canonical
          db: /srv/nabu/db
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal "/srv/nabu/canonical", config.canonical_dir
      assert_equal "/srv/nabu/db", config.db_dir
    end
  end

  def test_missing_key_falls_back_to_default
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          canonical: corpus
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "corpus"), config.canonical_dir
      assert_equal File.join(root, "db"), config.db_dir
    end
  end

  def test_empty_file_falls_back_to_defaults
    Dir.mktmpdir do |root|
      path = write_config(root, "")
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "canonical"), config.canonical_dir
      assert_equal File.join(root, "db"), config.db_dir
    end
  end

  def test_shipped_example_config_loads
    config = Nabu::Config.load
    assert_equal File.join(Nabu::Config::PROJECT_ROOT, "canonical"), config.canonical_dir
    assert_equal File.join(Nabu::Config::PROJECT_ROOT, "db"), config.db_dir
  end

  private

  def write_config(root, contents)
    dir = File.join(root, "config")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "nabu.yml")
    File.write(path, contents)
    path
  end
end
