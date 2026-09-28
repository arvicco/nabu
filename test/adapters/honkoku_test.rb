# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # honkoku — みんなで翻刻 crowd transcriptions (P108-5, Q89.1): the
  # v3 tree (project > material > page txts), CC BY-SA 4.0
  # README-verbatim, served HONESTLY as crowd transcription with the
  # platform's aozora-like notation VERBATIM (an upstream-measured
  # ~1.5 errors/100 chars — never "clean editions").
  class HonkokuTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("honkoku")

    def conformance_adapter = Nabu::Adapters::Honkoku.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "honkoku"

    def document
      @document ||= begin
        refs = conformance_adapter.discover(FIXTURES).to_a
        assert_equal 1, refs.size, "only the material WITH a transcription dir discovers"
        conformance_adapter.parse(refs.first)
      end
    end

    def test_document_per_material_titled_from_the_project_index
      assert_equal "urn:nabu:honkoku:21dzk:0A678AA21E602F6A3FFF3329B090920C", document.urn
      assert_equal "目次", document.title
      assert_equal "jpn", document.language
      assert_includes document.metadata["attribution"], "National Diet Library"
      assert_equal "21dzk", document.metadata["project"]
    end

    def test_passage_per_page_with_the_iiif_image
      assert_equal 2, document.passages.size
      first = document.passages.first
      assert first.urn.end_with?(":p1")
      assert_includes first.text, "法華開示抄第二"
      assert_includes first.annotations["image"], "iiif"
    end

    def test_text_is_served_verbatim_including_layout_whitespace
      assert_includes document.passages.first.text, "　　　目次",
                      "the transcription's own full-width layout survives — verbatim means verbatim"
    end

    def test_index_rows_without_a_transcription_dir_skip_counted
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 6, skips.skipped_by_rule,
                   "dir-less index rows AND all-pages-empty materials are censused, never silently dropped"
    end

    # The 2026-09-29 first sync's poison: attribution cells carry raw
    # HTML with bare quote chars (href="…") — a TSV is never quoted
    # CSV, and quote-aware parsing must not choke on it. The real ainu
    # row rides the fixture index verbatim.
    def test_html_attribution_with_bare_quotes_parses
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal 1, refs.size, "the quote-bearing dir-less row and the empty zukan material skip cleanly, no crash"
    end
  end
end
