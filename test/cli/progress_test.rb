# frozen_string_literal: true

require "test_helper"
require "stringio"

# The one-physical-line contract for \r-rendered progress lines
# (Nabu::CLI::ProgressLine): a line wider than the terminal soft-wraps, and
# "\r\e[K" then rewrites only the LAST wrapped row — every tick scrolls a
# permanent line. Every \r line is therefore clamped to width-1 cells, the
# LABEL ellipsis-truncated and the moving count kept whole.
class ProgressLineTest < Minitest::Test
  LABEL = "sign coverage (cdli + oracc + etcsl + ebl sign readings across every cuneiform witness held)…"

  # A tty-claiming StringIO: the progress lambdas branch on $stderr.tty?.
  class FakeTty < StringIO
    def tty? = true
  end

  # A console double answering winsize like IO.console does.
  FakeConsole = Struct.new(:rows, :cols) do
    def winsize = [rows, cols]
  end

  def visible(line)
    line.delete_prefix("\r").delete_prefix("\e[K")
  end

  def test_fixture_label_is_long_enough_to_wrap
    assert_operator LABEL.length, :>=, 90
  end

  def test_long_label_and_large_count_fit_80_columns_and_keep_the_count
    line = Nabu::CLI::ProgressLine.fit(lead: "  ", label: LABEL, tail: " 1234567 docs  ", width: 80)

    assert_operator line.length, :<=, 79
    assert line.end_with?(" 1234567 docs  "), "the moving count survives whole: #{line.inspect}"
  end

  def test_the_label_is_ellipsis_truncated_not_the_count
    line = Nabu::CLI::ProgressLine.fit(lead: "  ", label: LABEL, tail: " 82000 docs", width: 80)

    assert_equal 79, line.length
    label_part = line.delete_prefix("  ").delete_suffix(" 82000 docs")
    assert label_part.end_with?("…")
    assert LABEL.start_with?(label_part.delete_suffix("…")), "label truncated from the right only"
    assert_operator label_part.length, :<, LABEL.length
  end

  def test_wide_terminal_leaves_the_line_untouched
    line = Nabu::CLI::ProgressLine.fit(lead: "  ", label: LABEL, tail: " 82000 docs  ", width: 200)

    assert_equal "  #{LABEL} 82000 docs  ", line
  end

  def test_label_keeps_a_minimum_and_the_line_still_fits
    tail = " 82000 docs (12 quarantined) ~3h 20m left  #{'x' * 30}"
    line = Nabu::CLI::ProgressLine.fit(lead: "  ", label: LABEL, tail: tail, width: 60)

    assert_operator line.length, :<=, 59, "one physical line wins over everything"
    assert line.start_with?("  #{LABEL[0, 10]}"), "the label keeps its minimum: #{line.inspect}"
  end

  def test_pathologically_narrow_width_hard_truncates
    line = Nabu::CLI::ProgressLine.fit(lead: "  ", label: LABEL, tail: " 82000 docs", width: 12)

    assert_equal 11, line.length
    assert_equal "  #{LABEL}"[0, 11], line
  end

  def test_width_reads_the_console_first
    assert_equal 132, Nabu::CLI::ProgressLine.width(console: FakeConsole.new(40, 132), env: { "COLUMNS" => "90" })
  end

  def test_width_falls_back_to_columns
    assert_equal 90, Nabu::CLI::ProgressLine.width(console: nil, env: { "COLUMNS" => "90" })
    assert_equal 90, Nabu::CLI::ProgressLine.width(console: FakeConsole.new(0, 0), env: { "COLUMNS" => "90" })
  end

  def test_width_defaults_to_eighty_columns
    assert_equal 80, Nabu::CLI::ProgressLine.width(console: nil, env: {})
    assert_equal 80, Nabu::CLI::ProgressLine.width(console: nil, env: { "COLUMNS" => "junk" })
  end

  def test_render_prefixes_the_carriage_return_and_clear
    rendered = Nabu::CLI::ProgressLine.render(lead: "  ", label: "a…", tail: " 5 docs", width: 80)
    assert_equal "\r\e[K  a… 5 docs", rendered
  end

  # -- the live call sites route through the clamp ------------------------------

  def with_width(cols)
    line = Nabu::CLI::ProgressLine
    original = line.method(:width)
    line.define_singleton_method(:width) { |**| cols }
    yield
  ensure
    line.singleton_class.send(:remove_method, :width)
    line.define_singleton_method(:width, original)
  end

  def capture_tty
    original = $stderr
    $stderr = FakeTty.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  def test_load_tick_renders_one_clamped_line_at_80_columns
    cli = Nabu::CLI.new
    state = { stage: LABEL.delete_suffix("…"), started: Process.clock_gettime(Process::CLOCK_MONOTONIC),
              processed: 0, errored: 0, last: 0 }
    out = with_width(80) { capture_tty { cli.send(:load_tick, true, state).call(1_234_567, 0) } }

    assert out.start_with?("\r\e[K")
    refute_includes out, "\n"
    assert_operator visible(out).length, :<=, 79
    assert_includes out, " 1234567 docs"
  end

  def test_stage_open_and_close_lines_are_clamped
    cli = Nabu::CLI.new
    state = { stage: nil }
    out = with_width(80) do
      capture_tty do
        tick = cli.send(:stage_tick, true, state)
        tick.call(LABEL.delete_suffix("…"))
        state[:processed] = 82_000
        cli.send(:close_stage, state)
      end
    end

    out.split(/[\r\n]/).reject(&:empty?).each do |row|
      assert_operator visible(row).length, :<=, 79, row.inspect
    end
    assert_includes out, " 82000 docs "
  end

  def test_remote_health_ticker_is_clamped
    cli = Nabu::CLI.new
    out = with_width(40) do
      capture_tty { cli.send(:remote_health_ticker).call("a-very-long-source-slug-that-overflows", 117, 254) }
    end

    assert_operator visible(out).length, :<=, 39
    assert_includes out, "117/254"
  end

  def test_lect_facet_ticker_routes_through_the_clamp
    out = with_width(80) do
      capture_tty { Nabu::LectCLI.new.send(:facet_progress).load_tick(4_200_000, 0) }
    end

    assert_equal "\r\e[K  4200000 rows…", out
  end
end
