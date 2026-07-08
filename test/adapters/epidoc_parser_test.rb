# frozen_string_literal: true

require "test_helper"
require "digest"
require "stringio"
require "tempfile"

# EpidocParser unit tests against the real Perseus fixtures (P2-2). The four
# editions cover the parser's hard cases: flat single-level line citation
# (Homeric Hymns 13/14), nested chapter/verse citation (2 John), and a
# structural non-citeable div wrapping flat line citation (Ausonius).
#
# P6-1 adds the structural-retry cases: the Iliad (refsDecl unit "line"/"book"
# vs body subtype "Book" — a case mismatch the CapiTainS subtype convention
# cannot see) and Nicomachus (refsDecl units "book"/"section" vs body subtype
# "chapter" — a renamed label). Both recover via the replacementPattern xpath.
class EpidocParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/perseus", __dir__)
  FIRST1K_FIXTURES = File.expand_path("../fixtures/first1k", __dir__)

  HH13_PATH = File.join(FIXTURES, "greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-grc2.xml")
  HH14_PATH = File.join(FIXTURES, "greekLit/data/tlg0013/tlg014/tlg0013.tlg014.perseus-grc2.xml")
  JOHN2_PATH = File.join(FIXTURES, "greekLit/data/tlg0031/tlg024/tlg0031.tlg024.perseus-grc2.xml")
  AUSONIUS_PATH = File.join(FIXTURES, "latinLit/data/stoa0045/stoa013/stoa0045.stoa013.perseus-lat2.xml")
  ILIAD_PATH = File.join(FIXTURES, "greekLit/data/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml")
  NICOMACHUS_PATH = File.join(FIRST1K_FIXTURES, "greekLit/data/tlg0358/tlg001/tlg0358.tlg001.1st1K-grc1.xml")

  HH13_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-grc2"
  HH14_URN = "urn:cts:greekLit:tlg0013.tlg014.perseus-grc2"
  JOHN2_URN = "urn:cts:greekLit:tlg0031.tlg024.perseus-grc2"
  AUSONIUS_URN = "urn:cts:latinLit:stoa0045.stoa013.perseus-lat2"
  ILIAD_URN = "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2"
  NICOMACHUS_URN = "urn:cts:greekLit:tlg0358.tlg001.1st1K-grc1"

  def parser
    Nabu::Adapters::EpidocParser.new
  end

  def parse_hh13
    parser.parse(HH13_PATH, urn: HH13_URN, language: "grc", title: "Hymn 13 To Demeter")
  end

  def parse_hh14
    parser.parse(HH14_PATH, urn: HH14_URN, language: "grc", title: "Hymn 14 to the Mother of the Gods")
  end

  def parse_john2
    parser.parse(JOHN2_PATH, urn: JOHN2_URN, language: "grc", title: "2 John")
  end

  def parse_ausonius
    parser.parse(AUSONIUS_PATH, urn: AUSONIUS_URN, language: "lat", title: "Genethliacon ad Ausonium Nepotem")
  end

  # --- HH13: minimal flat line citation ------------------------------------

  def test_hh13_document_fields
    doc = parse_hh13

    assert_equal HH13_URN, doc.urn
    assert_equal "grc", doc.language
    assert_equal "Hymn 13 To Demeter", doc.title
    assert_equal HH13_PATH, doc.canonical_path
  end

  def test_hh13_passages_urns_and_sequence
    doc = parse_hh13

    assert_equal 3, doc.size
    assert_equal ["#{HH13_URN}:1", "#{HH13_URN}:2", "#{HH13_URN}:3"], doc.passages.map(&:urn)
    assert_equal [0, 1, 2], doc.passages.map(&:sequence)
  end

  def test_hh13_text_extraction
    doc = parse_hh13

    assert_includes doc.passages[0].text, "Δημήτηρ"
    # Line 2 has no mixed content: exact match proves whitespace handling
    # (trailing space in the fixture stripped, nothing else touched).
    assert_equal "αὐτὴν καὶ κούρην, περικαλλέα Περσεφόνειαν.", doc.passages[1].text
    doc.passages.each do |passage|
      assert_equal "grc", passage.language
      assert_empty passage.annotations
      refute_match(/\s\s/, passage.text, "whitespace runs must be collapsed")
      assert_equal passage.text, passage.text.strip
    end
  end

  def test_hh13_text_normalized_is_the_minted_search_form
    doc = parse_hh13

    doc.passages.each do |passage|
      assert_equal Nabu::Normalize.search_form(passage.text, language: "grc"),
                   passage.text_normalized
    end
    # Boundary-minted (P6-4): marks stripped + downcased ("Δημήτηρ’" → "δημητηρ’").
    assert_includes doc.passages[0].text_normalized, "δημητηρ"
    # Final sigma normalizes: line 3 ends "ἀοιδῆς." → "αοιδησ."
    assert_includes doc.passages[2].text_normalized, "αοιδησ"
  end

  def test_hh13_parses_from_an_open_io
    doc = File.open(HH13_PATH) { |io| parser.parse(io, urn: HH13_URN, language: "grc") }

    assert_equal 3, doc.size
    assert_equal HH13_PATH, doc.canonical_path # picked up from IO#path
  end

  def test_io_without_path_requires_canonical_path
    io = StringIO.new(File.read(HH13_PATH))

    assert_raises(ArgumentError) { parser.parse(io, urn: HH13_URN, language: "grc") }

    io.rewind
    doc = parser.parse(io, urn: HH13_URN, language: "grc", canonical_path: HH13_PATH)

    assert_equal 3, doc.size
  end

  # --- HH14: second document of the same scheme -----------------------------

  def test_hh14_passage_count_matches_the_fixture
    doc = parse_hh14

    # The fixture contains exactly six <l> elements, n="1".."6".
    assert_equal 6, doc.size
    assert_equal (1..6).map { |n| "#{HH14_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_equal (0..5).to_a, doc.passages.map(&:sequence)
    assert_includes doc.passages[1].text, "Μοῦσα λίγεια"
  end

  # --- 2 John: two-level chapter/verse citation ------------------------------

  def test_2john_two_level_citation
    doc = parse_john2

    assert_equal 13, doc.size
    assert_equal (1..13).map { |n| "#{JOHN2_URN}:1.#{n}" }, doc.passages.map(&:urn)
    assert_equal (0..12).to_a, doc.passages.map(&:sequence)
  end

  def test_2john_text_extraction_collapses_internal_whitespace
    doc = parse_john2
    first = doc.passages.first

    # The verse text spans multiple physical lines in the fixture; internal
    # runs must collapse to single spaces and the <milestone unit="para"/> at
    # the start must not leave leading whitespace.
    assert first.text.start_with?("Ο ΠΡΕΣΒΥΤΕΡΟΣ")
    assert_includes first.text, "καὶ τοῖς τέκνοις αὐτῆς, οὓς ἐγὼ ἀγαπῶ ἐν ἀληθείᾳ"
    refute_match(/\s\s/, first.text)

    verse7 = doc.passages.find { |p| p.urn.end_with?(":1.7") }

    assert_includes verse7.text, "ἀντίχριστος"
  end

  # --- Ausonius: flat line citation despite a structural section div --------

  def test_ausonius_lines_are_cited_flat_ignoring_the_section_div
    doc = parse_ausonius

    assert_equal 28, doc.size
    # The div[@subtype="section" n="21"] is structural, NOT a citation level:
    # per the refsDecl, lines are cited by @n alone (":1", not ":21.1").
    assert_equal (1..28).map { |n| "#{AUSONIUS_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_equal "carmina prima tibi eum iam puerilibus annis", doc.passages.first.text
    assert_equal "lat", doc.language
    assert(doc.passages.all? { |p| p.language == "lat" })
  end

  # --- Iliad: structural retry from the refsDecl xpath (P6-1) ---------------
  #
  # The Iliad declares book.line citation but labels its book divs
  # subtype="Book" — the CapiTainS subtype-matching convention (case-sensitive
  # by upstream contract) never sees them, so the legacy pass fails with a
  # depth mismatch. The replacementPattern xpath
  # (/tei:body/tei:div/tei:div[@n='$1']//tei:l[@n='$2']) states the real
  # structure; the structural retry honors it.

  def parse_iliad
    parser.parse(ILIAD_PATH, urn: ILIAD_URN, language: "grc", title: "Iliad")
  end

  ILIAD_SUFFIXES = ((1..10).map { |n| "1.#{n}" } + (607..611).map { |n| "1.#{n}" } +
                    (1..19).map { |n| "2.#{n}" }).freeze

  def test_iliad_parses_with_book_line_urns
    doc = parse_iliad

    assert_equal 34, doc.size
    assert_equal ILIAD_SUFFIXES.map { |s| "#{ILIAD_URN}:#{s}" }, doc.passages.map(&:urn)
    assert_equal (0..33).to_a, doc.passages.map(&:sequence)
  end

  def test_iliad_text_spot_checks
    doc = parse_iliad
    by_suffix = doc.passages.to_h { |p| [p.urn.sub("#{ILIAD_URN}:", ""), p] }

    # Il. 1.1 — the most famous line of Greek literature.
    assert_includes by_suffix.fetch("1.1").text, "μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος"
    # Book boundary: 1.611 is the last line of book 1, 2.1 the first of book 2.
    assert_includes by_suffix.fetch("1.611").text, "ἔνθα καθεῦδʼ ἀναβάς"
    assert_includes by_suffix.fetch("2.1").text, "ἄλλοι μέν ῥα θεοί"
    # 2.8 sits inside a <q> wrapper: the descendant axis (//tei:l) must reach
    # lines nested below non-div intermediates.
    assert_includes by_suffix.fetch("2.8").text, "βάσκʼ ἴθι οὖλε ὄνειρε"
  end

  def test_iliad_urns_and_texts_are_stable_across_two_parses
    first = parse_iliad
    second = parse_iliad

    assert_equal first.passages.map(&:urn), second.passages.map(&:urn)
    assert_equal first.passages.map(&:text), second.passages.map(&:text)
  end

  # --- Nicomachus: renamed subtype labels, same structural recovery ---------
  #
  # tlg0358 declares book.section but labels its book divs subtype="chapter".
  # The xpath (div[@n='$1']/div[@n='$2']) recovers the two-level citation.
  def test_nicomachus_recovers_book_section_urns_from_the_xpath
    doc = parser.parse(NICOMACHUS_PATH, urn: NICOMACHUS_URN, language: "grc")

    assert_equal ["#{NICOMACHUS_URN}:1.1", "#{NICOMACHUS_URN}:2.1"], doc.passages.map(&:urn)
    assert_includes doc.passages[0].text, "Οἱ παλαιοὶ καὶ πρῶτοι μεθοδεύσαντες"
    assert_includes doc.passages[1].text, "Ἐπειδὴ στοιχεῖον λέγεται"
  end

  # --- golden regression (P6-1 frozen-urn safety) ----------------------------
  #
  # The structural retry runs ONLY after the legacy subtype pass has raised:
  # every document that parsed cleanly before P6-1 never reaches it, so its
  # urns AND text must be byte-identical. These digests are the complete
  # passage urn lists and passage texts of all pre-P6-1 perseus/first1k
  # fixtures, captured before the change.
  GOLDEN = {
    HH13_URN => [HH13_PATH, "grc", %w[1 2 3],
                 "19caba25b1a4b8ccaac1587240469058a9f9252ae38946d2397763e5f7e37f38"],
    HH14_URN => [HH14_PATH, "grc", %w[1 2 3 4 5 6],
                 "be6bdb1f79c49353da391528b550c634465332b2ad34d16ca959399dd8e0a0d4"],
    JOHN2_URN => [JOHN2_PATH, "grc", (1..13).map { |n| "1.#{n}" },
                  "2e19e2aef96d11c3a2ff4c5811d364347101e932198b3eabfa9a1cb618318b19"],
    AUSONIUS_URN => [AUSONIUS_PATH, "lat", (1..28).map(&:to_s),
                     "a1bcbf69dbf51d6a221e9f8f4ac5b2f65561c0bffa11ef1975e19f3f943ff9cc"],
    "urn:cts:greekLit:tlg2139.tlg001.1st1K-grc1" => [
      File.join(FIRST1K_FIXTURES, "greekLit/data/tlg2139/tlg001/tlg2139.tlg001.1st1K-grc1.xml"),
      "grc", %w[1], "42904032df7c28de0fecb6598901dde71f94b1f7b86eec5300dcf7c2382d8c75"
    ],
    "urn:cts:greekLit:tlg1126.tlg003.1st1K-grc1" => [
      File.join(FIRST1K_FIXTURES, "greekLit/data/tlg1126/tlg003/tlg1126.tlg003.1st1K-grc1.xml"),
      "grc", %w[1], "a4c7fcb8ee17f71f7fd22c27a37c9012e2d934d97c60db267ceece9a992349f5"
    ],
    "urn:cts:greekLit:tlg2959.tlg008.opp-grc1" => [
      File.join(FIRST1K_FIXTURES, "greekLit/data/tlg2959/tlg008/tlg2959.tlg008.opp-grc1.xml"),
      "grc", %w[1 2], "03ca17d1ff3e5538511d8ce2d048f9cf60ecbd92e82806de994205ed8b4b5233"
    ]
  }.freeze

  def test_golden_urn_lists_and_texts_of_pre_p6_fixtures_are_byte_identical
    GOLDEN.each do |urn, (path, language, suffixes, text_sha)|
      doc = parser.parse(path, urn: urn, language: language)

      assert_equal suffixes.map { |s| "#{urn}:#{s}" }, doc.passages.map(&:urn),
                   "#{urn}: urn list must be unchanged by the structural retry"
      assert_equal text_sha, Digest::SHA256.hexdigest(doc.passages.map(&:text).join("\n")),
                   "#{urn}: passage texts must be byte-identical"
    end
  end

  # --- genuinely contradictory refsDecl still quarantines --------------------

  def test_refsdecl_contradicting_the_body_still_quarantines_with_a_precise_message
    # String surgery on HH13 (never a hand-written fixture): declare a
    # two-level div/div citation while the body cites flat <l> lines. Neither
    # the subtype convention nor the declared xpath can honor that — the
    # document must stay quarantined, naming both failures.
    xml = File.read(HH13_PATH).sub(
      %r{<cRefPattern.*?</cRefPattern>}m,
      '<cRefPattern n="verse" matchPattern="(\w+).(\w+)" ' \
      'replacementPattern="#xpath(/tei:TEI/tei:text/tei:body/tei:div/' \
      "tei:div[@n='$1']/tei:div[@n='$2'])\"/>"
    )

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/no citable passages/i, error.message)
      assert_match(/structural retry/i, error.message)
    end
  end

  # --- Editorial noise --------------------------------------------------------

  def test_note_subtrees_are_dropped_from_passage_text
    # No fixture carries a <note> inside a citation unit, so exercise the
    # dropping rule by string-surgery on a fixture copy (never a hand-written
    # fixture file).
    xml = File.read(HH13_PATH)
              .sub("κούρην,", "κούρην,<note>editorial <bibl>noise</bibl></note>")

    with_tempfile(xml) do |path|
      doc = parser.parse(path, urn: HH13_URN, language: "grc")

      assert_equal "αὐτὴν καὶ κούρην, περικαλλέα Περσεφόνειαν.", doc.passages[1].text
      refute_includes doc.passages[1].text, "noise"
    end
  end

  # --- NFC, belt and braces across all four fixtures -------------------------

  def test_every_passage_of_every_fixture_is_nfc_and_non_empty
    [parse_hh13, parse_hh14, parse_john2, parse_ausonius].each do |doc|
      refute_empty doc.passages
      doc.passages.each do |passage|
        refute_empty passage.text
        assert passage.text.unicode_normalized?(:nfc), "#{passage.urn} text is not NFC"
        assert passage.text_normalized.unicode_normalized?(:nfc), "#{passage.urn} text_normalized is not NFC"
      end
    end
  end

  # --- Error cases -----------------------------------------------------------

  def test_urn_mismatch_raises_parse_error_naming_the_file
    wrong_urn = "urn:cts:greekLit:tlg9999.tlg999.perseus-grc2"
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HH13_PATH, urn: wrong_urn, language: "grc")
    end

    assert_includes error.message, File.basename(HH13_PATH)
    assert_includes error.message, wrong_urn
    assert_includes error.message, HH13_URN # the urn actually found in div[@type="edition"]/@n
  end

  def test_missing_refsdecl_raises_parse_error
    # String-surgery on a fixture copy (never a hand-written fixture file):
    # strip every refsDecl block from the header.
    xml = File.read(HH13_PATH).gsub(%r{<refsDecl.*?</refsDecl>}m, "")

    refute_includes xml, "cRefPattern" # surgery sanity check

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/cRefPattern|refsDecl/, error.message)
    end
  end

  def test_malformed_xml_raises_parse_error
    xml = File.read(HH13_PATH)
    truncated = xml[0, xml.index("<l n=\"2\"")] # cut mid-document: unclosed elements

    with_tempfile(truncated) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/malformed XML/i, error.message)
    end
  end

  def test_document_with_zero_citable_units_raises_parse_error
    # Remove every <l> element: structurally valid TEI, but nothing citable.
    xml = File.read(HH13_PATH).gsub(%r{<l n="\d+">.*?</l>}m, "")

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: HH13_URN, language: "grc")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/no citable passages/i, error.message)
    end
  end

  # --- Translation divs (P7-4) ------------------------------------------------
  # English editions anchor their body in div[@type="translation"]; acceptance
  # is per-parse via division_types: so composite original-language files that
  # ALSO embed a translation div (3 exist upstream) stay byte-identical under
  # the default ["edition"].

  HH13_ENG_PATH = File.join(FIXTURES, "greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-eng2.xml")
  HH13_ENG_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-eng2"

  def test_translation_div_is_not_accepted_by_default
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HH13_ENG_PATH, urn: HH13_ENG_URN, language: "eng")
    end
    assert_match(/no div\[@type="edition"\] found/, error.message)
  end

  def test_translation_div_parses_with_division_types
    doc = parser.parse(HH13_ENG_PATH, urn: HH13_ENG_URN, language: "eng",
                                      division_types: %w[translation edition])
    assert_equal HH13_ENG_URN, doc.urn
    assert_equal "eng", doc.language
    assert_equal ["#{HH13_ENG_URN}:1"], doc.passages.map(&:urn)
    assert_includes doc.passages[0].text, "rich-haired Demeter"
  end

  def test_translation_division_types_error_message_names_the_accepted_types
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HH13_PATH, urn: HH13_URN, language: "grc", division_types: ["translation"])
    end
    assert_match(/no div\[@type="translation"\] found/, error.message)
  end

  # --- P4 fallback: legacy pre-P5 TEI (P9-2) ---------------------------------
  #
  # 167 perseus-latin files are pre-P5 TEI: no div[@type="edition"|
  # "translation"], no CTS cRefPattern — citation lives in numbered container
  # divs (<div1 type="book">, plain <div type="book">) and <milestone
  # unit="chapter|section" n="..."/> streams, or (verse) in numbered <lb/>
  # marks, or (flat tractates) in nothing but <p> order. The P4 fallback
  # engages only after the P5 pass raised "no div[...] found" AND the header
  # declares no usable cRefPattern (a P5 doc without an edition div — the
  # first1k commentary class — must keep its exact quarantine message).

  LIVY_PATH = File.join(FIXTURES, "latinLit/data/phi0914/phi0011/phi0914.phi0011.perseus-lat3.xml")
  TACITUS_PATH = File.join(FIXTURES, "latinLit/data/phi1351/phi004/phi1351.phi004.perseus-eng1.xml")
  DIRAE_PATH = File.join(FIXTURES, "latinLit/data/phi0692/phi012/phi0692.phi012.perseus-lat1.xml")
  BOETHIUS_PATH = File.join(FIXTURES, "latinLit/data/stoa0058/stoa028/stoa0058.stoa028.perseus-eng1.xml")

  LIVY_URN = "urn:cts:latinLit:phi0914.phi0011.perseus-lat3"
  TACITUS_URN = "urn:cts:latinLit:phi1351.phi004.perseus-eng1"
  DIRAE_URN = "urn:cts:latinLit:phi0692.phi012.perseus-lat1"
  BOETHIUS_URN = "urn:cts:latinLit:stoa0058.stoa028.perseus-eng1"

  def parse_livy
    parser.parse(LIVY_PATH, urn: LIVY_URN, language: "lat", title: "Ab Urbe Condita, Liber I")
  end

  # Livy: the dominant P4 sub-shape (~64 of the 167) — P5 namespace but a
  # legacy <refState>-only refsDecl; one <div type="book" n="1"> container
  # with <milestone unit="chapter"> / <milestone unit="section"> streams
  # inside. Citation = div @n + milestone components in first-appearance
  # order; chapter milestones clear the deeper section component. The
  # praefatio chapter is n="pr" — non-numeric labels mint as-is.
  LIVY_SUFFIXES = ((1..13).map { |n| "1.pr.#{n}" } + (1..11).map { |n| "1.1.#{n}" } +
                   (1..6).map { |n| "1.2.#{n}" }).freeze

  def test_livy_p4_milestone_citation_mints_book_chapter_section
    doc = parse_livy

    assert_equal 30, doc.size
    assert_equal LIVY_SUFFIXES.map { |s| "#{LIVY_URN}:#{s}" }, doc.passages.map(&:urn)
    assert_equal (0..29).to_a, doc.passages.map(&:sequence)
  end

  def test_livy_p4_text_spot_checks
    doc = parse_livy
    by_suffix = doc.passages.to_h { |p| [p.urn.sub("#{LIVY_URN}:", ""), p] }

    # Praef. 1 — the famous opening of Ab Urbe Condita.
    assert_includes by_suffix.fetch("1.pr.1").text, "facturusne operae pretium sim"
    # Chapter boundary: 1.1.1 starts the Aeneas narrative.
    assert_includes by_suffix.fetch("1.1.1").text, "iam primum omnium satis constat Troia capta"
    assert_includes by_suffix.fetch("1.2.6").text, "Iouem indigetem appellant"
    doc.passages.each do |passage|
      assert_equal "lat", passage.language
      refute_match(/\s\s/, passage.text)
    end
  end

  def test_livy_p4_urns_and_texts_are_stable_across_two_parses
    first = parse_livy
    second = parse_livy

    assert_equal first.passages.map(&:urn), second.passages.map(&:urn)
    assert_equal first.passages.map(&:text), second.passages.map(&:text)
  end

  # Tacitus Histories: true TEI P4 (<TEI.2> DOCTYPE, no namespace), numbered
  # <div1 type="book" n>/<div2 type="chapter" n> containers, undefined ISO
  # entities in text (&aelig; — the DTD is never fetched).
  def test_tacitus_tei2_numbered_div_citation
    doc = parser.parse(TACITUS_PATH, urn: TACITUS_URN, language: "eng")

    assert_equal %w[1.1 1.2 2.1 2.2].map { |s| "#{TACITUS_URN}:#{s}" }, doc.passages.map(&:urn)
    assert_includes doc.passages[0].text, "I BEGIN my work with the time when Servius Galba"
    # Book boundary: 2.1 is the first chapter of book 2.
    assert_includes doc.passages[2].text, "IN a distant part of the world fortune was now preparing"
  end

  def test_tacitus_iso_entities_resolve_and_heads_are_dropped
    doc = parser.parse(TACITUS_PATH, urn: TACITUS_URN, language: "eng")

    # &aelig; must resolve to æ, not vanish (which would fuse "Sarmat rose").
    assert_includes doc.passages[1].text, "the Suevi and the Sarmatæ rose"
    # <head>BOOK I</head> / <head>JANUARY&mdash;MARCH ...</head> are title
    # apparatus, not passage text.
    doc.passages.each do |passage|
      refute_includes passage.text, "BOOK"
      refute_includes passage.text, "JANUARY"
    end
  end

  # Dirae-class verse (Appendix Vergiliana): no divs, no milestones — the
  # poem's lines are numbered <lb n="1"/>..<lb n="26"/> marks. Second ladder
  # rung: per-line citation from the lb stream.
  def test_lb_verse_mints_per_line_citations
    doc = parser.parse(DIRAE_PATH, urn: DIRAE_URN, language: "lat")

    assert_equal (1..26).map { |n| "#{DIRAE_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_includes doc.passages[0].text, "vir bonus et sapiens"
  end

  # Boethius tractates: bare <p> bodies — no citation apparatus at all. Third
  # ladder rung: 1-based <p> ordinals (the first p is empty and mints nothing,
  # so citations start at 2 — ordinals stay faithful to document structure).
  def test_bare_paragraph_body_mints_p_ordinals
    doc = parser.parse(BOETHIUS_PATH, urn: BOETHIUS_URN, language: "eng")

    assert_equal (2..7).map { |n| "#{BOETHIUS_URN}:#{n}" }, doc.passages.map(&:urn)
    assert_includes doc.passages[0].text, "whether Father"
  end

  # A P5 document without an edition div (the first1k commentary class) has a
  # usable cRefPattern: the P4 fallback must DECLINE and re-raise the original
  # error byte-identical — those quarantines are load-bearing reports (P9-1).
  # (test_translation_div_is_not_accepted_by_default above pins the same
  # decline on a real P5 translation file.)
  def test_p4_fallback_declines_p5_documents_with_a_cref_pattern
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HH13_ENG_PATH, urn: HH13_ENG_URN, language: "eng")
    end

    assert_equal "#{HH13_ENG_PATH}: no div[@type=\"edition\"] found", error.message
  end

  # Genuinely contradictory P4 citation labels stay quarantined precisely: the
  # census found 8 such files (e.g. Cato's praefatio div labeled chapter n="1"
  # colliding with the real chapter 1). String surgery on the Livy fixture
  # reproduces the shape: a repeated section milestone n collides.
  def test_p4_duplicate_citation_labels_still_quarantine_with_a_precise_message
    xml = File.read(LIVY_PATH).sub('<milestone n="3" unit="section"/>',
                                   '<milestone n="1" unit="section"/>')

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: LIVY_URN, language: "lat")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/no div\[@type=/, error.message)
      assert_match(/P4 retry/, error.message)
      assert_match(/duplicate passage urn/, error.message)
    end
  end

  # A legacy file where every ladder rung comes up empty stays quarantined
  # with a message naming both failures.
  def test_p4_file_with_no_citable_structure_stays_quarantined
    xml = File.read(BOETHIUS_PATH).gsub(%r{<p>.*?</p>}m, "").gsub(/<lb[^>]*>/, "")

    with_tempfile(xml) do |path|
      error = assert_raises(Nabu::ParseError) do
        parser.parse(path, urn: BOETHIUS_URN, language: "eng")
      end

      assert_includes error.message, File.basename(path)
      assert_match(/no div\[@type=/, error.message)
      assert_match(/P4 retry/, error.message)
      assert_match(/no citable passages/, error.message)
    end
  end

  # --- Streaming proof --------------------------------------------------------

  def test_implementation_streams_and_never_builds_a_full_document_dom
    # Perseus has >5 MB editions; the parser must go through
    # Nokogiri::XML::Reader, never a whole-document DOM. Runtime spying would
    # contort the design (packet spec), so this asserts on code structure: the
    # implementation contains no full-document parse entry point.
    source = File.read(File.expand_path("../../lib/nabu/adapters/epidoc_parser.rb", __dir__))

    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    refute_match(/Nokogiri::XML::Document/, source, "must not build a full XML document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end

  private

  def with_tempfile(content)
    Tempfile.create(["epidoc", ".xml"]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end
end
