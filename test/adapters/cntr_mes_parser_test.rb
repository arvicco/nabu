# frozen_string_literal: true

require "test_helper"

# The cntr-mes family: CNTR's Manuscript Encoding Specification, read
# against upstream's own grammar (MES.g4) on real fixture lines
# (test/fixtures/cntr/, README.md there). The preservation policy under
# test is the parser header's: text = the original scribe's reading with
# restorations read through and lacunae marked; the verbatim MES, the
# extant-only reading, the later hands and the word marks in annotations.
class CntrMesParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("cntr")
  PARSER = Nabu::Adapters::CntrMesParser

  def parse(rel, urn: "urn:nabu:cntr:test")
    PARSER.new.parse(File.join(FIXTURES, rel), urn: urn, title: "test")
  end

  def passage(rel, tail)
    parse(rel).find { |p| p.urn == "urn:nabu:cntr:test:#{tail}" } || flunk("no passage #{tail} in #{rel}")
  end

  # --- the lacunose papyrus: P52, John 18:31-33, 37-38 -----------------------

  def test_p52_verse_keys_and_order
    assert_equal(%w[john.18.31 john.18.32 john.18.33 john.18.37 john.18.38],
                 parse("class 1/P52.txt").map { |p| p.urn.split(":").last })
  end

  def test_supplied_text_reads_through_and_lacunae_mark
    verse = passage("class 1/P52.txt", "john.18.31")
    assert_equal "[…] οι ιουδαιοι ημειν ουκ εξεστιν αποκτειναι ουδενα", verse.text
    assert_equal "[…] οι ιουδαιοι ημε[…] […] ουδενα", verse.annotations["extant"],
                 "the witness's own letters: ημει^ν^ loses ιν, the ~words collapse to one gap"
    assert_equal({ "supplied_chars" => 22, "unclear_chars" => 2, "gaps" => 1 }, verse.annotations["leiden"])
    assert_equal "\\*οι ιουδαιο%ι% ημει^ν^ ~ουκ ~εξεστιν ~αποκτειναι /ουδενα", verse.annotations["mes"]
  end

  def test_word_marks_ride_the_tokens
    tokens = passage("class 1/P52.txt", "john.18.32").annotations["tokens"]
    assert(tokens.all? { |t| t["citation_part"] == "JOHN 18.32" })
    jesus = tokens.find { |t| t["form"] == "ιηυ" }
    assert_equal({ "form" => "ιηυ", "citation_part" => "JOHN 18.32", "supplied" => "vid",
                   "abbreviation" => "nomen-sacrum" }, jesus)
    logos = tokens.find { |t| t["form"] == "λογοσ" }
    assert_equal 1, logos["damaged"]
    assert_equal 3, logos["missing"]
    assert_equal "word", tokens.find { |t| t["form"] == "ποιω" }["supplied"]
    refute tokens.first.key?("supplied"), "a plain word carries only form + citation_part"
  end

  def test_trailing_lacuna_and_word_internal_breaks
    verse = passage("class 1/P52.txt", "john.18.33")
    assert verse.text.end_with?("των ιουδαιων […]"), "ι^ο^υ^/δ^αιων^&/11: the line break joins the word"
    assert verse.text.start_with?("ισηλθεν ουν παλιν εισ το πραιτωριον")
  end

  # --- corrections and later hands: 0171 + 03 ---------------------------------

  def test_a_later_hand_rides_corrections_not_the_text
    verse = passage("class 1/0171.txt", "luke.22.45")
    assert_includes verse.text, "ευρεν κοιμενουσ αυτουσ"
    assert_equal [{ "scribe" => "κοιμενουσ", "a" => "κοιμωμενουσ" }], verse.annotations["corrections"]
    assert(verse.annotations["tokens"].find { |t| t["form"] == "κοιμενουσ" }["corrected"])
  end

  def test_letterless_verses_mint_no_passage_but_land_in_metadata
    document = parse("class 1/0171.txt")
    assert_equal 30, document.size
    assert_equal ["LUKE 22.51", "LUKE 22.62"], document.metadata["absent_verses"]
    refute(document.any? { |p| p.urn.end_with?("luke.22.51") })
  end

  def test_a_repeated_ref_merges_in_file_order
    verse = passage("class 1/03.txt", "rom.4.4")
    assert_equal "τω δε εργαζομενω ο μισθοσ ου λογιζεται κατα χαριν αλλα κατα οφειλημα", verse.text,
                 "the deleted dittography (x{…} {}) contributes nothing; the repeat line supplies the reading"
    assert_equal 2, verse.annotations["split_lines"]
    assert_equal [{ "scribe" => "", "original" => "ο μισθοσ ου λογιζεται κατα χαριν αλλα κατα οφειλημα" }],
                 verse.annotations["corrections"]
    assert_equal 2, verse.annotations["mes"].lines.size
    assert_equal 9, parse("class 1/03.txt").size, "11 lines, two refs repeated"
  end

  def test_a_breaks_only_edit_is_layout
    verse = passage("class 1/03.txt", "john.10.25")
    assert verse.text.start_with?("απεκριθη αυτοισ ο ισ ειπον υμιν")
    assert_equal [{ "scribe" => "ο", "original" => "" }], verse.annotations["corrections"]
  end

  def test_the_terminating_nu_overline_stays_verbatim
    verse = passage("class 1/03.txt", "matt.1.2")
    assert verse.text.start_with?("αβρααμ εγεννησεν το¯ ισαακ"), "the terminating-nu overline stays verbatim"
  end

  def test_alternate_versification_marker
    verse = passage("class 1/03.txt", "phil.1.17")
    assert_equal [16], verse.annotations["alt_verses"]
    assert verse.text.start_with?("οι με¯ εξ αγαπησ")
  end

  # --- classes 2 and 3 ---------------------------------------------------------

  def test_class_two_and_three_files
    assert_equal ["urn:nabu:cntr:test:heb.1.1"], parse("class 2/62312.txt").map(&:urn)
    meli = parse("class 3/Meli.txt").first
    assert_equal "[…] δαυιδ εν πνι καλει κν αυτον […]", meli.text
  end

  def test_a_stray_condition_mark_is_tolerated_and_recorded
    verse = passage("class 3/Orig.txt", "1john.3.2")
    assert_includes verse.text, "ουπω εφανερωθη τι"
    assert_equal 1, verse.annotations["mes_anomalies"].size
    assert_match(/stray \^ before a word's first letter/, verse.annotations["mes_anomalies"].first)
  end

  # --- the grammar's edges ------------------------------------------------------

  def test_off_grammar_input_raises_parse_error
    parser = PARSER.new
    assert_raises(Nabu::ParseError) { parser.segments("αβγ {δε") }
    assert_raises(Nabu::ParseError) { parser.segments("αβ@γ") }
    assert_raises(Nabu::ParseError) { parser.segments("x{αβ}") }
  end

  def test_empty_verse_forms
    parser = PARSER.new
    assert_equal [:empty, "absent_verses"], parser.segments("-")
    assert_equal [:empty, "absent_verses_vid"], parser.segments("-~")
    assert_equal [:empty, "present_verses_vid"], parser.segments("+~")
  end

  def test_an_unknown_book_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "X.txt")
      File.write(path, "39001001 αβγ\n")
      assert_raises(Nabu::ParseError) { PARSER.new.parse(path, urn: "urn:nabu:cntr:x", title: "x") }
    end
  end

  def test_census_counts
    parser = PARSER.new
    parser.parse(File.join(FIXTURES, "class 1/03.txt"), urn: "urn:nabu:cntr:03", title: "GA 03")
    assert_equal 11, parser.census.verse_lines
    assert_equal 2, parser.census.merged_lines
    assert_equal 0, parser.census.empty_verses
  end
end
