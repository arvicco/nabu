# frozen_string_literal: true

require "test_helper"

# CoraXmlParser tests (P80-5): the RAW CorA-XML family — the native export
# of the CorA annotation tool used by the Bochum/Hamburg reference-corpus
# projects. First registrant: ReF (Early New High German); the ReM/ReN
# CorA-XML sibling zips (ReM's pos/msd gap, ReN's dating gap) are future
# registrants. Fixtures are four structural trims of real ReF v1.0.2 texts
# (test/fixtures/ref/README.md) — never hand-written.
class CoraXmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ref")

  def parser
    Nabu::Adapters::CoraXmlParser.new
  end

  def fixture(name)
    Dir.glob(File.join(FIXTURES, "*", name)).first or flunk "missing fixture #{name}"
  end

  # --- header ---------------------------------------------------------------

  def test_header_reads_the_cora_header_and_the_key_value_fields
    header = parser.header(fixture("F011.xml"))
    assert_equal "F011", header.sigle
    assert_equal "Die Geometria. Deutsch", header.name
    assert_equal "ReF.MLU", header.fields["corpus"]
    assert_equal "fnhd", header.fields["language"]
    assert_equal "1487/88", header.fields["date"]
    assert_equal "Regensburg", header.fields["place"]
    assert_equal "nordbairisch", header.fields["language-area"]
    assert_equal "Druck", header.fields["medium"]
  end

  def test_header_drops_upstream_null_placeholders
    header = parser.header(fixture("F011.xml"))
    refute header.fields.key?("text-place"), '"-" is upstream\'s null, not a value'
    refute header.fields.key?("literature")
    header166 = parser.header(fixture("F166.xml"))
    refute header166.fields.key?("place")
    assert_equal "1. Hälfte 16. Jh.", header166.fields["date"]
  end

  def test_header_values_keep_inner_colons_and_literal_escapes
    header = parser.header(fixture("F313.xml"))
    assert_equal "Heiltum Bamberg: Die außruffunge des hochwirdig\\n heiligthums des " \
                 "loblichenn stifts zu bamberg", header.fields["text"],
                 "inner colons and upstream's literal backslash-n survive verbatim"
    notes = parser.header(fixture("F011.xml")).fields["notes-transcription"]
    assert_includes notes, "Faksimile-Ausgabe"
    assert_includes notes, "geduckter Nasal"
  end

  # --- lines (the layout grain) ---------------------------------------------

  def test_body_reconstructs_manuscript_lines_from_the_layoutinfo
    body = parser.body(fixture("F011.xml"))
    assert_equal 13, body.lines.size, "the trim keeps page 001r's 13 print lines"
    first = body.lines.first
    assert_equal ["001", "r", nil, "01"], [first.page, first.side, first.column, first.n]
    assert_equal "AUs der geometrey ettliche nuczpere ſtucklē die her",
                 Nabu::Normalize.nfc(first.text),
                 "diplomatic utf forms, space-joined (upstream is decomposed — the parser " \
                 "hands the raw surface through; the ADAPTER normalizes); the line-straddling " \
                 "token contributes only its first dipl here"
  end

  def test_a_line_straddling_token_splits_its_dipls_across_both_lines
    body = parser.body(fixture("F011.xml"))
    assert body.lines[0].text.end_with?(" her"), "t8_d1 (utf her) ends line 01"
    assert body.lines[1].text.start_with?("nach "), "t8_d2 (utf nach) opens line 02"
    lemmas = body.lines[0].tokens.map { |t| t["lemma"] }
    assert_includes lemmas, "hernach", "the straddler's anno record rides the line it starts on"
    refute_includes body.lines[1].tokens.map { |t| t["lemma"] }, "hernach"
  end

  def test_named_columns_join_the_line_citation
    body = parser.body(fixture("F313.xml"))
    refs = body.lines.map { |l| [l.page, l.side, l.column, l.n] }
    assert_includes refs, ["003", "r", nil, "19"], "the unnamed-column stretch cites folio.line"
    assert_includes refs, %w[003 v a 01], "the named column joins the citation"
  end

  def test_sideless_pages_and_duplicate_line_labels_pass_through_verbatim
    body = parser.body(fixture("F240.xml"))
    assert(body.lines.all? { |l| l.side.nil? }, "F240 pages carry no @side")
    labels = body.lines.map(&:n)
    assert_equal 2, labels.count("08"),
                 "upstream's duplicate line label survives verbatim (disambiguation is the " \
                 "adapter's job, not the parser's)"
  end

  # --- token records --------------------------------------------------------

  def test_token_records_carry_the_annotated_layer
    first = parser.body(fixture("F011.xml")).lines.first
    t1 = first.tokens.first
    assert_equal "t1_m1", t1["id"]
    assert_equal "AUs", t1["form"], "the house tokens surface key"
    assert_equal "aus", t1["lemma"]
    assert_equal "APPR", t1["pos"]
    assert_equal "GA07685", t1["lemma_id"]
    assert_equal "manual", t1["anno_type"]
    assert_equal ["lemma verified"], t1["flags"],
                 "cora-flag names ride verbatim (minus the punc/boundary mirrors)"
    refute t1.key?("morph"), "t1 carries no morph element"
    t2 = first.tokens[1]
    assert_equal "Fem.Dat.Sg", t2["morph"]
  end

  def test_ascii_rides_only_when_it_differs_from_form
    first = parser.body(fixture("F011.xml")).lines.first
    stuck = first.tokens.find { |t| t["lemma"] == "stücklein" }
    assert_equal "ſtucklē", Nabu::Normalize.nfc(stuck["form"])
    assert_equal "stucklen", stuck["ascii"], "the simplification layer differs — it rides"
    plain = first.tokens.find { |t| t["form"] == "der" }
    refute plain.key?("ascii"), "ascii == form carries no information"
  end

  def test_punctuation_split_annos_stay_separate_records
    first = parser.body(fixture("F166.xml")).lines.first
    records = first.tokens.select { |t| t["id"].start_with?("t1_") }
    assert_equal %w[t1_m1 t1_m2], records.map { |t| t["id"] },
                 "one dipl token, two anno units (the (,) split)"
    assert_equal "$_", records[1]["pos"]
  end

  def test_auto_annotation_carries_no_manual_mark
    body = parser.body(fixture("F313.xml"))
    assert(body.lines.flat_map(&:tokens).none? { |t| t.key?("anno_type") },
           "F313 is wholly auto-annotated (censused) — absence of anno_type means auto")
  end

  def test_punc_and_boundary_suggestions_ride_verbatim
    tokens = parser.body(fixture("F011.xml")).lines.flat_map(&:tokens)
    assert(tokens.any? { |t| t["punc"] == "(,)" }, "the modern-punctuation layer rides")
  end

  def test_dropped_annotation_lanes_never_leak
    tokens = parser.body(fixture("F011.xml")).lines.flat_map(&:tokens)
    %w[trans posLemma pos_lemma lemmaURL lemma_url checked].each do |key|
      assert(tokens.none? { |t| t.key?(key) }, "#{key} is a documented drop")
    end
  end

  def test_anno_level_comment_notes_ride_the_record
    tokens = parser.body(fixture("F166.xml")).lines.flat_map(&:tokens)
    assert_includes tokens.map { |t| t["comment"] }, "Mehl?",
                    "the annotator's doubt note is annotation content, not droppable apparatus"
  end

  # --- shifttags + loudness -------------------------------------------------

  def test_shifttag_spans_are_censused_by_kind
    assert_equal({ "lat" => 4 }, parser.body(fixture("F240.xml")).shifttags)
    assert_equal({ "title" => 1 }, parser.body(fixture("F166.xml")).shifttags)
    assert_empty parser.body(fixture("F011.xml")).shifttags
  end

  def test_top_level_editorial_comments_are_counted_and_their_text_swallowed
    body = parser.body(fixture("F240.xml"))
    assert_equal 12, body.comments, "the transcriber apparatus between tokens is censused"
    assert_empty body.unrecognized, "comment free text never leaks as loose #text"
    assert_equal 3, parser.body(fixture("F011.xml")).comments,
                 "F011's other two comments are anno-level @tag notes, not apparatus"
  end

  def test_clean_files_census_no_unrecognized_elements
    %w[F011.xml F166.xml F313.xml F240.xml].each do |name|
      assert_empty parser.body(fixture(name)).unrecognized, "#{name} is a censused-clean trim"
    end
  end

  # --- structural breakage is loud ------------------------------------------

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.xml")
      File.write(path, "<text id=\"X\"><layoutinfo>")
      assert_raises(Nabu::ParseError) { parser.body(path) }
    end
  end

  def test_a_dipl_before_any_line_start_raises
    Dir.mktmpdir do |dir|
      path = File.join(dir, "orphan.xml")
      doc = File.read(fixture("F011.xml"))
                .sub('<line id="l1" name="01" range="t1_d1..t8_d1"/>', "")
      File.write(path, doc)
      assert_raises(Nabu::ParseError) { parser.body(path) }
    end
  end
end
