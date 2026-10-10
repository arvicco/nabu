# frozen_string_literal: true

require "test_helper"
require "json"

module Adapters
  # The wikisource-html parser family (P116-3): server-rendered pages →
  # passages. Every case reads a REAL rendering from the Slavic wikisource
  # fixtures (api.php action=parse captures, 2026-10-10).
  class WikisourceHtmlParserTest < Minitest::Test
    def parser = Nabu::Adapters::WikisourceHtmlParser.new

    def html(slug, pageid)
      JSON.parse(File.read(File.join(Nabu::TestSupport.fixtures(slug), "pages", "#{pageid}.json"))).fetch("html")
    end

    def test_proofread_transclusion_output_is_the_text_root
      passages = parser.parse(html("pl-wikisource", 1481))
      texts = passages.map(&:text)
      assert(texts.any? { |t| t.start_with?("1. Bogv rodzicza dzewicza bogem slawena maria") },
             "the prp-pages-output Bogurodzica text is read")
      refute(texts.any? { |t| t.include?("Na podstawie") || t.include?("Józefa Brandta") },
             "the header box and figure captions outside the transclusion never leak")
      refute(texts.any? { |t| t.include?("własnością publiczną") }, "the licence box never leaks")
      refute(texts.any? { |t| t.include?("[9]") || t.include?("Strona:") }, "page-number markers strip")
    end

    def test_verse_lines_stay_lines_and_blank_lines_split_stanzas
      passages = parser.parse(html("pl-wikisource", 1481))
      first = passages.find { |p| p.text.start_with?("1. Bogv") }
      assert_equal ["1. Bogv rodzicza dzewicza bogem slawena maria",
                    "Vtwego syna gospodzina matko swolena maria",
                    "Sziszczi nam spwczi nam kyrieleyson"], first.text.split("\n")
      second = passages.find { |p| p.text.start_with?("2. Twego dzela") }
      refute_nil second, "the <br><br> stanza break opens a new passage"
    end

    def test_hidden_correction_readings_never_leak
      texts = parser.parse(html("pl-wikisource", 1481)).map(&:text)
      assert_includes texts, "(rp. warszawski z w. XV).",
                      "the displayed reading stays; the display:none [Korekta] print reading drops"
    end

    def test_reference_markers_strip_and_number_only_lines_drop
      texts = parser.parse(html("pl-wikisource", 25_521)).map(&:text)
      assert_equal 12, texts.size, "the cyzjojan's twelve month couplets, nothing else"
      refute(texts.any? { |t| t.match?(/\[\d+\]/) }, "reference markers never leak")
    end

    def test_headings_become_sections_not_passages
      passages = parser.parse(html("ru-wikisource", 34_424))
      assert_equal "Слово о пълку Игоревѣ, Игоря сына Святъславля, внука Ольгова.",
                   passages.first.section
      assert passages.first.text.start_with?("Не лѣполи ны бяшетъ, братіе")
    end

    def test_text_div_is_the_root_when_no_transclusion_output
      texts = parser.parse(html("ru-wikisource", 293_263)).map(&:text)
      assert texts.first.start_with?("Cе еси добра прекрасная моя"),
             "the ru <div class=text> body, header template excluded"
      refute_includes texts, "1670", "a number-only date line is not text"
    end

    def test_header_tables_and_navigation_never_leak
      texts = parser.parse(html("cs-wikisource", 9925)).map(&:text)
      assert_equal 1, texts.size
      assert texts.first.start_with?("Páni po koniu pojedú,\naž Bieliny řěky dojedú.")
      refute(texts.any? { |t| t.include?("Údaje o") || t.include?("Matice česká") },
             "the Textinfo table and the NavigacePaP bar are furniture")
    end

    def test_marginal_summaries_strip_from_the_kralice_verses
      texts = parser.parse(html("cs-wikisource", 68_927)).map(&:text)
      verse = texts.find { |t| t.include?("Elimelech/ a gméno ženy geho Noémi") }
      refute_nil verse
      refute_includes verse, "Hľad Elimelecha z wľaſti geho wypudiľ.",
                      "the print's marginal summary (poznamkapostrane) is not verse text"
    end
  end
end
