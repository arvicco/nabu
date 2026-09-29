# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # kouigenji — the 校異源氏物語 TEI (P108-3, Q89.2): Ikeda Kikan's
  # 1942 critical edition of Genji, 54 maki as TEI files, CC BY 4.0.
  # Passage per MANUSCRIPT LINE (`seg`), cited p<page>.l<line> from
  # the seg's own corresp API id; waka ride nested inside their seg
  # and surface as annotations, never re-segmented text.
  class KouigenjiTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("kouigenji")

    def conformance_adapter = Nabu::Adapters::Kouigenji.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "kouigenji"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def kiritsubo
      documents.find { |d| d.urn.end_with?(":01") } || flunk("maki 01 missing")
    end

    def test_one_document_per_maki_titled_from_the_header
      assert_equal %w[urn:nabu:kouigenji:01 urn:nabu:kouigenji:03],
                   documents.map(&:urn).sort
      assert_includes kiritsubo.title, "桐壺"
      assert_equal "jpn", kiritsubo.language
    end

    def test_passages_are_manuscript_lines_cited_page_line
      first = kiritsubo.passages.first
      assert_equal "urn:nabu:kouigenji:01:p5.l1", first.urn
      assert_includes first.text, "いつれの御時にか"
    end

    def test_a_waka_rides_its_seg_as_annotation
      waka_seg = kiritsubo.passages.find { |p| p.annotations["waka"] } ||
                 flunk("no waka-bearing passage in the fixture")
      assert_equal "waka-001", waka_seg.annotations["waka"]
      assert_includes waka_seg.annotations["waka_text"], "かきりとて／わかるゝ道の",
                      "the five l-lines join with ／ in the annotation layer"
      assert_includes waka_seg.text, "かきりとて",
                      "the passage text keeps the manuscript line verbatim, waka inline"
    end

    def test_page_breaks_carry_the_ndl_facsimile
      paged = kiritsubo.passages.find { |p| p.annotations["facs"] }
      refute_nil paged, "the pb facs IIIF URL rides the page's first line"
    end
  end
end
