# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # IEDC — the Invisible East Digital Corpus (P107-2, Q96.1): ONE
  # versioned Zenodo XML → 1,316 documentary items from the medieval
  # Islamicate East (CC BY 4.0). The honest text census drives the
  # design: 481 items carry folio transcriptions (embedded-HTML <ol><li>
  # line lists), 16 more transliteration-only; the rest — including
  # nearly the whole 552-item Khotanese slice — are METADATA-ONLY
  # catalog records (their text lane is the Skjaervø BL set, a separate
  # source), still ingested for their axis metadata: typed dates with
  # parenthesized ISO substrings, toponym lists with lat/long fields,
  # editorial grades, shelfmarks.
  class IedcTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("iedc")

    def conformance_adapter = Nabu::Adapters::Iedc.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "iedc"

    # The Khotanese catalog record legitimately parses to zero passages.
    def conformance_metadata_only?(document)
      document.metadata["text_state"] == "catalog-record"
    end

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(uri) = documents.find { |d| d.urn.end_with?(uri) } || flunk("#{uri} missing")

    def test_discovers_every_item_with_the_corpus_own_ids
      assert_equal %w[urn:nabu:iedc:iedc0002 urn:nabu:iedc:iedc0201
                      urn:nabu:iedc:iedc0382 urn:nabu:iedc:iedc1266],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_primary_language_maps_to_iso_codes
      assert_equal "kho", doc("iedc0382").language
      assert_equal "fa",  doc("iedc0201").language
      assert_equal "xbc", doc("iedc0002").language
      assert_equal "pal", doc("iedc1266").language
    end

    def test_khotanese_catalog_record_is_metadata_only_and_declared
      d = doc("iedc0382")
      assert_equal 0, d.passages.size
      assert_equal "catalog-record", d.metadata["text_state"]
      assert d.metadata["shelfmark"], "the catalog metadata is the point"
    end

    def test_transcription_html_lines_become_passages
      d = doc("iedc0201")
      assert_operator d.passages.size, :>, 3, "the <ol><li> lines split at line grain"
      assert d.passages.first.urn.match?(/:f\d+\.l\d+\z/), "folio.line citation"
      refute(d.passages.any? { |p| p.text.include?("<li") }, "no HTML leaks into text")
      assert_equal "text", d.metadata["text_state"]
    end

    def test_transliteration_is_the_defensive_fallback_layer
      # v1.1 ships no transliteration-only folio (census 2026-09-28:
      # transliteration always accompanies a transcription) — the
      # fallback is defensive against upstream versions, pinned at unit
      # grain; transcription wins when both are present.
      both = doc("iedc1266")
      assert_operator both.passages.size, :>=, 1
      assert_nil both.passages.first.annotations["layer"], "transcription wins"
      layer, body = Nabu::Adapters::Iedc.new.send(:folio_text, fake_folio(translit: "only"))
      assert_equal "transliteration", layer
      assert_equal "only", body
    end

    def fake_folio(translit:)
      Nokogiri::XML("<item><transcription> </transcription>" \
                    "<transliteration>#{translit}</transliteration></item>").root
    end

    def test_typed_date_string_yields_the_iso_substring
      d = doc("iedc0201")
      assert d.metadata["date_text"], "the prose date string rides verbatim"
      assert_match(/\A\d{3,4}(-\d{2})?(-\d{2})?\z/, d.metadata["date_iso"],
                   "the parenthesized ISO substring is extracted for the timeline lane")
    end

    def test_editorial_grade_and_doctype_land_as_facets
      facets = doc("iedc0002").metadata["facets"]
      assert_equal "Gold", facets["grade"]
      assert facets.key?("doctype")
    end

    def test_toponyms_ride_metadata_with_their_coordinate_fields
      topos = documents.flat_map { |d| Array(d.metadata["toponyms"]) }
      assert topos.any?, "at least one fixture item names toponyms"
      assert(topos.all? { |t| t.key?("name") })
    end
  end
end
