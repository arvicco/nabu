# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::LocalMigration (P71-0, the local/ elevation): the one-shot move of
# a pre-P71 box's instance files from config/ to local/config/. Idempotent
# — a second run finds nothing to move; a file already at home is never
# clobbered by a legacy straggler.
class LocalMigrationTest < Minitest::Test
  FILES = %w[grants.yml creep_acceptances.yml link_scopes.yml lect_rulings.yml profile.yml].freeze

  def with_tree
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "config"))
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      yield root, config
    end
  end

  def test_moves_legacy_instance_files_to_local_config
    with_tree do |root, config|
      FILES.each { |name| File.write(File.join(root, "config", name), "#{name}: legacy\n") }
      result = Nabu::LocalMigration.run(config: config)
      assert_equal FILES.sort, result.moved.sort
      FILES.each do |name|
        assert File.exist?(File.join(root, "local", "config", name)), "#{name} moved home"
        refute File.exist?(File.join(root, "config", name)), "#{name} left config/"
      end
      assert_empty Nabu::LocalMigration.run(config: config).moved, "idempotent"
    end
  end

  def test_never_clobbers_a_file_already_at_home
    with_tree do |root, config|
      File.write(File.join(root, "config", "grants.yml"), "legacy\n")
      FileUtils.mkdir_p(File.join(root, "local", "config"))
      File.write(File.join(root, "local", "config", "grants.yml"), "home\n")
      result = Nabu::LocalMigration.run(config: config)
      assert_equal ["grants.yml"], result.conflicts
      assert_equal "home\n", File.read(File.join(root, "local", "config", "grants.yml")),
                   "the home copy is never overwritten"
      assert File.exist?(File.join(root, "config", "grants.yml")),
             "the conflicting legacy copy stays for the owner to reconcile"
    end
  end

  def test_fresh_box_is_a_clean_no_op
    with_tree do |_root, config|
      result = Nabu::LocalMigration.run(config: config)
      assert_empty result.moved
      assert_empty result.conflicts
    end
  end
end
