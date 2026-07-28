# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::EsukhiaTextParser (P48-1) — the `esukhia-text` family:
  # the Esukhia Derge line format ([page.line] citation brackets, {D<toh>}
  # Tohoku boundaries, (error,correction) / {archaic,modern} pairs, [X]
  # error candidates, # peydurma note anchors). All tests run against the
  # REAL trimmed fixture bytes — no hand-written format samples.
  class EsukhiaTextParserTest < Minitest::Test
    KANGYUR = Nabu::TestSupport.fixtures("derge-kangyur")
    TENGYUR = Nabu::TestSupport.fixtures("derge-tengyur")

    def parser
      Nabu::Adapters::EsukhiaTextParser.new
    end

    def kangyur_paths
      Dir.glob(File.join(KANGYUR, "text", "*.txt"))
    end

    def tengyur_paths
      Dir.glob(File.join(TENGYUR, "text", "*.txt"))
    end

    # -- volume files ---------------------------------------------------------

    def test_volume_number_comes_from_the_filename_prefix
      assert_equal([1, 2, 100], kangyur_paths.map { |p| parser.volume_number(p) })
      assert_equal([1, 212], tengyur_paths.map { |p| parser.volume_number(p) })
    end

    def test_volume_number_is_nil_for_a_non_volume_filename
      assert_nil parser.volume_number("/tmp/README.md")
    end

    # -- scan: the marker index ----------------------------------------------

    def test_scan_finds_every_toh_marker_in_corpus_order
      scan = parser.scan(kangyur_paths)
      assert_equal %w[D1 D1-1 D1-2 D1-6 D846 D846a D847 D848 D852],
                   scan.markers.map(&:marker)
    end

    def test_scan_records_positions_the_d1_pair_sits_on_one_line
      scan = parser.scan(kangyur_paths)
      parent, subtext = scan.markers.first(2)
      assert_equal [0, 3], [parent.file_index, parent.line_index]
      assert_equal [0, 3], [subtext.file_index, subtext.line_index]
      # {D1}{D1-1}: the parent's span ends exactly where the subtext's
      # marker starts — a zero-width (container) span.
      assert_equal parent.char_end, subtext.char_start
    end

    def test_scan_strips_the_tengyur_bom_before_the_first_citation
      scan = parser.scan(tengyur_paths)
      assert_equal %w[D1109 D1110 D1113 D4452 D4453], scan.markers.map(&:marker)
      # The BOM never reaches marker/citation parsing: the first marker sits
      # on line 3 ([1b.1]{D1109}…), char_start right after the citation.
      first = scan.markers.first
      assert_equal 2, first.line_index
      assert_equal "[1b.1]".length, first.char_start
    end

    def test_scan_counts_preamble_text_lines_before_the_first_marker
      # Kangyur volume 001 opens with empty [1a]/[1a.1]/[1b] marker-only
      # lines — nothing textual precedes {D1}.
      assert_equal 0, parser.scan(kangyur_paths).preamble_text_lines
      assert_equal 0, parser.scan(tengyur_paths).preamble_text_lines
    end

    # -- clean: markup extraction over real fixture lines ---------------------

    # The real toh852 opening line carries an in-mantra suggestion pair:
    # …ཨཱརྱ་སཔྟ་(པུ,བུ)དྡྷ་ཀཾ་… — the ORIGINAL reading stays in the text
    # (exact-representation doctrine), the correction rides the apparatus.
    def test_clean_keeps_the_original_reading_of_a_suggestion_pair
      line = fixture_line(KANGYUR, "100", 71)
      cleaned = parser.clean(strip_citation(line))
      refute_includes cleaned.text, "(", "the pair markup must not survive"
      assert_includes cleaned.text, "ཨཱརྱ་སཔྟ་པུདྡྷ་ཀཾ་"
      app = cleaned.apparatus.find { |a| a["kind"] == "suggestion" }
      assert_equal "པུ", app["original"]
      assert_equal "བུ", app["suggested"]
      assert_equal "པུ", cleaned.text[app["offset"], app["original"].length],
                   "the offset must point at the original inside the CLEANED text"
    end

    # The real toh1-1 closing line: …རྫོགས་{སྷོ,སོ}།། །། — an archaic/modern
    # pair; the archaic spelling (what the woodblock carves) stays in text.
    def test_clean_keeps_the_archaic_spelling_of_an_archaic_modern_pair
      line = fixture_line(KANGYUR, "001", 78)
      before_marker = strip_citation(line).split("{D1-2}", 2).first
      cleaned = parser.clean(before_marker)
      assert_includes cleaned.text, "རྫོགས་སྷོ།། །།"
      app = cleaned.apparatus.find { |a| a["kind"] == "archaic" }
      assert_equal "སྷོ", app["original"]
      assert_equal "སོ", app["modern"]
      assert_equal "སྷོ", cleaned.text[app["offset"], app["original"].length]
    end

    # The one real [X] error candidate in the sampled canon (tengyur vol 212
    # line 3803): [པུཥྦཱུ] — the flagged reading stays in the text, brackets
    # extracted to the apparatus.
    def test_clean_extracts_an_error_candidate_and_keeps_its_reading
      line = fixture_line(TENGYUR, "212", 32)
      cleaned = parser.clean(strip_citation(line))
      refute_includes cleaned.text, "["
      assert_includes cleaned.text, "པུཥྦཱུ་རབ་ཏུ་བསྔགས་པ"
      app = cleaned.apparatus.find { |a| a["kind"] == "error_candidate" }
      assert_equal "པུཥྦཱུ", app["reading"]
      assert_equal "པུཥྦཱུ", cleaned.text[app["offset"], app["reading"].length]
    end

    # The real {D1113}#༄༅༅།… line: the peydurma note anchor is removed from
    # the text, its position recorded.
    def test_clean_records_peydurma_note_anchor_offsets
      line = fixture_line(TENGYUR, "001", 85)
      after_marker = strip_citation(line).split("{D1113}", 2).last
      cleaned = parser.clean(after_marker)
      refute_includes cleaned.text, "#"
      assert_equal [0], cleaned.note_marks
      assert cleaned.text.start_with?("༄༅༅།")
    end

    def test_clean_passes_plain_text_through_untouched
      line = fixture_line(KANGYUR, "001", 5)
      raw = strip_citation(line)
      cleaned = parser.clean(raw)
      assert_equal raw, cleaned.text
      assert_empty cleaned.apparatus
      assert_empty cleaned.note_marks
      assert_equal 0, cleaned.unrecognized_curly
    end

    # -- citation brackets ----------------------------------------------------

    def test_citation_parses_page_line_page_only_and_x_pages
      assert_equal %w[1b 1], parser.citation("[1b.1]xyz").first(2)
      assert_equal ["49a", nil], parser.citation("[49a]").first(2)
      assert_equal %w[355xa 2], parser.citation("[355xa.2]…").first(2),
                   "the duplicated-page x convention (README: vol 102 [355xa]) must parse"
    end

    private

    # 1-based +line_no+ of the single fixture volume whose filename starts
    # with +prefix+ — real bytes, BOM stripped like the parser does.
    def fixture_line(root, prefix, line_no)
      path = Dir.glob(File.join(root, "text", "#{prefix}_*.txt")).fetch(0)
      raw = File.read(path, encoding: Encoding::UTF_8).delete_prefix("﻿")
      raw.split("\n").fetch(line_no - 1)
    end

    def strip_citation(line)
      line.sub(/\A\[[0-9]+x?[ab](?:\.[0-9]+)?\]/, "")
    end
  end
end
