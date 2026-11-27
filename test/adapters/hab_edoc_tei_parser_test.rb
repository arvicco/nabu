# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::HabEdocTeiParser — the page-grain TEI family for the
  # HAB's digital editions, against trimmed real transcripts: Hans Sachs
  # (a 1523 print, verse, choice-encoded ſ/u/v and abbreviations, margin
  # notes), Conring (a 1708 print with a prose sourceDesc bibl, facs-only
  # page breaks, printed footnotes), Sibylla Schwarz (a DTA-basisformat
  # print, foliated pb labels) and a Lüne convent letter (msDesc,
  # correspDesc, orig/reg, an editor's note).
  class HabEdocTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("hab-edoc")

    def parse(rel, language: "de")
      Nabu::Adapters::HabEdocTeiParser.new.parse(File.join(FIXTURES, rel), urn: "urn:test:x", language: language)
    end

    def sachs = @sachs ||= parse("ed000238/tei-transcript.xml")
    def conring = @conring ||= parse("ed000226/tei-transcript.xml", language: "lat")
    def schwarz = @schwarz ||= parse("ed000278/texts/tei-transcription.xml")
    def letter = @letter ||= parse("ed000248/texts/Brief001-D_tei-transcript.xml", language: "gml")

    def test_one_passage_per_page_cited_by_the_printed_label
      assert_equal ["urn:test:x:p2r", "urn:test:x:p2v"], sachs.map(&:urn)
      assert_equal({ "page" => "2r", "facs" => "00003" }, sachs.first.annotations.except("notes"))
      assert_equal(%w[pfolair pfolaiir pfolaiiv pfolaiiir pfolaiiiv], schwarz.map { |p| p.urn.split(":").last })
      assert_equal "fol. a i r", schwarz.first.annotations["page"]
    end

    def test_facs_only_page_breaks_cite_the_image_number
      tokens = conring.map { |p| p.urn.split(":").last }
      assert_equal "f00001", tokens.first
      assert_includes tokens, "f00019"
      assert_equal tokens.uniq, tokens
    end

    def test_choice_keeps_the_source_half
      text = sachs.first.text
      assert text.start_with?("Allen liebhabern euangeliſcher warheyt wunſch ich Johannes Sachs ſchuͦmacher"), text
      assert_includes text, "auſerweltẽ", "the abbreviation as printed, not the editors' expansion"
      refute_includes text, "auserwelten"
      assert_includes letter.first.text, "myn I elen vnde wy wilt", "orig kept, reg dropped"
      refute_includes letter.first.text, "unde"
    end

    def test_notes_ride_annotations_never_the_text
      notes = sachs.first.annotations.fetch("notes")
      assert_equal({ "place" => "margin-right", "text" => "Math. xv" }, notes.first)
      refute_includes sachs.first.text, "Math. xv"
      assert_equal [{ "type" => "crit_app", "text" => "Lesart unsicher" }], letter.first.annotations["notes"]
      refute_includes letter.first.text, "Lesart"
      footnoted = conring.find { |p| p.annotations["notes"] }
      assert_match(/\A\(a\)/, footnoted.annotations["notes"].first["text"], "Böhmer's printed footnote marks")
    end

    def test_print_header_mined
      meta = sachs.metadata
      assert_equal "\"Die Wittenbergisch Nachtigall\"", sachs.title
      assert_equal "Hans Sachs", meta["source_author"]
      assert_equal "Nürnberg", meta["pub_place"]
      assert_equal "Georg Erlinger", meta["printer"]
      assert_equal({ "not_before" => 1523, "not_after" => 1523, "raw" => "1523", "basis" => "imprint" },
                   meta["source_date"])
      assert_equal "http://creativecommons.org/licenses/by/4.0/", meta["licence_target"]
    end

    def test_the_dta_basisformat_header_names_the_author_by_parts
      meta = schwarz.metadata
      assert_equal "Schwarz, Sibylla", meta["source_author"]
      assert_equal "Danzig", meta["pub_place"]
      assert_equal "Anna Rhete", meta["printer"]
      assert_equal 1650, meta.dig("source_date", "not_before")
      assert_equal %w[deu lat], meta["lang_usage"]
      assert_equal ["Belletristik"], meta["keywords"]
      assert_equal "http://creativecommons.org/publicdomain/zero/1.0/", meta["licence_target"]
    end

    def test_a_prose_bibl_yields_place_printer_and_year
      meta = conring.metadata
      assert_equal "Helmstedt", meta["pub_place"]
      assert_equal "Georg. Wolfg. Hammius", meta["printer"]
      assert_equal({ "not_before" => 1708, "not_after" => 1708,
                     "raw" => "Helmstedt: Georg. Wolfg. Hammius, 1708.", "basis" => "imprint" },
                   meta["source_date"])
      assert_nil meta["licence_target"], "the header carries only the (c) line"
    end

    def test_the_letter_header_mines_the_manuscript_and_the_correspondents
      meta = letter.metadata
      assert_equal "nds", meta["text_lang"]
      assert_equal "Lüneburg Kloster Lüne Hs. 15, Lage 1, fol. 1r, Brief 1", meta["shelfmark"]
      assert_equal "vermutlich Garnlieferant", meta["sender"]
      assert_equal "vermutlich Weberin", meta["addressee"]
      assert_nil meta["letter_date"], "\"undatiert\" names no year"
    end

    def test_the_header_peek_reads_the_same_header
      path = File.join(FIXTURES, "ed000278/texts/tei-transcription.xml")
      assert_equal schwarz.metadata, Nabu::Adapters::HabEdocTeiParser.new.header(path)
    end

    def test_a_headerless_transcript_parses_with_an_empty_header
      Dir.mktmpdir do |dir|
        path = File.join(dir, "part.xml")
        body = File.read(File.join(FIXTURES, "ed000238/tei-transcript.xml"))
        File.write(path, body.sub(%r{<teiHeader>.*</teiHeader>}m, ""))
        document = Nabu::Adapters::HabEdocTeiParser.new.parse(path, urn: "urn:test:x", language: "de")
        assert_equal sachs.map(&:text), document.map(&:text)
        assert_empty document.metadata
        assert_empty Nabu::Adapters::HabEdocTeiParser.new.header(path)
      end
    end

    def test_output_is_nfc
      [sachs, conring, schwarz, letter].each do |document|
        document.each { |passage| assert passage.text.unicode_normalized?(:nfc), passage.urn }
      end
    end
  end
end
