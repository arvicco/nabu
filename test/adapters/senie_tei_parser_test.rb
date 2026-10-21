# frozen_string_literal: true

require "test_helper"

# The senie-tei parser family over real TEI elements cut from the SENIE
# fixture (the trimmed 2025-11-27 release file): one Unit per page / verse /
# section, the line-faithful main layer, furniture as annotations, the
# corr/sic pairing, and the search-form line rejoin.
class SenieTeiParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("senie"), "SENIE_Unicode.tei.xml")

  def units_of(id)
    @xml ||= File.read(FIXTURE, encoding: "UTF-8")
    start = @xml.index("<TEI>", @xml.index(%(fileDesc id="#{id}")) - 200)
    finish = @xml.index("</TEI>", start) + "</TEI>".length
    Nabu::Adapters::SenieTeiParser.new.units(@xml[start...finish], path: FIXTURE)
  end

  def test_pages_cite_upstreams_own_page_labels
    assert_equal %w[p.1 p.6 p.7], units_of("AP1622").map(&:citation)
  end

  def test_a_duplicated_page_number_takes_the_collision_suffix
    citations = units_of("Ench1586").map(&:citation)
    assert_equal "p.EB", citations.first
    assert_equal "p.EB:b2", citations.last, "the print numbers two sheets EB — both kept, document order"
  end

  def test_verses_cite_chapter_and_verse_and_headings_cite_what_follows
    citations = units_of("JT1685::2J").map(&:citation)
    assert_equal "1.0.head", citations.first, "the book title + chapter heading before verse 1:0"
    assert_equal (0..13).map { |v| "1.#{v}" }, citations.drop(1)
  end

  def test_sections_cite_their_number_without_the_trailing_dot
    assert_equal %w[s.0 s.1 s.2 s.3 s.5.6], units_of("SKL1696_KB").map(&:citation)
  end

  def test_text_keeps_the_print_lines_and_their_hyphens
    verse = units_of("JT1685::2J").find { |unit| unit.citation == "1.1" }
    assert verse.text.start_with?("1. TAs Wezzajs tai\nisredſetai Gaſpa-\nſchai")
  end

  def test_the_search_source_rejoins_hyphenated_line_breaks
    source = Nabu::Adapters::SenieTeiParser.search_source("isredſetai Gaſpa-\nſchai un\nwiņņa")
    assert_equal "isredſetai Gaſpaſchai un wiņņa", source
    assert_equal "Kaŗŗa= Teeſas", Nabu::Adapters::SenieTeiParser.search_source("Kaŗŗa=\nTeeſas"),
                 "the double-hyphen compound sign is upstream text, never a break to rejoin"
  end

  def test_the_unit_language_is_the_majority_run_language
    page = units_of("AP1622").find { |unit| unit.citation == "p.6" }
    assert_equal "lat", page.language, "the Agenda's Latin rubric dominates the page"
    assert_equal %w[de et lat lv], page.annotations["languages"].keys
    assert_includes page.annotations["foreign"], { "lang" => "et", "text" => "Ommes ſelatz üppres riſtmätä echk" }
  end

  def test_remarks_are_text_and_listed_as_marginalia
    page = units_of("AP1622").find { |unit| unit.citation == "p.6" }
    assert_includes page.text, "Nie ieſtli iuż okrſcżone od baby/ abo"
    assert_includes page.annotations["marginalia"], "o'd kogo innego?",
                    "the Polish catechism lines sit in Remark divs (lang-tagged Latvian upstream)"
  end

  def test_parallels_ride_as_annotations_never_text
    verse = units_of("JT1685::2J").find { |unit| unit.citation == "1.8" }
    assert_equal ["w:8. Gal: 3,4."], verse.annotations["parallels"]
    refute_includes verse.text, "Gal: 3,4."
  end

  def test_sic_is_the_text_and_corr_rides_as_a_correction
    page = units_of("AP1622").find { |unit| unit.citation == "p.7" }
    assert_includes page.text, "receptuſq'z in Eccleſiam"
    refute_includes page.text, "receptuſq'ue"
    assert_equal [{ "sic" => "receptuſq'z", "corr" => "receptuſq'ue" }], page.annotations["corrections"]
  end

  def test_a_sic_after_a_page_break_is_the_printed_page_number
    page = units_of("Depk1681_90_ms").find { |unit| unit.citation == "p.13" }
    assert_equal "14", page.annotations["printed_page"]
  end
end
