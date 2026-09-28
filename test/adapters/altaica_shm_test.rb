# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # altaica-shm — Street's Secret History of the Mongols (P107-7, Q99):
  # the romanized Middle Mongol text, one document at Street's own line
  # grain, use granted by the hosting site's maintainer (by email,
  # 2026-09-27; Street's copyright line carried verbatim).
  class AltaicaShmTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("altaica-shm")

    # The RECORDED text layer of the fixture PDF (mutool 1.26 on the
    # cutting box, checked in beside it) — the suite never depends on
    # mutool being installed (the local-library law); the guarded live
    # test below pins agreement when mutool is present.
    RECORDED = ->(_path) { File.read(File.join(FIXTURES, "SH-24UP.textlayer.txt")) }

    def conformance_adapter = Nabu::Adapters::AltaicaShm.new(extract: RECORDED)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "altaica-shm"

    def document
      @document ||= begin
        refs = conformance_adapter.discover(FIXTURES).to_a
        assert_equal 1, refs.size
        conformance_adapter.parse(refs.first)
      end
    end

    def test_one_document_at_street_line_grain
      assert_equal "urn:nabu:altaica-shm:shm", document.urn
      assert_equal "xng", document.language
      assert_operator document.passages.size, :>=, 50
      assert document.passages.first.urn.match?(/:l\d{4}\z/)
    end

    def test_lines_carry_the_text_verbatim_with_street_substitutions
      l1012 = document.passages.find { |p| p.urn.end_with?(":l1012") } || flunk("l1012 missing")
      assert_includes l1012.text, "te6geri", "Street's ASCII substitutions served verbatim (6 = ŋ)"
    end

    def test_section_markers_ride_annotations
      l1011 = document.passages.find { |p| p.urn.end_with?(":l1011") } || flunk("l1011 missing")
      assert_equal "1", l1011.annotations["section"]
      refute_includes l1011.text, "(§", "the marker moves to the annotation"
    end

    def test_glued_footnote_pointers_split_off_the_line_number
      # The unit pin (the fixture pages may not carry a glued case).
      line, fn, text = Nabu::Adapters::AltaicaShm.split_line("10951 göröesün-ü miqan")
      assert_equal %w[1095 1], [line, fn]
      assert_equal "göröesün-ü miqan", text
    end

    def test_copyright_and_grant_ride_the_metadata
      assert_includes document.metadata["copyright"], "Copyright John C. Street"
      assert_includes document.metadata["encoding_note"], "6"
    end

    # -- live mutool (present on the owner's box, absent in CI) ------------

    def test_real_mutool_extraction_agrees_with_the_recorded_layer
      skip "mutool not on PATH — the recorded-extraction tests carry the suite" unless mutool_available?

      live = Nabu::Adapters::AltaicaShm.new
                                       .send(:mutool_text, File.join(FIXTURES, "SH-24UP.pdf"))
      assert_equal RECORDED.call(nil).split("\n").map(&:rstrip),
                   live.split("\n").map(&:rstrip),
                   "the checked-in text layer must stay what mutool extracts (line-grain, " \
                   "trailing whitespace tolerated across mutool versions)"
    end

    private

    def mutool_available?
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, "mutool"))
      end
    end
  end
end
