# frozen_string_literal: true

require "test_helper"

module Adapters
  # The SOL entry page parser: one saved search-CGI answer → one entry
  # (fixture README: test/fixtures/suda-translations/).
  class SolEntryParserTest < Minitest::Test
    ZIP = File.expand_path("../fixtures/suda-translations/solEntries.zip", __dir__)

    def member(name)
      reader = Nabu::ZipReader.new(File.binread(ZIP))
      entry = reader.entries.find { |e| e.name.b == "sol-entries/#{name}".b } || flunk("#{name} missing")
      reader.extract(entry).force_encoding(Encoding::UTF_8)
    end

    def parse(name) = Nabu::Adapters::SolEntryParser.parse(member(name))

    def test_naxos_core_fields
      e = parse("nu/27")
      assert_equal "nu", e.letter
      assert_equal 27, e.number
      assert_equal ["*naci/a"], e.headwords_betacode
      assert_equal "Ναξία", e.headword
      assert_equal "Naxia; Naxos, Naxus", e.translated_headword
      assert_equal "high", e.vetting_status
    end

    def test_translation_keeps_line_breaks_and_decodes_inline_greek
      text = parse("nu/27").translation
      assert text.start_with?("A city.[1]\nAlso [sc. attested is] 'Naxian stone'"), text[0, 80]
      assert_includes text, "from the [verb] νάξαι [\"to squeeze\"]",
                      "<g> betacode inside the translation decodes to Unicode Greek"
      assert_includes text, "very sweet wine flows.[5]"
      refute_includes text, "<"
    end

    def test_greek_original_decodes_and_placeholder_is_nil
      greek = parse("nu/27").greek_original
      assert greek.start_with?("Ναξία: πόλις. καὶ Ναξία λίθος, ἡ Κρητικὴ ἀκόνη:"), greek[0, 60]
      assert greek.end_with?("ἐξ ἧς οἶνος ῥεῖ μάλα ἡδύς."), greek[-40..]
      assert_nil parse("alpha/1").greek_original, "the export's '#' placeholder is no Greek"
    end

    def test_notes_references_and_keywords
      e = parse("nu/27")
      assert e.notes.start_with?("[1] In Karia (see below)"), e.notes[0, 40]
      assert_includes e.notes, "the phrase Ναξίαν ... ἀκόναν occurs"
      assert_equal 5, e.notes.lines.size
      assert_equal "E. Schütrumpf, Heracleides of Pontus. Texts and Translation. New Brunswick, NJ, 2008",
                   e.references
      assert_equal ["aetiology", "definition", "dialects, grammar, and etymology", "food",
                    "gender and sexuality", "geography", "medicine", "mythology", "religion", "women"],
                   e.keywords
    end

    def test_translator_and_vetting_history
      e = parse("nu/27")
      assert_equal "David Mirhady", e.translator
      assert_equal "2009-07-10T17:32:56", e.translated_at
      assert_equal 6, e.vetters.size
      assert_equal({ "name" => "Catharine Roth", "note" => "added betacode and keywords",
                     "at" => "2009-07-10T20:22:33" }, e.vetters.first)
      assert_equal({ "name" => "David Whitehead", "at" => "2011-07-28T05:59:00" }, e.vetters[2])
    end

    def test_two_headwords_and_web_address
      e = parse("alpha/1")
      assert_equal ["*)\\a", "a)/"], e.headwords_betacode
      assert_equal "Ἂ ἄ", e.headword, "smooth breathing + grave, then smooth + acute"
      assert_equal ["http://www.perseus.tufts.edu/hopper/text?doc=aristoph.+pl.+1052"], e.web_addresses
      assert_equal "Ross Scaife ✝", e.vetters.first["name"]
      assert_equal 8, e.vetters.size
    end

    def test_singular_keyword_label_is_read_too
      assert_equal ["dialects, grammar, and etymology"], parse("alpha/106").keywords,
                   "1,333 entries label the list 'Keyword:'"
    end

    def test_malformed_stamp_rides_verbatim
      assert_equal "2002-11-21T14:42:39", Nabu::Adapters::SolEntryParser.iso("21 November 2002@14:42:39")
      assert_equal "21 November 2002@014:42:39", Nabu::Adapters::SolEntryParser.iso("21 November 2002@014:42:39"),
                   "the export's one '@014:42:39' stamp is kept, never repaired"
    end

    def test_no_match_page_is_no_record
      error = assert_raises(Nabu::Adapters::SolEntryParser::NoRecord) { parse("epsilon/4079") }
      assert_match(/no-matches answer/, error.message)
    end

    def test_mis_keyed_query_page_is_no_record
      error = assert_raises(Nabu::Adapters::SolEntryParser::NoRecord) { parse("omicrioniota/8") }
      assert_match(/27 records/, error.message)
    end
  end
end
