# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The `eltec-tei` parser family (P117-2): ELTeC level-1 novels (the
  # eltec-1 schema shared by every ELTeC language collection). Pinned
  # against trimmed real files of ELTeC-srp (test/fixtures/eltec-srp/level1/):
  # Два идола (1852; verse quotes, a 1893 print's title page), Ђурађ
  # Бранковић (1859; book groups, editor notes in back, a 1987 print
  # source), Пре среће (1918; Latin script) and Ђакон Богородичине цркве
  # (1919; a header whose author died 1958).
  class EltecTeiParserTest < Minitest::Test
    FIXTURES = File.join(Nabu::TestSupport.fixtures("eltec-srp"), "level1")

    def parser = Nabu::Adapters::EltecTeiParser.new
    def path(name) = File.join(FIXTURES, name)
    def parse(name) = parser.parse(path(name))

    def test_header_reads_title_author_life_years_and_refs
      header = parse("SRP18520_BogobojA_DvaIdola.xml").header
      assert_equal "SRP18520", header.xml_id
      assert_equal "sr", header.lang_tag
      assert_equal "Два идола", header.title, "the ' : ELTeC издање' suffix is stripped"
      assert_equal "Two idols", header.title_en
      assert_equal "Атанацковић, Богобој", header.author
      assert_equal 1826, header.author_birth
      assert_equal 1858, header.author_death
      assert_equal ["viaf:8970679", "wikidata:Q833421"], header.author_refs
      assert_equal ["wikidata:Q109336066"], header.title_refs
      assert_equal 44_207, header.words
      assert_equal "https://creativecommons.org/licenses/by/4.0/", header.licence
      assert_equal({ "author_gender" => "M", "size" => "short", "reprint_count" => "high",
                     "time_slot" => "T1" }, header.text_desc)
    end

    def test_first_edition_and_print_source_are_separate_bibls
      header = parse("SRP18590_JakovI_DjuradjB.xml").header
      assert_equal [1859], header.first_edition.years
      assert_equal "Пешта", header.first_edition.place
      print = header.print_source
      assert_equal [1987], print.years, "the digitized print is a modern reprint — the named edition layer"
      assert_equal "Матица српска ; Јединство", print.publisher
      assert_equal "Нови Сад ; Приштина", print.place
      assert_equal "Ђурађ Бранковић : историческиј роман", header.title
    end

    def test_header_alone_matches_the_full_parse
      %w[SRP18520_BogobojA_DvaIdola.xml SRP19190_IsidoraS_Djakon.xml].each do |name|
        assert_equal parse(name).header, parser.header(path(name))
      end
    end

    def test_unknown_years_and_a_late_death_are_read_honestly
      assert_equal 1958, parser.header(path("SRP19190_IsidoraS_Djakon.xml")).author_death
      Dir.mktmpdir do |dir|
        source = File.read(path("SRP18520_BogobojA_DvaIdola.xml"))
        File.write(File.join(dir, "x.xml"), source.sub("(1826-1858)", "(????-????)"))
        header = parser.header(File.join(dir, "x.xml"))
        assert_nil header.author_birth
        assert_nil header.author_death
        assert_equal "Атанацковић, Богобој", header.author
      end
    end

    def test_blocks_are_heads_lines_and_paragraphs_cited_by_div_path
      blocks = parse("SRP18520_BogobojA_DvaIdola.xml").blocks
      assert_equal %w[1.1 1.2 1.3 1.4 1.5], blocks.first(5).map(&:citation)
      assert_equal %w[head head l l p], blocks.first(5).map(&:kind)
      assert_equal "Тко ће народу помоћи?", blocks[2].text, "verse lines inside a quote are blocks"
      assert(blocks[4].text.start_with?("Ала је лепа земља то Српско Војводство"))
    end

    def test_the_title_page_is_furniture_and_pages_track_pb
      blocks = parse("SRP18520_BogobojA_DvaIdola.xml").blocks
      refute(blocks.any? { |b| b.text.include?("СРПСКА КЊИЖЕВНА ЗАДРУГА") },
             "the digitized print's title page is not the work")
      assert_equal "3", blocks.first.page
      assert_equal "4", blocks.find { |b| b.text == "У Војводству има белих градова, лепих и убавих села." }.page
    end

    def test_groups_nest_chapters_and_editor_notes_never_become_text
      parsed = parse("SRP18590_JakovI_DjuradjB.xml")
      citations = parsed.blocks.map(&:citation)
      assert_equal %w[1.1 1.1.1 1.1.2], citations.first(3)
      assert_equal "ПРВА КЊИГА", parsed.blocks.first.text
      refute(parsed.blocks.any? { |b| b.text.include?("Прим. прир.") }, "back/div[@type=notes] is apparatus")
      hafis = parsed.blocks.find { |b| b.text.start_with?("Хафис") }
      assert hafis.text.start_with?("Хафис и Марко!"), "the empty note anchor leaves no residue"
      assert_equal citations.uniq, citations
    end

    def test_body_blocks_outside_divs_sit_under_zero
      blocks = parse("SRP19180_MilicaJ_PreSrece.xml").blocks
      assert_equal "0.1", blocks.first.citation
      assert_equal "PRE SREĆE", blocks.first.text
      assert_equal "1.1", blocks[1].citation
    end

    def test_malformed_xml_is_a_parse_error
      Dir.mktmpdir do |dir|
        broken = File.join(dir, "broken.xml")
        File.write(broken, "<TEI><teiHeader></teiHeader><text><body><p>x</body></text></TEI>")
        assert_raises(Nabu::ParseError) { parser.parse(broken) }
      end
    end
  end
end
