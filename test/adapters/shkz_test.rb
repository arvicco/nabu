# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ŠKZ — the trilingual Kaʿba-ye Zartošt inscription (P107-3b, Q96.3):
  # three version documents (grc / xpr / pal) over 50 SHARED line
  # citations — the shared :l<n> citation IS the alignment; the word-
  # pair layer stays a declared residue in canonical.
  class ShkzTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("shkz")

    def conformance_adapter = Nabu::Adapters::Shkz.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "shkz"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(code) = documents.find { |d| d.language == code } || flunk("#{code} missing")

    def test_three_version_documents
      assert_equal %w[grc pal xpr], documents.map(&:language).sort
      assert_equal %w[urn:nabu:shkz:grc urn:nabu:shkz:pal urn:nabu:shkz:xpr],
                   documents.map(&:urn).sort
    end

    def test_lines_share_citations_across_versions
      assert_equal doc("grc").passages.map { |p| p.urn.split(":").last },
                   doc("xpr").passages.map { |p| p.urn.split(":").last },
                   "the shared :l<n> citation is the alignment"
      assert_equal 3, doc("grc").passages.size, "fixture rows"
    end

    def test_parthian_serves_the_transcription_with_transliteration_as_annotation
      first = doc("xpr").passages.first
      assert_includes first.text, "Šābuhr", "the transcription is the text"
      assert_includes first.annotations["transliteration"], "MLKYN MLKA"
    end

    def test_greek_and_middle_persian_texts_verbatim
      assert_includes doc("grc").passages.first.text, "Σαπώρης"
      assert_includes doc("pal").passages.first.text, "šāhān šāh"
    end
  end
end
