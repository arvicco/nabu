# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # Skjaervø's Khotanese BL records (P107-3a, Q96.2): 2,357 TEI.2
  # msDescription records with khot-Latn transliteration LINES — the
  # text lane for the Khotanese documents IEDC catalogs. Upstream's own
  # caveat (DRAFT, unproofed) is declared on every surface.
  class SkjaervoKhotaneseTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("skjaervo-khotanese")

    def conformance_adapter = Nabu::Adapters::SkjaervoKhotanese.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "skjaervo-khotanese"

    # Some records are catalog-only (no <l> lines) — metadata documents.
    def conformance_metadata_only?(document)
      document.passages.empty?
    end

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def test_one_document_per_ms_description_keyed_by_record_number
      assert_equal 4, documents.size, "3 clean records + the genuinely damaged ms1495"
      assert(documents.map(&:urn).all? { |u| u.match?(/\Aurn:nabu:skjaervo-khotanese:ms\d+\z/) })
    end

    # The damage boundary (first-sync finding): the upstream DRAFT has
    # ~100 unclosed tags; record ms1495 is one of the real casualties,
    # included verbatim. Fragment isolation keeps its damage INSIDE the
    # record — the neighbours parse byte-identically clean.
    def test_upstream_damage_stays_inside_its_own_record
      damaged = documents.find { |d| d.urn.end_with?(":ms1495") }
      refute_nil damaged, "the damaged record still yields a document (best-effort recover)"
      ms3 = documents.find { |d| d.urn.end_with?(":ms3") }
      assert_operator ms3.passages.size, :>=, 5, "neighbours keep their full line sets"
    end

    def test_title_is_the_current_shelfmark
      ms3 = documents.find { |d| d.urn.end_with?(":ms3") }
      assert_equal "Or.6393/1", ms3.title
      assert_equal "Hoernle", ms3.metadata["collection"]
    end

    def test_transliteration_lines_become_passages_with_item_line_citations
      ms3 = documents.find { |d| d.urn.end_with?(":ms3") }
      assert_operator ms3.passages.size, :>=, 5
      first = ms3.passages.first
      assert_match(/:i1\.l1\z/, first.urn)
      assert_includes first.text, "vaśäʾrapą̄ñä", "the khot-Latn line verbatim (NFC)"
      assert_equal "kho", first.language
    end

    def test_the_english_note_is_apparatus_metadata_never_a_passage
      ms3 = documents.find { |d| d.urn.end_with?(":ms3") }
      assert_includes ms3.metadata["items"].first["note"], "Report from"
      refute(ms3.passages.any? { |p| p.text.include?("Report from") })
    end

    def test_draft_status_is_declared_on_every_document
      assert(documents.all? { |d| d.metadata["edition_status"] == "draft-unproofed" })
    end
  end
end
