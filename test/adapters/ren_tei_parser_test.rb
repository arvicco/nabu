# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# RenTeiParser (P46-5): the ReN dialect of the cora-tei family, censused
# from the whole tei_1.1.zip deposit (235 files) — never invented. The
# dialect differs from ReM's on every axis the tests below pin: no
# teiHeader (files open at <text><body>), pos+msd instead of norm on
# annotated tokens (transcribed-only tokens carry neither), <s> sentence
# containers cross-cutting the manuscript lines, editorial apparatus
# (expan/del/add/gap/unclear and in-token <note>) whose text IS the
# surface, join="both", and page/line breaks landing INSIDE tokens.
class RenTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ren")

  def parser
    Nabu::Adapters::RenTeiParser.new
  end

  def body(name)
    parser.body(File.join(FIXTURES, name))
  end

  def hamb
    @hamb ||= body("anno/Hamb._Uk._1301-1350.tei")
  end

  def reval
    @reval ||= body("anno/Reval_Schragen_1351-1500.tei")
  end

  def line(body, page, number)
    body.lines.find { |l| l.page == page && l.n == number }
  end

  # --- lines: the layout grain (no @ed anywhere — all lineation is primary) ---

  def test_manuscript_lines_are_the_grain_with_zero_padded_numbers_kept_verbatim
    assert_equal 15, hamb.lines.size, "the CorA layoutinfo censuses l1..l15 for this charter"
    assert_equal %w[01 02 03], hamb.lines.first(3).map(&:n),
                 "upstream's zero-padded lb @n is the citation label, kept verbatim"
    assert(hamb.lines.all? { |l| l.page == "1" })
  end

  def test_sentence_containers_never_split_a_manuscript_line
    # Line 01 spans three </s><s> boundaries — <s> is sentence annotation,
    # not layout; the physical line reads straight through them.
    assert_equal "Dit se witlic alle den ghoͤnen de dessen bref sen . vnde hoͤren lesen . dat we her",
                 line(hamb, "1", "01").text
  end

  def test_columns_join_the_page_exactly_like_rem
    brs = body("anno/Brs._Ält._DegB_Altst._I.tei")
    assert_includes brs.lines.map { |l| [l.page, l.column, l.n] }, %w[1r a 01]
    assert_includes brs.lines.map { |l| [l.page, l.column, l.n] }, %w[1r b 01],
                    "two-column pages restart line numbers per column (the ReM M242 shape)"
  end

  # --- tokens: pos+msd+lemma, never norm --------------------------------------

  def test_annotated_tokens_carry_pos_msd_lemma_verbatim
    den = line(hamb, "1", "01").tokens.find { |t| t["id"] == "t5_m1" }
    assert_equal({ "id" => "t5_m1", "form" => "den", "pos" => "DDARTA<DD",
                   "msd" => "_.Dat.Pl", "lemma" => "dê¹,dê¹,dat²A" }, den,
                 "the HiNTS<HiTS pos pair, the msd, and the comma-chained lemma set, all verbatim")
  end

  def test_the_null_placeholder_drops_from_lemma_pos_and_msd
    dot = line(hamb, "1", "01").tokens.find { |t| t["id"] == "t11_m1" }
    assert_equal({ "id" => "t11_m1", "form" => ".", "pos" => "$;<$;" }, dot,
                 "punctuation is a <w> with pos $; — its msd/lemma are the '--' null and drop")
  end

  def test_transcribed_only_tokens_are_honestly_bare
    dub = body("trans/Dub._Uk._1301-1350.tei")
    assert_equal({ "id" => "t1_m1", "form" => "Allen" }, dub.lines.first.tokens.first,
                 "the 74 trans/ texts carry no annotation layer — id + form only")
  end

  # --- breaks inside tokens ---------------------------------------------------

  def test_a_line_break_inside_a_token_lands_the_whole_token_on_the_new_line
    juncvrowendale = line(hamb, "1", "03").tokens.first
    assert_equal "t34_m1", juncvrowendale["id"]
    assert_equal "Juncvrowen dale", juncvrowendale["form"],
                 "Junc<lb/>vrowen<space/>dale: parts glued, the scribal <space> kept"
    refute_includes line(hamb, "1", "02").tokens.map { |t| t["id"] }, "t34_m1"
  end

  def test_a_page_break_inside_a_token_lands_it_on_the_new_page
    stuyerschen = line(reval, "25v", "01").tokens.first
    assert_equal %w[t267_m1 stuyerschen], [stuyerschen["id"], stuyerschen["form"]],
                 "stuyer<pb n=25v/><lb n=01/>schen — the token finishes on 25v.01"
  end

  def test_the_hyphenation_equals_sign_is_witness_text_and_stays
    dub = body("trans/Dub._Uk._1301-1350.tei")
    vorgenompd = line(dub, "1r", "09").tokens.first
    assert_equal "vor=genompd", vorgenompd["form"],
                 "vor=<lb/>genompd — the scribal line-break mark is canonical"
  end

  # --- join gluing, including the ReN-only "both" -----------------------------

  def test_join_both_glues_on_both_sides
    first = line(reval, "23r", "01")
    assert_equal "Anno millequadringentiquadragintaseptem vppe passchen do", first.text,
                 "t2_m1(right) t2_m2(both) t2_m3(both) t2_m4(left) glue into one date word"
    date_joins = first.tokens.select { |t| t["id"] =~ /\At2_/ }.map { |t| t["join"] }
    assert_equal %w[right both both left], date_joins
  end

  # --- editorial apparatus: text flows into the form, flagged ------------------

  def test_expansion_text_is_part_of_the_form_and_flagged
    vppe = line(reval, "23r", "01").tokens.find { |t| t["id"] == "t3_m1" }
    assert_equal "vppe", vppe["form"], "vpp<expan>e</expan> — the expansion completes the form"
    assert_equal true, vppe["expan"]
  end

  def test_addition_and_deletion_text_stay_in_the_witness_flagged
    vorleende = line(reval, "23r", "02").tokens.find { |t| t["id"] == "t6_m1" }
    assert_equal ["vorleende", true], [vorleende["form"], vorleende["add"]]
    ferdinghe = reval.lines.flat_map(&:tokens).find { |t| t["id"] == "t276_m1" }
    assert_equal ["ferdinghe", true], [ferdinghe["form"], ferdinghe["del"]],
                 "<del>ferdin</del><lb/><del>ghe</del> — struck text is still the witness"
  end

  def test_an_in_token_note_is_the_token_surface_with_place_flagged
    # Censused corpus-wide: a <note> inside <w> is ALWAYS the token's whole
    # surface (639/639 in the four richest files) — another hand's text,
    # never apparatus glued onto an existing form.
    spfen = line(reval, "23r", "04").tokens.first
    assert_equal "t16_m1", spfen["id"]
    assert_equal "Spfen", spfen["form"], "S<gap/>pf<unclear>en</unclear> inside the note"
    assert_equal "bottom", spfen["note"]
    assert_equal true, spfen["unclear"]
    assert_equal true, spfen["gap"]
  end

  def test_a_token_that_is_only_an_illegible_gap_drops_with_a_loud_census
    refute_includes reval.lines.flat_map(&:tokens).map { |t| t["id"] }, "t294_m1",
                    "<w><note><gap reason=illegible/></note></w> has no witness text"
    assert_operator reval.unrecognized.fetch("empty-w"), :>=, 1
  end

  # --- notes outside tokens ---------------------------------------------------

  def test_editorial_notes_ride_the_next_manuscript_line
    assert_equal ["HBG1", "Hbg 1329"], line(hamb, "1", "01").notes,
                 "the ASnA charter sigle introduce the entry they precede"
    assert_empty line(hamb, "1", "02").notes
  end

  def test_a_free_standing_place_note_would_census_not_silently_drop
    # Censused: ALL 35,036 place-notes in the 1.1 deposit sit inside a
    # token — this branch is defensive, pinned with a doctored file (the
    # ReM doctoring precedent) so a future deposit that grows free
    # marginalia is loud, never silent.
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "anno/Hamb._Uk._1301-1350.tei"))
                     .sub("<w xml:id=\"t3_m1\"",
                          "<note place=\"margin left\">al<unclear>t</unclear></note><w xml:id=\"t3_m1\"")
      path = File.join(dir, "doctored.tei")
      File.write(path, doctored)
      census = parser.body(path).unrecognized
      assert_equal 1, census["note[margin left]"]
      refute census.key?("#text"), "swallowed note text must not double-count as stray witness text"
      refute census.key?("unclear"), "markup inside the swallowed note is part of the apparatus"
    end
  end

  # --- loudness ---------------------------------------------------------------

  def test_truly_unknown_elements_still_census_loudly
    Dir.mktmpdir do |dir|
      doctored = File.read(File.join(FIXTURES, "anno/Hamb._Uk._1301-1350.tei"))
                     .sub("<w xml:id=\"t3_m1\"", "<seg>x</seg><w xml:id=\"t3_m1\"")
      path = File.join(dir, "doctored.tei")
      File.write(path, doctored)
      census = parser.body(path).unrecognized
      assert_equal 1, census["seg"]
      assert_equal 1, census["#text"]
    end
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.tei")
      File.write(path, "<text><body><ab><s><lb n=\"01\"/><w>unclosed")
      assert_raises(Nabu::ParseError) { parser.body(path) }
    end
  end
end
