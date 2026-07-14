# frozen_string_literal: true

require_relative "shell"

module Nabu
  # PDF text-layer extraction for the local-library shelf (P19-4,
  # architecture §16) — mutool through Nabu::Shell, the already-sanctioned
  # shell dependency (CLAUDE.md; the ad-hoc pipeline design named it first).
  #
  # == Page grain, argued
  #
  # `mutool draw -F text` emits one form-feed-terminated block per page —
  # the page is the ONLY stable citation unit a PDF natively carries.
  # Paragraph re-segmentation of extracted text is an extraction artifact
  # (column order, hyphenation and line joining shift between mutool
  # versions), while the page number survives every re-extraction AND is how
  # scholarship cites these documents ("Leskien 1871, p. 12"). So the shelf
  # mints page-grain passages (`…:p12`) and never pretends to a finer grain
  # it could not keep stable (frozen-URN discipline).
  #
  # == Failure semantics
  #
  # mutool exiting nonzero (or absent) raises PdfText::Error — the adapter
  # maps that to ParseError/quarantine: a file that cannot be READ is
  # genuinely damaged. A scan that reads fine but carries no text layer is
  # NOT an error: extraction succeeds with blank pages, and the adapter
  # catalogues the document metadata-only (`text_layer: none`).
  module PdfText
    # Extraction failure (mutool missing, nonzero exit). Carries the Shell
    # diagnostics in the message.
    class Error < Nabu::Error; end

    module_function

    # The per-page text of the PDF at +path+, in page order: an Array with
    # one String per page ("" for a page with no text layer). mutool prints
    # each page followed by \f, so the trailing split fragment after the
    # LAST \f is not a page and is dropped when blank — some mutool
    # versions terminate the stream bare, others append a final newline
    # (measured: 1.26 emits "…\f\n"), and either way a whitespace-only
    # tail is stream decoration, never a page. Every OTHER fragment is one,
    # blank or not (page numbers must stay aligned with the physical PDF).
    #
    # +runner+ is the command seam (anything with Shell's .run contract);
    # tests inject a fake so the suite never depends on mutool being
    # installed (minitest 6 ships no stubbing, and the dependency budget
    # stands).
    def pages(path, runner: Shell)
      output = runner.run("mutool", "draw", "-F", "text", "-o", "-", path)
      pages = output.split("\f", -1)
      pages.pop if pages.last&.strip&.empty?
      pages
    rescue Shell::Error => e
      detail = e.stderr.to_s.strip.empty? ? e.message : "#{e.message}: #{e.stderr.strip.lines.first&.strip}"
      raise Error, "mutool text extraction failed for #{path} (#{detail})"
    end

    # Best-effort document metadata for `nabu ingest` (P19-5): the PDF Info
    # dictionary via `mutool info`, reduced to the candidate lanes ingest can
    # prefill — {"title", "creator", "year"} (year from /CreationDate's
    # D:YYYY… prefix), empty lanes omitted. DEGRADES to {} on any failure
    # (mutool absent, unreadable file, no Info dict): metadata candidates
    # are a convenience, never a gate — filename heuristics carry instead.
    # Only literal-string values are read; hex-encoded (UTF-16) strings are
    # honestly skipped rather than half-decoded.
    def info(path, runner: Shell)
      output = runner.run("mutool", "info", path)
      candidates = {
        "title" => info_string(output, "Title"),
        "creator" => info_string(output, "Author"),
        "year" => info_year(output)
      }
      candidates.compact.reject { |_k, v| v == "" }
    rescue Shell::Error
      {}
    end

    # /Key (value) with the PDF literal-string escapes \( \) \\ undone.
    def info_string(output, key)
      match = output[%r{/#{key}\s*\(((?:\\.|[^()\\])*)\)}, 1]
      match&.gsub(/\\([()\\])/, '\1')&.strip
    end

    def info_year(output)
      year = output[%r{/CreationDate\s*\(D:(\d{4})}, 1]
      year&.to_i
    end
  end
end
