# frozen_string_literal: true

require "test_helper"

# The bim-tsv parser family over real windows of the BIM/SAHCOBA token
# streams: the declared passage rule (source page where the stream carries
# page markers, else the sentence), markup tokens kept out of the text,
# the decoded XML escapes, and the per-token annotation.
class BimTsvParserTest < Minitest::Test
  DIR = File.join(Nabu::TestSupport.fixtures("bim-sahcoba"), "BZENTROA-BIM")

  def units_of(author)
    path = File.join(DIR, "#{author}_automatikoa.tsv")
    Nabu::Adapters::BimTsvParser.new.units(File.read(path, encoding: "UTF-8"), label: path)
  end

  def test_page_markers_cut_the_stream_into_pages
    assert_equal %w[front p.i p.ii p.iii], units_of("Materra").map(&:citation)
  end

  def test_folio_labels_ride_verbatim
    assert_equal %w[p.90v p.91r], units_of("Beriain").map(&:citation)
  end

  def test_a_repeated_page_label_takes_the_collision_suffix
    assert_equal %w[p.584 p.585 p.585:b2], units_of("Axular").map(&:citation)
  end

  def test_a_stream_without_page_markers_is_cut_into_sentences
    units = units_of("Etxepare")
    assert_equal 49, units.size
    assert_equal "s.1", units.first.citation
    assert units.first.text.end_with?("berian."), "the first sentence closes on its period"
  end

  def test_markup_tokens_never_reach_the_text
    units_of("Materra").each do |unit|
      refute_match(%r{< (?:gap|text|/)}, unit.text)
      refute_match(/\A< ?[ivx]+ ?>/, unit.text)
    end
  end

  def test_tagged_spans_ride_as_annotations
    page = units_of("Beriain").first
    assert_equal ["\" pater noster \""], page.annotations["latin"], "the < lat > … < / lat > span"
    dedication = units_of("Materra").find { |unit| unit.citation == "p.ii" }
    assert dedication.annotations["gaps"].first.start_with?("À monseigneur, Monseigneur le reverendissime")
  end

  def test_xml_escapes_are_decoded_at_the_boundary
    page = units_of("Beriain").first
    assert_includes page.text, "\" pater noster \""
    refute_includes page.text, "&quot;"
  end

  def test_doubled_brackets_are_the_corpus_quotation_marks
    quoted = units_of("Etxepare").find { |unit| unit.text.include?("<<") }
    refute_nil quoted, "Etxepare's verse dialogues open with < <"
    assert_match(/<<Hilak oro/, quoted.text)
  end

  def test_tokens_carry_form_norm_lemma_and_both_tags
    token = units_of("Materra").first.annotations["tokens"][1]
    assert_equal({ "form" => "Kristiana", "norm" => "Kristianoa", "lemma" => "Kristianoa",
                   "upos" => "PROPN", "xpos" => "IZE" }, token)
  end

  def test_a_short_row_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::BimTsvParser.new.units("Eta\tEta\teta\tLOT\n", label: "x.tsv")
    end
    assert_match(/expected 5 TAB columns/, error.message)
  end
end
