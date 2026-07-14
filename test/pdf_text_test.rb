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

  def test_a_trailing_newline_after_the_final_form_feed_is_not_a_phantom_page
    # mutool 1.26 (this box) terminates the stream "…\f\n"; older versions
    # end bare "…\f". Neither tail is a page.
    runner = FakeRunner.new(output: "Erste Seite.\n\fZweite Seite.\n\f\n")
    assert_equal ["Erste Seite.\n", "Zweite Seite.\n"], Nabu::PdfText.pages("x.pdf", runner: runner)
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

  # -- .info (P19-5): best-effort ingest metadata candidates -----------------

  INFO_OUTPUT = <<~OUT
    x.pdf:

    PDF-1.7
    Info object (60 0 R):
    <</Author(A. Vaillant)/Title(Manuel du vieux slave \\(2e éd.\\))/CreationDate(D:19500612120000Z)/Producer(x)>>
    Pages: 2
  OUT

  def test_info_reads_title_creator_and_year_from_mutool_info
    runner = FakeRunner.new(output: INFO_OUTPUT)
    info = Nabu::PdfText.info("x.pdf", runner: runner)
    assert_equal ["mutool", "info", "x.pdf"], runner.argv
    assert_equal "Manuel du vieux slave (2e éd.)", info["title"], "PDF literal-string escapes are undone"
    assert_equal "A. Vaillant", info["creator"]
    assert_equal 1950, info["year"]
  end

  def test_info_omits_absent_lanes_and_skips_hex_strings
    output = "Info object (2 0 R):\n<</Title<FEFF04120430>/CreationDate(D:2026)>>\n"
    info = Nabu::PdfText.info("x.pdf", runner: FakeRunner.new(output: output))
    assert_equal({ "year" => 2026 }, info,
                 "hex-encoded strings are honestly skipped, never half-decoded")
  end

  def test_info_degrades_to_empty_on_any_shell_failure
    error = Nabu::Shell::Error.new("command not found: mutool", status: nil, stderr: "")
    assert_empty Nabu::PdfText.info("x.pdf", runner: FakeRunner.new(error: error)),
                 "metadata candidates are a convenience — filename heuristics carry instead"
  end
end
