# frozen_string_literal: true

require "json"
require "test_helper"

module Adapters
  # The wikisource-slavic parser family (P116-2) against the real page
  # captures in the five South Slavic fixture dirs — every shape the census
  # found: the header template (and the mk header that CARRIES the text),
  # the sr verse wrapper with its edition numbering, the Erlangen
  # apparatus sections, the hr ":"-indented couplets, sl prose, link-list
  # index pages, author pages, the bg original-script template lane.
  class WikisourceSlavicParserTest < Minitest::Test
    Parser = Nabu::Adapters::WikisourceSlavicParser

    def parser(*headers)
      Parser.new(header_templates: headers,
                 apparatus_headings: Nabu::Adapters::SlavicWikisource::APPARATUS_HEADINGS)
    end

    def wikitext(slug, pageid)
      path = File.join(Nabu::TestSupport.fixtures(slug), "pages", "#{pageid}.json")
      JSON.parse(File.read(path)).fetch("wikitext")
    end

    def test_verse_wrapper_is_line_grain_with_the_edition_numbering_stripped
      result = parser("заглавље").parse(wikitext("sr-wikisource", 22_093))
      assert(result.passages.all?(&:verse))
      assert_equal 66, result.passages.size, "one passage per verse line of the 66-line song"
      first = result.passages.first
      assert_equal "Фала Богу лијепе љепоте,", first.text, "the 0001 edition prefix is numbering, not text"
      refute(result.passages.any? { |p| p.text.match?(/\A\d{4}\s|стих|\{\{/) })
      assert_equal "Опет то, али друкчије · (Из Црне Горе).", first.section,
                   "consecutive centered heading lines join into one section path"
      refute(result.passages.any? { |p| p.text.include?("IIIв 552") }, "the bracketed siglum is apparatus")
      assert_includes result.apparatus.fetch("Избор"), "књига трећа 1846",
                      "the source section is cut from the text and returned beside it"
    end

    def test_erlangen_apparatus_sections_never_leak_into_the_text
      result = parser("заглавље").parse(wikitext("sr-wikisource", 28_813))
      assert_equal %w[Интервенције Напомене Коментар Извори], result.apparatus.keys
      assert_equal 22, result.passages.size
      assert_equal "Ја заљубим драго на далеко,", result.passages.first.text
      assert_equal "Ја заволех драгу надалеко", result.passages.first.section
      assert_match(/Детелић/, result.header.fetch("белешке"))
    end

    def test_header_text_param_carries_the_mk_body
      result = parser("Заглавје").parse(wikitext("mk-wikisource", 3686))
      assert_equal "на современ македонски правопис", result.header.fetch("забелешки")
      refute result.header.key?("текст"), "the text param is the body, never header metadata"
      assert_equal "Цуцуљ пасит гојада", result.passages.first.text
      assert(result.passages.all?(&:verse))
    end

    def test_colon_indented_couplets_are_verse_without_a_poem_tag
      result = parser("zaglavlje").parse(wikitext("hr-wikisource", 5889))
      assert(result.passages.all?(&:verse), "the Judita couplet layout is verse")
      assert_equal "S tom vojsko(m) prejako(m) Oloferne greduć,", result.passages.first.text,
                   "the edition's (m) restorations ride verbatim"
      assert_equal "Asiri(j)om jur svom prošal biše hituć.", result.passages[1].text
      assert_equal "Libro drugo", result.passages.first.section
    end

    def test_bare_interwiki_links_drop
      result = parser("zaglavlje").parse(wikitext("hr-wikisource", 12_823))
      refute(result.passages.any? { |p| p.text.start_with?("sr:") }, "[[sr:…]] is sister-wiki furniture")
      assert_equal 4, result.passages.map(&:stanza).uniq.size, "four sestets, four stanzas"
    end

    def test_prose_keeps_paragraph_grain
      result = parser("naslov", "naslov-mp").parse(wikitext("sl-wikisource", 18_712))
      refute(result.passages.any?(&:verse))
      assert result.passages.first.text.start_with?("Zemlja ima dvojno gibanje")
      assert_equal "Venceslav Bril", result.header.fetch("avtor")
    end

    def test_link_list_items_count_as_index_items
      result = parser("заглавље").parse(wikitext("sr-wikisource", 10_666))
      assert_operator result.index_items, :>, result.passages.size,
                      "the Erlangen table of contents is navigation"
    end

    def test_author_pages_are_flagged
      assert parser("Заглавје").parse(wikitext("mk-wikisource", 3552)).author_page
      refute parser("Заглавје").parse(wikitext("mk-wikisource", 3686)).author_page
    end

    def test_script_template_texts_reach_into_image_captions
      blocks = parser("Творба").template_texts(wikitext("bg-wikisource", 6045), name: "Script/Slavonic")
      assert_equal 2, blocks.size, "the Brashov charter's original sits in the facsimile caption"
      assert blocks.first.first.start_with?("† Ѿ гнⷣа • цр҃ѣ • Ср҃ацимира")
    end

    def test_script_template_texts_split_on_closing_br_forms
      blocks = parser("Творба").template_texts(wikitext("bg-wikisource", 6326), name: "Script/Slavonic")
      assert_operator blocks.first.size, :>, 5, "</br> separates the charter's paragraphs"
      refute(blocks.flatten.any? { |line| line.include?("&#") || line.include?("<") })
    end

    def test_refs_are_collected_not_text
      result = parser("Творба").parse(wikitext("bg-wikisource", 6194))
      assert(result.refs.any? { |ref| ref.start_with?("По редакция и издание") })
    end
  end
end
