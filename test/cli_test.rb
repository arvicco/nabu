# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  # Run the Thor CLI in-process (never shell out to bin/nabu). Returns the
  # captured [stdout, stderr, exit_status]. exit_status is nil when the CLI
  # returned normally without calling exit.
  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end

  def test_version_prints_version_to_stdout
    out, _err, status = run_cli(["version"])
    assert_equal "#{Nabu::VERSION}\n", out
    assert_nil status, "version should not signal failure"
  end

  def test_help_lists_all_commands
    out, _err, _status = run_cli(["help"])
    %w[version sync status rebuild search show].each do |command|
      assert_match(/\b#{command}\b/, out, "help output should list #{command}")
    end
  end

  def test_exit_on_failure_is_enabled
    assert Nabu::CLI.exit_on_failure?
  end

  # Every stub subcommand must announce it is not implemented and fail (exit 1).
  %w[sync rebuild search show].each do |command|
    define_method(:"test_#{command}_stub_is_not_implemented") do
      _out, err, status = run_cli([command])
      assert_equal 1, status, "#{command} should exit with status 1"
      assert_match(/not implemented/i, err, "#{command} should report not implemented on stderr")
    end
  end

  # status is implemented (P1-6). With the shipped comments-only sources.yml
  # the registry is empty and no catalog db exists, so it reports "no sources"
  # and exits cleanly (0).
  def test_status_reports_no_sources_and_succeeds
    out, _err, status = run_cli(["status"])
    assert_nil status, "status should not signal failure with an empty registry"
    assert_match(/no sources registered/i, out)
  end
end
