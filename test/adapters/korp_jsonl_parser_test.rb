# frozen_string_literal: true

require "test_helper"

# The korp-jsonl parser family over landed VKS texts (real kwic rows,
# recorded 2026-10-21, in the KorpFetch landing shape): the passage = a
# run of one sentence_code; text from the word layer; pages, headings,
# scripture refs, per-element dates and abbreviation expansions as
# annotations.
class KorpJsonlParserTest < Minitest::Test
  TEXTS = File.join(Nabu::TestSupport.fixtures("vks"), "texts")

  def parse(corpus, stem)
    path = File.join(TEXTS, corpus, "#{stem}.jsonl")
    Nabu::Adapters::KorpJsonlParser.new.parse(File.read(path, encoding: "UTF-8"), label: path)
  end

  def units(corpus, stem) = parse(corpus, stem).first

  def test_a_run_of_one_sentence_code_is_one_passage
    frosterus = units("VKS_FROSTERUS", "jafro1791")
    assert_equal (1..8).map { |n| "JAFro1791-#{n}" }, frosterus.map(&:citation),
                 "40 Korp sentences fold into the corpus's own 8 codes"
  end

  # A Korp sentence whose only token is all-null ([[null, null, null]])
  # renders to nothing: it mints no passage — one empty sentence must never
  # quarantine a whole text (quarantine review 2026-11-13: six VKS texts,
  # each with one or two such sentences among 1,200–2,500). Three real
  # consecutive rows of VKS_BIBLIA rekisteri1 (sentence_ids 416–418).
  def test_an_all_null_token_sentence_mints_no_passage
    path = File.join(Nabu::TestSupport.fixtures("vks"), "empty-sentence", "rekisteri1.jsonl")
    units, rows = Nabu::Adapters::KorpJsonlParser.new.parse(File.read(path, encoding: "UTF-8"), label: path)
    assert_equal 3, rows.size
    assert_equal %w[1rek-0.0-A3a50 1rek-0.0-A3b4], units.map(&:citation),
                 "the empty 1rek-0:0-A3a51 sentence is dropped; its neighbours stand"
    assert(units.none? { |unit| unit.text.empty? })
  end

  def test_verse_codes_cite_with_the_colon_read_as_a_dot
    citations = units("VKS_BIBLIA", "ut1_ev").map(&:citation)
    assert_equal "Jh-19.38-623c", citations.first
    assert_includes citations, "Jh-19.00-623c", "the chapter summary keeps upstream's 00"
  end

  def test_text_is_the_word_layer_with_punctuation_glued
    verse = units("VKS_BIBLIA", "ut1_ev").first
    assert verse.text.start_with?("JA Joseph Arimathiast / joca oli Jesuxen Opetuslapsi")
    assert verse.text.end_with?("ruumin:")
  end

  def test_headings_and_scripture_refs_ride_as_annotations
    commandments = units("VKS_AGRICOLA", "agri1_abc1543").find { |u| u.citation == "abc1543-005" }
    assert_equal ["Ne Kymenen Käskyt / Hebrein textin ielkin. Exodi %xx."], commandments.annotations["headings"]
    assert_equal %w[2Ms-20:5 2Ms-20:6], commandments.annotations["refs"]
    assert_equal "005", commandments.annotations["page"]
  end

  def test_completed_abbreviations_ride_as_expansions
    expansions = units("VKS_AGRICOLA", "agri1_abc1543").flat_map { |u| u.annotations["expansions"] || [] }
    assert_includes expansions, { "form" => "minu", "completed" => "minun", "marked" => "minun~" }
    assert_includes expansions, { "form" => "Amud", "completed" => "Amund", "marked" => "Amun~d" },
                    "the tilde marks WHERE the abbreviation was completed"
  end

  def test_a_multi_dated_file_dates_each_passage
    decrees = units("VKS_LAIT", "as1800")
    assert_equal({ "not_before" => 1805, "not_after" => 1805 }, decrees.first.annotations["date"])
    assert_equal({ "not_before" => 1806, "not_after" => 1806 }, decrees.last.annotations["date"])
    refute units("VKS_FROSTERUS", "jafro1791").first.annotations.key?("date"),
           "a single-dated text dates at document grain only"
  end

  def test_a_malformed_line_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::KorpJsonlParser.new.parse("{\"structs\": {}}\n", label: "x.jsonl")
    end
    assert_match(/x\.jsonl:1/, error.message)
  end
end
