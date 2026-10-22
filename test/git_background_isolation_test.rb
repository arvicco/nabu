# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# test_helper switches git's detached auto-gc / auto-maintenance off for the
# whole suite (a background repack raced local clones and tmpdir cleanup).
class GitBackgroundIsolationTest < Minitest::Test
  def test_every_git_in_the_suite_sees_auto_gc_and_maintenance_off
    Dir.mktmpdir do |dir|
      Nabu::Shell.run("git", "init", "-q", dir)
      assert_equal "0", Nabu::Shell.run("git", "-C", dir, "config", "--get", "gc.auto").strip
      assert_equal "false", Nabu::Shell.run("git", "-C", dir, "config", "--get", "maintenance.auto").strip
    end
  end

  def test_isolation_appends_to_existing_env_config_and_is_idempotent
    env = { "GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "user.name", "GIT_CONFIG_VALUE_0" => "t" }
    Nabu::TestSupport.isolate_git_background_work!(env)
    expected = { "GIT_CONFIG_COUNT" => "3", "GIT_CONFIG_KEY_0" => "user.name", "GIT_CONFIG_VALUE_0" => "t",
                 "GIT_CONFIG_KEY_1" => "gc.auto", "GIT_CONFIG_VALUE_1" => "0",
                 "GIT_CONFIG_KEY_2" => "maintenance.auto", "GIT_CONFIG_VALUE_2" => "false" }
    assert_equal expected, env
    Nabu::TestSupport.isolate_git_background_work!(env)
    assert_equal expected, env, "a child process inheriting the env must not stack duplicates"
  end
end
