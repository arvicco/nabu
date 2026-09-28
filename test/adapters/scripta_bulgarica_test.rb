# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # Scripta Bulgarica (P107-8 — Q100): 125 Old/Middle Bulgarian source
  # texts from the BAS Institute for Literature's portal, mirrored
  # snapshot-first (fragile PHP 5.5 upstream). The Drupal field shape is
  # the parse contract: field-name-body = the FULL source text,
  # field-name-field-manuscript-transcript = the printed-edition
  # citation (the per-text provenance layer), field-author / terms as
  # metadata. CC BY-NC-SA 2.0 verbatim in Bulgarian → class nc.
  class ScriptaBulgaricaTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("scripta-bulgarica")

    def conformance_adapter = Nabu::Adapters::ScriptaBulgarica.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "scripta-bulgarica"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def bitola
      documents.find { |d| d.urn.end_with?("bitolski-nadpis-na-ivan-vladislav") } ||
        flunk("bitola inscription not discovered")
    end

    def test_discovers_the_mirrored_source_pages_only
      urns = conformance_adapter.discover(FIXTURES).map(&:id).sort
      assert_equal ["urn:nabu:scripta-bulgarica:bitolski-nadpis-na-ivan-vladislav",
                    "urn:nabu:scripta-bulgarica:vatopedska-gramota"], urns,
                   "pager index sidecars (manuscript-N.html) are never documents"
    end

    def test_body_field_is_the_source_text
      text = bitola.passages.map(&:text).join(" ")
      assert_includes text, "Їѡаном самодрьжъцемъ блъгарьскомь",
                      "the Old Bulgarian text with its combining titla, verbatim"
      refute_match(/Заимов/, text, "the edition citation is metadata, never a passage")
    end

    def test_edition_citation_is_recorded_as_provenance_metadata
      assert_includes bitola.metadata.fetch("edition"), "Заимов",
                      "the printed-edition layer (the survey's per-text provenance) rides metadata"
      vatoped = documents.find { |d| d.urn.end_with?("vatopedska-gramota") }
      assert_includes vatoped.metadata.fetch("edition"), "Даскалова"
    end

    def test_title_comes_from_the_page_title
      assert_includes bitola.title, "Битолски надпис",
                      "the page title, site-suffix stripped"
      refute_includes bitola.title, "Scripta Bulgarica"
    end

    def test_language_claim_is_the_declared_whole_source_posture
      assert(documents.all? { |d| d.language == "bul" },
             "whole-source bul (Old→Middle Bulgarian span; the chu-recension refinement is a " \
             "recorded future lect look, not silently faked)")
    end
  end
end
