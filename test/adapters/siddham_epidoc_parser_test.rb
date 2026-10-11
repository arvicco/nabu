# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::SiddhamEpidocParser (P118-4): the Siddham EpiDoc
# dialect, parsed at PHYSICAL-LINE grain over trimmed-real fixtures
# (test/fixtures/siddham/README.md). Why not dharma-epidoc: Siddham nests
# half-verse <lg> groups (dharma's verse walk reads only direct <l>
# children and would lose them), its line numbers run CONTINUOUSLY
# across verse and prose (lb is the citation grain everywhere), and its
# standalone <sic> is the inscribed text (dharma drops every sic).
class SiddhamEpidocParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("siddham")

  def parse(name) = Nabu::Adapters::SiddhamEpidocParser.parse(File.join(FIXTURES, name))

  def unit(result, key) = result.passages.find { |u| u.key == key }

  def test_header_reads_title_idno_and_the_edition_language
    result = parse("IN00021_TEI.xml")
    assert_equal "Gadhwa Donation 3 of the Time of Kumāragupta I, GE 98", result.title
    assert_equal "IN00021", result.idno
    assert_equal "san-Latn", result.language
  end

  def test_a_line_runs_from_its_lb_across_paragraph_boundaries
    result = parse("IN00021_TEI.xml")
    assert_equal "jitaṃ bhagavatā| parama-bhāgavata-mahārājādhi", unit(result, "1").text,
                 "supplied/unclear read through; a <p> boundary is a space, never a line end"
    assert_equal "rāja-śrī-kumāragupta-rājya-saṃvatsare 90 8 […]", unit(result, "2").text,
                 "<num> keeps its printed text; a gap is the […] marker"
    assert_equal "[…] asyāṃ divasa-pūrvvāyāṃ paṭṭana[…]", unit(result, "3").text
  end

  def test_break_no_still_ends_the_physical_line
    result = parse("IN00021_TEI.xml")
    assert_equal "[…] nenātma-puṇy-opaca", unit(result, "4").text
    assert unit(result, "5").text.start_with?("yārtthaṃ"),
           "lb break=\"no\" opens line 5 (the titus/dharma line-grain precedent)"
  end

  def test_gap_only_lines_mint_nothing
    keys = parse("IN00002_TEI.xml").passages.map(&:key)
    %w[1 2 3 4 5 6].each { |key| refute_includes keys, key, "line #{key} is lost-gap markers only" }
    assert_includes keys, "7"
  end

  def test_verse_lines_carry_stanza_and_meter_through_nested_half_verses
    line9 = unit(parse("IN00002_TEI.xml"), "9")
    assert_equal "[…] babhūva dhanadāntaka-tuṣṭi-kopa- tulyaḥ", line9.text,
                 "a physical line spans the pāda boundary inside a nested half-verse lg"
    assert_equal({ "stanza" => "3", "met" => "vasantatilaka" }, line9.annotations)
  end

  def test_upstreams_gap_only_duplicate_line_mints_once
    keys = parse("IN00002_TEI.xml").passages.map(&:key)
    assert_includes keys, "27",
                    "upstream numbers line 27 twice; the second is lost-gap markers only and mints nothing"
    assert_equal keys.uniq, keys
  end

  def test_a_repeated_line_number_with_text_takes_an_occurrence_suffix
    with_doctored("IN00002_TEI.xml", '<lb n="26"/>', '<lb n="25"/>') do |path|
      units = Nabu::Adapters::SiddhamEpidocParser.parse(path).passages
      assert_equal %w[25 25+2], units.map(&:key).grep(/\A25/),
                   "a second line 25 takes a deterministic +2, never an overwrite"
      assert_includes units.find { |u| u.key == "25+2" }.text, "saṃsthāpitas"
    end
  end

  def test_textparts_and_plates_ride_annotations
    result = parse("IN00077_TEI.xml")
    seal = unit(result, "seal.1")
    assert_equal "śrī-mahārāja-hastinaḥ", seal.text
    assert_equal({ "textpart" => "seal" }, seal.annotations)
    line1 = unit(result, "1")
    assert_equal({ "textpart" => "body", "plate" => "1verso" }, line1.annotations)
    assert_equal "2recto", unit(result, "12").annotations["plate"], "a pb sets the plate for later lines"
    assert_equal %w[seal body], result.textparts
  end

  def test_standalone_sic_reads_through_and_choice_prefers_corr
    result = parse("IN00077_TEI.xml")
    assert_includes unit(result, "3").text, "asyān divasa",
                    "a standalone <sic> IS the inscribed text — read through"
    assert_includes unit(result, "11").text, "uttare paścimena",
                    "<choice><sic>o</sic><corr>e</corr></choice> reads the correction"
    assert_includes unit(result, "1").text, "svasti|", "<supplied reason=omitted> reads through"
    assert_includes unit(result, "3").text, "kulotpannena{|} mahā", "surplus is the {…} marker"
  end

  def test_an_ab_text_parses_as_one_line
    result = parse("IN00121_TEI.xml")
    assert_equal ["1"], result.passages.map(&:key)
    assert unit(result, "1").text.start_with?("aka[…] vihārasvāmi-gośūra")
    assert unit(result, "1").text.end_with?("pratolī ca||")
  end

  def test_comments_never_leak_into_text
    parse("IN00077_TEI.xml").passages.each do |u|
      refute_match(/Fleet|Bhandarkar/, u.text, "editorial XML comments are not text")
    end
  end

  def test_texts_are_nfc
    parse("IN00002_TEI.xml").passages.each { |u| assert u.text.unicode_normalized?(:nfc) }
  end

  def test_an_edition_without_any_lb_falls_back_to_verse_and_paragraph_units
    with_doctored("IN00002_TEI.xml", %r{<lb[^>]*/>}, "") do |path|
      result = Nabu::Adapters::SiddhamEpidocParser.parse(path)
      keys = result.passages.map(&:key)
      assert_includes keys, "2.cd.1", "no-lb mode: one unit per <l>, keyed by the lg @n path + l ordinal"
      assert_equal "[…] suvarṇṇa-dāne", result.passages.find { |u| u.key == "2.cd.1" }.text
      assert_equal({ "stanza" => "2", "met" => "vasantatilaka" },
                   result.passages.find { |u| u.key == "2.cd.1" }.annotations)
    end
  end

  def test_a_file_without_an_edition_div_raises_parse_error
    with_doctored("IN00121_TEI.xml", 'type="edition"', 'type="commentary"') do |path|
      assert_raises(Nabu::ParseError) { Nabu::Adapters::SiddhamEpidocParser.parse(path) }
    end
  end

  def test_an_edition_with_no_citable_text_raises_parse_error
    with_doctored("IN00121_TEI.xml", %r{<ab>.*</ab>}m, "<ab><lb n=\"1\"/><gap reason=\"lost\"/></ab>") do |path|
      assert_raises(Nabu::ParseError) { Nabu::Adapters::SiddhamEpidocParser.parse(path) }
    end
  end

  def test_an_unexpected_edition_language_raises_parse_error
    with_doctored("IN00121_TEI.xml", 'xml:lang="san-Latn"', 'xml:lang="pra-Latn"') do |path|
      error = assert_raises(Nabu::ParseError) { Nabu::Adapters::SiddhamEpidocParser.parse(path) }
      assert_match(/pra-Latn/, error.message, "the census found san-Latn only — anything else is loud")
    end
  end

  private

  # A real fixture with one deliberate substitution (the rem doctored-copy
  # pattern — never a hand-written TEI).
  def with_doctored(name, from, to)
    Dir.mktmpdir do |dir|
      text = File.read(File.join(FIXTURES, name), encoding: "bom|utf-8")
      doctored = text.gsub(from, to)
      refute_equal text, doctored, "the doctoring pattern must match the fixture"
      path = File.join(dir, name)
      File.write(path, doctored)
      yield path
    end
  end
end
