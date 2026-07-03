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

  # --- stream -------------------------------------------------------------

  def test_stream_forwards_each_line_as_it_arrives
    lines = []
    result = Nabu::Shell.stream("/bin/sh", "-c", "printf 'one\\ntwo\\nthree\\n'") { |line| lines << line }
    assert_nil result, "stream returns nil on success"
    assert_equal "one\ntwo\nthree\n".lines, lines
  end

  def test_stream_merges_stderr_into_the_forwarded_stream
    # git writes progress to stderr; popen2e must merge it into the block.
    lines = []
    Nabu::Shell.stream("/bin/sh", "-c", "printf 'out\\n'; printf 'err\\n' >&2") { |line| lines << line }
    assert_includes lines, "out\n"
    assert_includes lines, "err\n"
  end

  def test_stream_splits_on_carriage_return_so_progress_forwards_live
    # git --progress overwrites with \r and no trailing newline until the end.
    lines = []
    Nabu::Shell.stream("/bin/sh", "-c", "printf '10%%\\r50%%\\r100%%\\n'") { |line| lines << line }
    assert_equal ["10%\r", "50%\r", "100%\n"], lines
  end

  def test_stream_yields_unterminated_trailing_fragment
    lines = []
    Nabu::Shell.stream("/bin/sh", "-c", "printf 'no-newline'") { |line| lines << line }
    assert_equal ["no-newline"], lines
  end

  def test_stream_raises_shell_error_with_captured_output_on_failure
    lines = []
    error = assert_raises(Nabu::Shell::Error) do
      Nabu::Shell.stream("/bin/sh", "-c", "printf 'partial\\nkaboom\\n'; exit 4") { |line| lines << line }
    end
    assert_equal 4, error.status
    # Everything forwarded is also captured for the error diagnostic.
    assert_equal "partial\nkaboom\n", error.stderr
    assert_equal "partial\nkaboom\n".lines, lines
  end

  def test_stream_without_a_block_still_runs_and_checks_exit_status
    assert_nil Nabu::Shell.stream("/bin/sh", "-c", "printf 'ignored\\n'")
    assert_raises(Nabu::Shell::Error) { Nabu::Shell.stream("/usr/bin/false") }
  end

  def test_stream_unknown_command_raises_nabu_error
    assert_raises(Nabu::Error) do
      Nabu::Shell.stream("/nonexistent/nabu-definitely-not-here") { |line| line }
    end
  end
end
