# frozen_string_literal: true

require "test_helper"

module Adapters
  # The emmo-tei family over the real, whole EMMO files (test/fixtures/emmo/
  # README.md): the <w>/<c>/<pc> text model, the orig/reg layers, the
  # inline insertions and the out-of-text apparatus.
  class EmmoTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("emmo")

    def parse(name) = Nabu::Adapters::EmmoTeiParser.new.parse(File.join(FIXTURES, name))

    def test_spaces_come_from_c_elements_never_from_layout_whitespace
      first = parse("La13.xml").pages.first.text
      assert first.start_with?("Right worshipfull and my very much respected freind: I haue caused your\n" \
                               "sonne to write out"), "a <pc> sits flush; an <lb/> breaks the line"
      refute_match(/ [:,.]/, first, "no layout space before punctuation")
    end

    def test_the_text_keeps_the_original_spelling_with_expansions_and_reg_rides_beside
      page = parse("La13.xml").pages.first
      assert_includes page.text, "the greater summe", "orig su<abbr>m<ex>m</ex>e</abbr> keeps its expansion"
      assert_includes page.regularized, "the greater sum,"
      assert_includes page.regularized, "Oxford this 27 of March 1620",
                      "an English reg wins over the Latin one (Oxoniensis / Oxford)"
      assert_includes page.text, "Oxoniensis this 27 of March"
    end

    def test_deletions_fw_and_administrative_notes_stay_out_of_the_text
      pages = parse("La13.xml").pages
      assert_equal(["L.a.131"], pages.first.notes.map { |n| n["text"] })
      assert_equal ["187"], pages.first.forme_work
      outer = pages.last
      assert_equal ["Sir Harvye"], outer.deletions
      refute_includes outer.text, "Harvye"
      refute_includes pages.first.text, "L.a.131"
    end

    def test_the_endorsement_is_manuscript_text_and_reads_inline
      outer = parse("La13.xml").pages.last
      assert_includes outer.text, "To Walter Bagot — from"
    end

    def test_a_blank_opening_mints_no_page_and_is_counted
      result = parse("La13.xml")
      assert_equal ["leaf 1 recto", "leaf 2 verso"], result.pages.map(&:n)
      assert_equal 1, result.blank_pages
    end

    def test_an_n_less_pb_after_text_opens_an_unlabelled_page
      result = parse("Xd451-187.xml")
      assert_equal ["leaf 2 verso || leaf 1 recto", nil, "leaf 1 verso || leaf 2 recto"], result.pages.map(&:n)
      assert result.pages[1].text.start_with?("May the 12th 1697\nHonored Sir")
    end

    def test_mentions_ride_in_their_regularized_reading
      result = parse("La13.xml")
      assert_equal ["Oxford"], result.pages.first.places
      assert_equal ["Blithfield"], result.pages.last.places, "Blithfeild regularizes to Blithfield"
      assert_equal ["Yeldard Alvey"], result.pages.first.persons, "the signature's Aluey regularized"
    end

    def test_the_dateline_names_the_writing_place
      assert_equal "Oxford", parse("La13.xml").writing_place
      assert_nil parse("Lb543.xml").writing_place, "a dateline without a placeName names none"
    end

    def test_foreign_spans_carry_their_language
      assert_equal [{ "lang" => "la", "text" => "Oxoniensis" }], parse("La13.xml").pages.first.foreign
    end

    def test_the_header_is_mined
      header = parse("La13.xml").header
      assert_equal "La13", header.idno
      assert_equal "L.a.13", header.shelfmark
      assert_equal "Alvey, Yeldard", header.author
      assert_equal "eng", header.text_lang
      assert_equal "1620-03-27", header.origin_when
      assert_equal "1620 March 27", header.origin_raw
      assert_equal ["Letters"], header.keywords
      assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", header.licence
      assert_equal "https://digitalcollections.folger.edu/img38790", header.surfaces["leaf 1 recto"]
    end

    def test_a_malformed_file_quarantines
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.xml")
        File.write(path, "<TEI><text><body><p>unclosed</body></TEI>")
        assert_raises(Nabu::ParseError) { Nabu::Adapters::EmmoTeiParser.new.parse(path) }
      end
    end
  end
end
