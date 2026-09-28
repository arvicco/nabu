# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ATMO — Annotated Turki Manuscripts from the Jarring Collection
  # (P107-4, Q97.1): 18 line-by-line TEI P5 transcripts of 18th–20th c.
  # Eastern Turki manuscripts, CC BY-SA 4.0 verbatim. The Perso-Arabic
  # atmo:lit layer is the served text; atmo:lat transliteration rides
  # annotations; zone provenance (main vs top/endorsement) is per
  # passage. Language chg, the declared honest-coarse Turki posture.
  class AtmoTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("atmo")

    def conformance_adapter = Nabu::Adapters::Atmo.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "atmo"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def prov2 = documents.find { |d| d.urn.end_with?("jarring-prov-2") } || flunk("prov2 missing")

    def test_discovers_transcript_files_never_the_index
      assert_equal %w[urn:nabu:atmo:jarring-prov-2 urn:nabu:atmo:jarring-prov-24],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_lit_layer_is_the_text_lat_rides_annotations
      first_main = prov2.passages.find { |p| p.annotations["zone"].nil? } ||
                   flunk("no main-zone passage")
      assert_includes first_main.text, "رسالۀ", "the Perso-Arabic lit layer verbatim"
      assert_equal "rsalhʾ kasyb", first_main.annotations["translit"]
      assert_equal "chg", first_main.language
    end

    def test_surface_line_citations
      assert prov2.passages.first.urn.match?(/:s[0-9]+[ab]?\.l\d+/),
             "surface (folio side) + line citation"
    end

    def test_non_main_zones_carry_their_zone_annotation
      endorsement = prov2.passages.find { |p| p.annotations["zone"] == "endorsement" }
      refute_nil endorsement, "the top-zone endorsement line is served WITH its provenance"
    end

    def test_title_from_the_tei_header
      assert_includes prov2.title, "Jarring Prov. 2"
    end
  end
end
