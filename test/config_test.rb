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

  def test_sources_path_defaults_under_config
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "config", "sources.yml"), config.sources_path
    end
  end

  def test_sources_path_override_resolves_against_root
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          sources: registry/corpora.yml
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "registry", "corpora.yml"), config.sources_path
    end
  end

  def test_alignments_path_defaults_under_config
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "config", "alignments.yml"), config.alignments_path
    end
  end

  def test_alignments_path_override_resolves_against_root
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          alignments: registry/hub.yml
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "registry", "hub.yml"), config.alignments_path
    end
  end

  def test_display_path_defaults_under_config
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "config", "display.yml"), config.display_path
    end
  end

  def test_display_path_override_resolves_against_root
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        paths:
          display: policies/terminal.yml
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "policies", "terminal.yml"), config.display_path
    end
  end

  def test_catalog_path_is_under_db_dir
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "db", "catalog.sqlite3"), config.catalog_path
    end
  end

  # P7-1: the history ledger rides in the same (config-driven) db dir.
  def test_history_path_is_under_db_dir
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "db", "history.sqlite3"), config.history_path
    end
  end

  # P16-1: the links journal rides in the same (config-driven) db dir.
  def test_links_path_is_under_db_dir
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "db", "links.sqlite3"), config.links_path
    end
  end

  # P7-2: the backup target is optional and has no default (nil until wired).
  def test_backup_target_absent_by_default
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_nil config.backup_target
    end
  end

  def test_backup_target_relative_resolves_against_root
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        backup:
          target: backups/here
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal File.join(root, "backups", "here"), config.backup_target
    end
  end

  def test_backup_target_absolute_used_verbatim
    Dir.mktmpdir do |root|
      path = write_config(root, <<~YAML)
        backup:
          target: /Volumes/NabuBackup/nabu
      YAML
      config = Nabu::Config.load(path: path, root: root)
      assert_equal "/Volumes/NabuBackup/nabu", config.backup_target
    end
  end

  # P7-2: config/ is the backup set's config section; config_dir follows the
  # config file's own location (so a restored/relocated tree is honest).
  def test_config_dir_is_the_config_files_directory
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_equal File.join(root, "config"), config.config_dir
    end
  end

  # P7-2 fresh-machine plumbing: NABU_CONFIG / NABU_ROOT drive the defaults so a
  # restored install needs no code edit. Explicit kwargs still win.
  def test_env_overrides_config_path_and_root
    Dir.mktmpdir do |root|
      path = write_config(root, "paths:\n  canonical: corpus\n")
      with_env("NABU_CONFIG" => path, "NABU_ROOT" => root) do
        config = Nabu::Config.load
        assert_equal path, config.config_path
        assert_equal File.join(root, "corpus"), config.canonical_dir
      end
    end
  end

  def test_explicit_args_win_over_env
    Dir.mktmpdir do |root|
      other = File.join(root, "elsewhere", "nabu.yml")
      with_env("NABU_CONFIG" => "/nope/nabu.yml", "NABU_ROOT" => "/nope") do
        config = Nabu::Config.load(path: other, root: root)
        assert_equal other, config.config_path
        assert_equal File.join(root, "canonical"), config.canonical_dir
      end
    end
  end

  private

  def with_env(vars)
    saved = vars.transform_values { |_| :__unset__ }
    vars.each_key { |key| saved[key] = ENV.key?(key) ? ENV[key] : :__unset__ }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value == :__unset__ ? ENV.delete(key) : ENV[key] = value }
  end

  def write_config(root, contents)
    dir = File.join(root, "config")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "nabu.yml")
    File.write(path, contents)
    path
  end
end
