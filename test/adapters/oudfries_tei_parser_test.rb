# frozen_string_literal: true

require "test_helper"

# The oudfries-tei parser family: the Corpus Oudfries TEI witness files
# (INT/IvdNT, research_private). The bytes never enter git — the members are
# read from the gitignored local fixture zip, and every case skips (= fails
# on the owner's box, StrictSkips) when it is absent.
class OudfriesTeiParserTest < Minitest::Test
  SLUG = "corpus-oudfries"

  def test_the_header_interp_groups_become_the_metadata_hash
    text = parse("E1-Hav.tei.3.exported.xml")
    meta = text.meta
    assert_equal "E1-Hav", meta["title"]
    assert_equal "Three Capital Crimes", meta["title_text_EN"]
    assert_equal "Drie Hoofddaden", meta["title_text_NL"]
    assert_equal "Emsingo", meta["manuscript_region"]
    assert_equal "East Old Frisian", meta["manuscript_dialect_EN"]
    assert_equal "1375", meta["manuscript_year_from"]
    assert_equal "1312", meta["text_year_to"]
    refute meta.key?("text_category_3"), "an empty <interp/> carries no claim"
  end

  def test_one_line_becomes_one_passage_with_post_punctuation_glued
    text = parse("E1-Hav.tei.3.exported.xml")
    assert_equal 1, text.lines.size
    line = text.lines.first
    assert_equal 1, line.seq
    assert_equal "5:18", line.n
    assert_equal "Thi mon mey enes deis thria haued-deda dua uuif nede nima mon sla. and stela.", line.text
  end

  def test_tokens_carry_form_lemma_pos_and_gloss_verbatim
    tokens = parse("E1-Hav.tei.3.exported.xml").lines.first.tokens
    assert_equal 15, tokens.size, "one token per <w>; <pc> is reading text, not a token"
    assert_equal({ "form" => "Thi", "lemma" => "thî", "pos" => "DET", "gloss" => "de, die" }, tokens.first)
    multi = tokens.find { |t| t["form"] == "haued-deda" }
    assert_equal({ "form" => "haued-deda", "lemma" => "hâveddêde", "pos" => "NOUN", "multiword" => true }, multi)
  end

  def test_the_seventeen_statutes_open_with_the_known_line
    line = parse("R1-K17.data.xml").lines.first
    assert_equal "1", line.n
    assert_equal "Thit is thiv forme liodkest. and thes kyning-kerles ieft. and londriuch allera frisona.", line.text
    assert_equal "kening Karel", line.tokens.find { |t| t["form"] == "kyning-kerles" }["lemma"]
  end

  def test_an_unnumbered_line_is_still_a_passage_with_no_n
    lines = parse("R1-K17.data.xml").lines
    assert_nil lines[1].n
    assert_equal 2, lines[1].seq
  end

  def test_pre_punctuation_glues_to_the_next_word_and_blank_lemmas_drop
    line = parse("R1-Mrk.data.xml").lines.first
    assert line.text.start_with?(":1 Thiu ield"), line.text
    numeral = line.tokens.first
    assert_equal({ "form" => "1" }, numeral, "lemma=\"\" type=\"\" carry no claim")
  end

  def test_floating_punctuation_stands_alone_and_punctuation_only_lines_are_skipped
    text = parse("B2-BrBb.data.xml")
    assert(text.lines.any? { |l| l.text.start_with?(". thera mutha ek") })
    assert(text.lines.all? { |l| l.tokens.any? }, "a <l> holding only <pc> is no passage")
    assert_equal 2, text.skipped_lines, "B2-BrBb holds two <l><pc>.</pc></l> lines"
    seqs = text.lines.map(&:seq)
    assert_equal (1..seqs.size).to_a, seqs, "seq stays dense across skipped lines"
  end

  def test_the_mis_nested_line_splits_at_its_start_and_keeps_its_tail
    lines = parse("E1-Bro.tei.3.exported.xml").lines
    outer = lines.find { |l| l.n == "5:15" }
    inner = lines.find { |l| l.n == "5:16" }
    assert outer.text.end_with?("nauuet wertha."), outer.text
    assert inner.text.start_with?("Der weren ac tre brothere."), inner.text
    assert inner.text.end_with?("And bi liuda londriuchte."),
           "the tokens after the inner </l> finish the inner line's sentence"
    assert_equal(1, lines.count { |l| l.n == "5:15" })
  end

  def test_malformed_xml_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::OudfriesTeiParser.new.text("<TEI><teiHeader>", name: "broken.xml")
    end
  end

  private

  def parse(member)
    zip = File.join(fixtures, "CorpusOudfries1.0.zip")
    bytes = Nabu::Shell.run("unzip", "-p", zip, "CorpusOudfries1.0/Data/#{member}")
    Nabu::Adapters::OudfriesTeiParser.new.text(bytes, name: member)
  end

  def fixtures
    skip "#{SLUG} local fixtures absent (INT-NC, no-redistribution — bytes never in git)" unless
      Nabu::TestSupport.local_fixtures?(SLUG)

    Nabu::TestSupport.local_fixtures(SLUG)
  end
end
