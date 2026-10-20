# frozen_string_literal: true

require "test_helper"

# The SCAT TEI parser family (St. Petersburg Corpus of Hagiographic Texts,
# release 1.2.0): one <ab> per text, <pb n="N"/> / <pb n="-N"/> folio
# sides, <lb/> lines, every word a <w> with the manuscript form as text
# and a normalized spelling in @norm (lemma/pos/msd on the morphology
# subset). The fixtures are trimmed real release files; see
# test/fixtures/scat/README.md.
class ScatTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("scat")

  def pages(name)
    xml = Nabu::Adapters::SourceRead.utf8_file(File.join(FIXTURES, "#{name}.xml"), label: "scat")
    Nabu::Adapters::ScatTeiParser.new.pages(xml, label: name)
  end

  def nfc(text) = Nabu::Normalize.nfc(text)

  def test_title_is_the_tei_header_title
    xml = Nabu::Adapters::SourceRead.utf8_file(File.join(FIXTURES, "AKush.xml"), label: "scat")
    assert_equal "Житие Александра Куштского", Nabu::Adapters::ScatTeiParser.new.title(xml, label: "AKush")
  end

  def test_one_page_per_folio_side_with_recto_verso_citations
    assert_equal %w[f.371r f.371v f.372r], pages("AKush").map(&:citation),
                 "pb n=\"371\" is the recto, n=\"-371\" its verso (SCAT's sign convention)"
    assert_equal %w[371 -371 372], pages("AKush").map(&:folio), "upstream's pb n rides verbatim"
  end

  def test_words_split_across_lines_rejoin_and_punctuation_glues
    first = pages("AKush").first
    assert first.text.start_with?(nfc("м҇ⷭца июнѧ, въ ѳ҃ ⷣⷩꙺ. житїе и подвизи и ѿчасти чюде҇ⷭ, исповѣданїе прпⷣбнаго")),
           "the manuscript surface: lb-split words rejoin (по|двизи), pc glues left; got #{first.text[0, 90]}"
  end

  def test_margin_additions_keep_upstreams_own_brackets
    page = pages("AKush").last
    assert_includes page.text, nfc("постигнꙋти [могоⷯ]. иже ѡ немъ трꙋды"),
                    "the <add place=\"margin\"> word rides inline in upstream's own [ ] c-marks"
  end

  def test_tokens_carry_form_and_norm_and_mark_names
    tokens = pages("AKush").first.tokens
    assert_equal({ "form" => nfc("житїе"), "norm" => "ЖИТИЕ" }, tokens.find { |t| t["norm"] == "ЖИТИЕ" })
    assert(tokens.any? { |t| t["name"] == true }, "words inside <name> carry name: true")
  end

  def test_numeral_lemmas_are_not_lemmas
    tokens = pages("AKush").first.tokens
    nine = tokens.find { |t| t["norm"] == "9" }
    refute nine.key?("lemma"), "a <num> word's digit 'lemma' is a value, never a dictionary form"
  end

  def test_morphology_rides_on_the_annotated_subset
    tokens = pages("DmPrlc").first.tokens
    month = tokens.first
    assert_equal "месяць", month["lemma"]
    assert_equal "сущ", month["pos"]
    assert_equal "jo;род;ед;м", month["msd"]
  end

  def test_corrections_ride_as_annotations_not_text
    corrected = pages("DmPrlc").find { |p| p.corrections.any? }
    refute_nil corrected
    assert_equal [nfc("растѧщѹ")], corrected.corrections
    refute_includes corrected.text, nfc("растѧщѹ"), "a <note type=\"corr\"> is an editorial reading, not the witness"
  end

  def test_quotation_sources_ride_per_page
    sources = pages("DmPrlc").flat_map(&:quotations)
    refute_empty sources
    assert(sources.all? { |q| q.key?("source") })
  end

  def test_a_repeated_pb_with_text_on_both_sides_gets_a_suffixed_citation
    assert_equal %w[f.51v f.52r f.52v f.53r f.53r.2], pages("ThdTtm").map(&:citation),
                 "upstream repeats n=\"53\" with text on both sides — kept apart, never merged or renumbered"
  end

  def test_malformed_xml_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::ScatTeiParser.new.pages("<TEI><text><body><ab><pb n=\"1\"/><w>x</ab>", label: "bad")
    end
  end
end
