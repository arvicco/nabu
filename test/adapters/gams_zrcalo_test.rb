# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # gams-zrcalo (Q102, 02-sources row 244): the GAMS digital edition of the
  # 1445 Croatian Glagolitic Zrcalo člověčaskago spasenja (CC BY 4.0 TEI,
  # one datastream). Fixture: the real TEI with its header whole and the
  # body cut to the foreword + chapters 1, 8, 14, 24 and 35 (each removed
  # chapter leaves its last pb/cb in place so the folio state stays true).
  class GamsZrcaloTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("gams-zrcalo")
    URN = "urn:nabu:gams-zrcalo:speculum"

    def conformance_adapter = Nabu::Adapters::GamsZrcalo.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "gams-zrcalo"

    def document
      @document ||= conformance_adapter.parse(conformance_adapter.discover(FIXTURES).first)
    end

    def passage(citation) = document.find { |p| p.urn == "#{URN}:#{citation}" } || flunk("#{citation} missing")

    def test_one_document_cited_by_chapter_and_paragraph
      assert_equal [URN], conformance_adapter.discover(FIXTURES).map(&:id)
      assert_equal "hrv", document.language
      assert_equal "Zrcalo člověčaskago spasenja", document.title
      assert_equal %w[title.head foreword.head foreword.1 1.head 1.1 1.2 1.3 1.4 1.5 8.head 8.1 8.2 8.3
                      14.head 14.1 14.2 14.3 24.head 24.1 35.head 35.1 35.2 35.3 35.4],
                   document.map { |p| p.urn.delete_prefix("#{URN}:") },
                   "\"35.\" keys like \"Chapter 35\" — the integer in div@n"
    end

    def test_line_breaks_join_or_space_per_the_edition
      text = passage("foreword.1").text
      assert text.start_with?("V ime Božje i Děvi Marije. Amen. 1445. měseca maja na 19. dan. Ja žakan Luka " \
                              "počeh pisati sije kńigi popu Grguru va Vrbnici"),
             "lb break=no joins m|aja and Grgu|ru; a plain lb is a space: #{text[0, 140]}"
      assert_equal({ "unit" => "p", "folio" => "1r", "column" => "a" }, passage("foreword.1").annotations)
    end

    def test_choice_keeps_the_witness_and_records_the_correction
      p142 = passage("14.2")
      assert p142.text.start_with?("Kako otac čeladni milostivo prvima sina svojego"), p142.text[0, 60]
      assert_equal [{ "sic" => "Aktoje", "corr" => "Takoje" }], p142.annotations["corrections"]
      assert_includes p142.text, "Aktoje"
      refute_includes p142.text, "Takoje"
    end

    def test_deletions_leave_additions_stay
      p141 = passage("14.1")
      assert_includes p141.text, "A to je pokazalo se na grišnici Mariji Magdalini",
                      "the marginal <add>ka</add> joins its word"
      assert_includes p141.text, "vratil. Manasija Boga razgnival", "the scribe's struck běš|e leaves the reading text"
    end

    def test_folio_state_follows_page_breaks_in_document_order
      assert_equal "26r", passage("14.2").annotations["folio"]
      assert_equal "b", passage("14.2").annotations["column"]
      assert_equal "47v", passage("24.head").annotations["folio"]
      assert_nil passage("title.head").annotations["folio"], "nothing precedes the first pb"
    end

    def test_editorial_notes_ride_annotations_or_the_document
      assert_equal 1, passage("8.head").annotations["notes"].size
      assert_includes passage("8.head").annotations["notes"].first, "The title and the bigger part of the 8th chapter"
      notes = document.metadata["div_notes"]
      assert_equal(["24"], notes.map { |n| n["chapter"] })
      assert_includes notes.first["note"], "ostatak 24. poglavlja, 25., 26."
    end

    def test_header_mines_date_shelfmark_and_declared_script
      meta = document.metadata
      assert_equal({ "not_before" => 1445, "not_after" => 1445, "raw" => "1445" }, meta["date"])
      assert_equal "Borg. L. VII. 9, illirico 9", meta["shelfmark"]
      assert_equal "Biblioteca Apostolica Vaticana", meta["repository"]
      assert_equal "Glagolitic script", meta["script_original"]
      assert_equal %w[hr chu], meta["text_languages"]
      assert_equal "place of origin unknown", meta["orig_place"]
      assert_nil meta["place"], "upstream says unknown — no place is minted"
      assert_equal ["Martina Kramarić", "Gerlinde Schneider"], meta["editors"]
    end

    def test_fetch_is_one_file_fetch_of_the_tei_datastream
      assert_equal "https://gams.uni-graz.at/o:speculum.01/TEI_SOURCE", Nabu::Adapters::GamsZrcalo::TEI_URL
      assert_equal "attribution", Nabu::Adapters::GamsZrcalo.manifest.license_class
    end
  end
end
