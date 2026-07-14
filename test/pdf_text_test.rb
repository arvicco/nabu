# frozen_string_literal: true

require "test_helper"

# Nabu::PdfText (P19-4): the mutool text-layer boundary — page splitting on
# mutool's form-feed convention, blank-page alignment, and the failure wrap.
# The command seam is injected (PdfText.pages runner:) so the suite never
# depends on mutool being installed; the recorded shape is mutool draw -F
# text's documented output: each page's text followed by one \f, blank pages
# contributing an empty block so page numbers stay aligned with the physical
# PDF. A guarded live test in LocalLibraryTest exercises real mutool against
# the fixture PDFs when it is on PATH.
class PdfTextTest < Minitest::Test
  # A fake Shell: returns +output+ (or raises +error+) and records argv.
  class FakeRunner
    attr_reader :argv

    def initialize(output: nil, error: nil)
      @output = output
      @error = error
    end

    def run(*argv)
      @argv = argv
      raise @error if @error

      @output
    end
  end

  def test_splits_pages_on_form_feed_and_drops_the_trailing_terminator
    runner = FakeRunner.new(output: "Erste Seite.\n\fZweite Seite.\n\f")
    assert_equal ["Erste Seite.\n", "Zweite Seite.\n"], Nabu::PdfText.pages("x.pdf", runner: runner)
  end

  def test_keeps_blank_pages_so_page_numbers_stay_aligned
    runner = FakeRunner.new(output: "Erste Seite.\n\f\fDritte Seite.\n\f")
    pages = Nabu::PdfText.pages("x.pdf", runner: runner)
    assert_equal 3, pages.size
    assert_equal "", pages[1], "a textless page is an empty block, not a dropped one"
  end

  def test_a_fully_textless_pdf_yields_only_blank_pages_not_an_error
    assert_equal [""], Nabu::PdfText.pages("scan.pdf", runner: FakeRunner.new(output: "\f"))
  end

  def test_runs_mutool_draw_text_to_stdout_via_the_shell_contract
    runner = FakeRunner.new(output: "p1\f")
    Nabu::PdfText.pages("/canonical/local-library/a/b.pdf", runner: runner)
    assert_equal ["mutool", "draw", "-F", "text", "-o", "-", "/canonical/local-library/a/b.pdf"],
                 runner.argv
  end

  def test_wraps_shell_failure_including_missing_mutool_in_pdf_text_error
    error = Nabu::Shell::Error.new("command failed (exit 1): mutool", status: 1, stderr: "bad xref")
    runner = FakeRunner.new(error: error)
    raised = assert_raises(Nabu::PdfText::Error) { Nabu::PdfText.pages("corrupt.pdf", runner: runner) }
    assert_match(/corrupt\.pdf/, raised.message)
    assert_match(/bad xref/, raised.message, "the mutool diagnostic rides along")
  end

  def test_missing_mutool_reads_as_pdf_text_error_with_the_command_name
    error = Nabu::Shell::Error.new("command not found: mutool", status: nil, stderr: "")
    raised = assert_raises(Nabu::PdfText::Error) do
      Nabu::PdfText.pages("x.pdf", runner: FakeRunner.new(error: error))
    end
    assert_match(/command not found: mutool/, raised.message)
  end
end
