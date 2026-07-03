# frozen_string_literal: true

require "test_helper"

class ShellTest < Minitest::Test
  def test_success_returns_stdout
    assert_equal "hello\n", Nabu::Shell.run("/bin/echo", "hello")
  end

  def test_nonzero_exit_raises_with_status_and_stderr
    error = assert_raises(Nabu::Shell::Error) do
      Nabu::Shell.run("/usr/bin/false")
    end
    refute_equal 0, error.status
    assert_respond_to error, :stderr
  end

  def test_stderr_is_captured_in_error
    # Emit to stderr and exit nonzero via a shell we invoke *as an argv program*,
    # not by letting Shell.run interpret a string.
    error = assert_raises(Nabu::Shell::Error) do
      Nabu::Shell.run("/bin/sh", "-c", "printf 'kaboom' >&2; exit 3")
    end
    assert_equal 3, error.status
    assert_equal "kaboom", error.stderr
  end

  def test_arguments_are_passed_literally_not_shell_expanded
    # A shell would expand $HOME and split on the space; argv semantics must not.
    literal = "a b $HOME"
    assert_equal "#{literal}\n", Nabu::Shell.run("/bin/echo", literal)
  end

  def test_unknown_command_raises_nabu_error
    assert_raises(Nabu::Error) do
      Nabu::Shell.run("/nonexistent/nabu-definitely-not-here")
    end
  end
end
