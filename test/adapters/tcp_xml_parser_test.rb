# frozen_string_literal: true

require "test_helper"
require "stringio"

# TcpXmlParser (P82-2): the tcp-xml family — the TCP schema (eebo2prf.xml.dtd,
# the EEBO-TCP/ECCO-TCP/Evans-TCP lineage) as the Corpus of Middle English's
# May-2026 normalization actually ships it: UPPERCASE element names under an
# <ETS> root (<HEADER> + <EEBO><IDG/><TEXT>…), NOT lowercase TEI P5. Built
# for reuse — a future EEBO-TCP wave (~60k texts) rides this same machinery,
# so the CME adapter composes the family and owns none of it.
#
# Every expectation below is pinned from the four REAL fixture files
# (test/fixtures/cme/texts/, retrieved 2026-08-23 — see the fixture README).
# The format's own surprises, recorded honestly:
#
#   - TEXT nests inside a DIV1 of another TEXT with NO <GROUP> (CME00121):
#     the div stack is NESTING-driven, never ladder-rank-driven.
#   - <CHOICE><SIC>…</SIC><CORR>…</CORR></CHOICE> order varies file-to-file
#     and SIC can hold editorial prose, not text ("[scratched out in MS.]"
#     in ajt8135) — the reading takes CORR, drops SIC-inside-CHOICE.
#   - <IDG ID="CME00000"> is a PLACEHOLDER shared by many files — never an
#     identity; the caller's urn (the filename) is.
#   - <AUTHOR/> appears EMPTY before the real <AUTHOR TYPE="add"> — an empty
#     element must not consume the first-wins capture slot.
#   - <GAP DESC="illegible" … DISP="•"/> carries upstream's display glyph;
#     the reading text takes a plain space, never the glyph.
class TcpXmlParserTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("cme"), "texts")

  def parse(file, urn: "urn:nabu:cme:#{File.basename(file, '.xml')}", **)
    Nabu::Adapters::TcpXmlParser.new.parse(
      File.join(FIXTURES, file), urn: urn, language: "enm", **
    )
  end

  def hematoscopy = @hematoscopy ||= parse("CME301.xml")

  def tenwives = @tenwives ||= parse("tenwives.xml")

  def catechism = @catechism ||= parse("CME00011.xml")

  def carols = @carols ||= parse("CME00121.xml")

  # -- grain: heads, prose blocks, verse lines --------------------------------

  def test_prose_document_parses_at_head_and_block_grain
    assert_equal 64, hematoscopy.count, "2 HEADs + 62 prose blocks (OPENER/ARGUMENT/P)"
    assert_equal "urn:nabu:cme:CME301:d1.h1", hematoscopy.first.urn
    assert_equal(%w[d1.h1 d1.h2 d1.p1 d1.p2 d1.p3],
                 hematoscopy.to_a.first(5).map { |p| p.urn.split(":").last })
    assert_includes hematoscopy.to_a[2].text, "Transcribed from manuscripts Sloane 3486"
    assert_includes hematoscopy.to_a[4].text,
                    "A phisiciane bihoueþ to knowe þre manerʼ inspecciouns"
  end

  def test_verse_document_parses_at_line_grain
    # front title page: 3 <P>; body poem: 1 <HEAD> + 20 <LG> × 6 <L>.
    assert_equal 124, tenwives.count
    assert_equal "urn:nabu:cme:tenwives:d2.l1", tenwives.to_a[4].urn
    assert_equal "LEve, lystynes to me", tenwives.to_a[4].text
    assert_equal "urn:nabu:cme:tenwives:d2.l120", tenwives.to_a.last.urn,
                 "<LG> stanzas are transparent — line ordinals run per div, not per stanza"
  end

  def test_head_rubrics_are_reading_passages_not_apparatus
    head = tenwives.to_a[3]
    assert_equal "urn:nabu:cme:tenwives:d2.h1", head.urn
    assert_equal "A Talk of Ten Wives on their Husbands' Ware", head.text,
                 "CME <HEAD> is the transcribed medieval rubric — reading text, " \
                 "unlike the editorial captions the croala/epidoc families drop"
    assert_equal "head", head.annotations["unit"]
  end

  # -- the nested-TEXT surprise (CME00121) ------------------------------------

  def test_a_text_nested_inside_a_div_of_another_text_stacks_by_nesting
    assert_equal 154, carols.count
    urns = carols.map { |p| p.urn.split(":").last }
    assert_includes urns, "d1.h1", "the outer TEXT's DIV1 head"
    assert_includes urns, "d1.d1.l1",
                    "the inner <TEXT> (no <GROUP>!) sits INSIDE the outer DIV1 — its DIV1 " \
                    "is a nested frame (d1.d1), so citations stay unique without any GROUP rule"
    inner_first = carols.find { |p| p.urn.end_with?("d1.d1.l1") }
    assert_equal "»Ecce ancilla domini«,", inner_first.text
  end

  # -- front/body provenance --------------------------------------------------

  def test_front_matter_passages_carry_the_division_annotation
    title_page = tenwives.first
    assert_equal "urn:nabu:cme:tenwives:d1.p1", title_page.urn
    assert_equal "front", title_page.annotations["division"]
    assert_includes title_page.text, "Jyl of Breyntford's Testament"
    assert_nil tenwives.to_a[4].annotations["division"], "body is the silent default"
  end

  # -- apparatus drops ---------------------------------------------------------

  def test_marginal_and_foot_notes_drop_their_subtrees
    line = tenwives.to_a.find { |p| p.text.include?("herkenes to my songe") }
    assert_equal "And herkenes to my songe;", line.text,
                 "the <NOTE PLACE=\"marg\"> inside the line is the 1871 editor's " \
                 "apparatus — dropped whole, the reading text flows around it"
    refute(catechism.any? { |p| p.text.include?("Wülcker's Altengl. lesebuch") },
           "German foot-notes never leak into passages")
  end

  def test_choice_takes_corr_and_drops_sic
    passage = hematoscopy.to_a.find { |p| p.text.include?("Blod þat is þynne") }
    assert_includes passage.text, "þouȝ",
                    "<CHOICE><SIC>youȝ</SIC><CORR>þouȝ</CORR></CHOICE> reads CORR"
    refute_includes passage.text, "youȝ", "SIC inside CHOICE is the typo record, not text"
  end

  def test_add_and_del_both_stay_transparent
    added = hematoscopy.to_a.find { |p| p.text.include?("colour þan rody or rede") }
    assert_includes added.text, "oþer colour", "<ADD> is transcription — kept"
    deleted = hematoscopy.to_a.find { |p| p.text.include?("bytokneþ þat") }
    assert_includes deleted.text, "is bytokneþ",
                    "<DEL> is transcription of a scribal deletion — kept (canonical means canonical)"
  end

  def test_gap_reads_as_a_space_never_the_display_glyph
    refute(catechism.any? { |p| p.text.include?("•") },
           "<GAP DISP=\"•\"/> is upstream's rendering hint; the reading takes a space")
  end

  def test_milestones_and_line_breaks_read_as_spaces
    passage = hematoscopy.to_a[4]
    refute_includes passage.text, "166r", "the <MILESTONE UNIT=\"fol.\"> cite never enters text"
    assert_includes passage.text, "lettyng A phicisian",
                    "<LB/> between the interlinear pair reads as a single space"
  end

  # -- drama: speakers ---------------------------------------------------------

  def test_speech_passages_carry_the_speaker_annotation
    first_speech = catechism.to_a[2]
    assert_equal "urn:nabu:cme:CME00011:d1.p1", first_speech.urn
    assert_equal "Clerk:", first_speech.annotations["speaker"]
    assert_equal "Sei me, where was god whanne he made heven and erthe?", first_speech.text,
                 "<SPEAKER> is a structural label — annotation, never reading text"
    assert_equal "Maister:", catechism.to_a[3].annotations["speaker"],
                 "inline <HI> inside SPEAKER stays transparent in the label"
  end

  # -- page provenance ---------------------------------------------------------

  def test_passages_carry_the_page_in_force
    assert_equal "29", tenwives.to_a[3].annotations["page"],
                 "<PB REF=\"\" N=\"29\"/> before the poem head is the page cite in force"
    assert_nil tenwives.first.annotations["page"], "no <PB> seen yet on the title page"
  end

  # -- header metadata ---------------------------------------------------------

  def test_header_metadata_rides_the_document
    metadata = tenwives.metadata
    assert_equal "A talk of ten wives on their husbands' ware / ed. by Frederick J. Furnivall.",
                 tenwives.title
    assert_equal "Furnivall, Frederick James, 1825-1910.", metadata["editor"]
    assert_equal "tenwives", metadata["idno"], "IDNO TYPE=\"dlps\" — not notis, not imev"
    assert_equal "2003", metadata["pub_date"]
    assert_includes metadata["availability"], "public domain"
    assert_equal "1871", metadata["source_date"], "the print edition's own year (BIBLFULL)"
    assert_equal "London", metadata["source_pub_place"]
    assert_equal "CME00000", metadata["idg_id"],
                 "the shared placeholder IDG id — captured verbatim, NEVER an identity"
  end

  def test_an_empty_author_element_never_consumes_the_capture
    assert_equal "Horstmann, Karl", catechism.metadata["author"],
                 "<AUTHOR/> (empty) precedes <AUTHOR TYPE=\"add\">Horstmann, Karl</AUTHOR> — " \
                 "first-wins capture must skip empty elements"
  end

  def test_language_usage_and_text_lang_are_censused_verbatim
    assert_equal "enm=English, Middle (1100-1500)", hematoscopy.metadata["language_usage"]
    assert_equal "enm", hematoscopy.metadata["text_lang"]
    assert_nil tenwives.metadata["text_lang"], "tenwives' <TEXT> carries no LANG attr"
  end

  def test_a_document_without_bibfull_has_no_source_keys
    refute hematoscopy.metadata.key?("source_date"),
           "CME301 is transcribed straight from manuscripts — no BIBLFULL, no source_* keys"
  end

  # -- seams -------------------------------------------------------------------

  def test_the_license_mapper_seam_maps_availability_to_an_override
    document = parse("CME301.xml",
                     license_mapper: ->(availability) { "open" if availability&.include?("public domain") })
    assert_equal "open", document.license_override
    assert_nil parse("CME301.xml").license_override, "no mapper — the source class governs"
  end

  def test_the_metadata_mapper_seam_merges_extra_keys_header_wins
    document = parse("CME301.xml",
                     metadata_mapper: ->(header) { { "batch" => "phase3", "idno" => header["idno"] } })
    assert_equal "phase3", document.metadata["batch"]
    assert_equal "CME00301", document.metadata["idno"]
  end

  def test_the_language_mapper_seam_sets_the_claim_from_the_mined_header
    document = parse("CME301.xml",
                     language_mapper: ->(header) { header["language_usage"]&.start_with?("enm") && "enm" })
    assert_equal "enm", document.language
    assert(document.all? { |passage| passage.language == "enm" })
    assert_equal "enm", parse("CME301.xml", language_mapper: ->(_header) {}).language,
                 "a mapper declining (nil/false) falls back to the caller's language:"
  end

  # -- FW forme work (P83-1 — the EEBO-TCP family fix) -------------------------

  def test_fw_forme_work_drops_from_reading_text
    # <FW> is the page's furniture — running titles, catchwords, page
    # numbers ("added FW element, allowed it in a few page-crossing objects
    # (p q letter div etc.), and constrained it to following directly on
    # pb" — eebo2prf.xml.dtd changelog 2011-05; content model #PCDATA|…).
    # Inside a page-crossing <P> its PCDATA would leak mid-passage; it is
    # apparatus, never reading text. Censused vanishingly rare in the wild
    # (1 FW-bearing file in 5,782 EEBO-P4 files sampled 2026-08-26, 0 in
    # all 297 CME files) — but one leaked running title is still a corrupt
    # passage. DTD-shaped reproduction; the real-bytes FW file (A29180,
    # FW wrapping a FIGURE) is pinned in the eebo-tcp adapter suite.
    document = Nabu::Adapters::TcpXmlParser.new.parse(
      StringIO.new(<<~XML), urn: "urn:nabu:eebo-tcp:fw", language: "en", canonical_path: "fw.xml"
        <?xml version="1.0" encoding="utf-8"?>
        <ETS><HEADER><FILEDESC><TITLESTMT><TITLE>FW</TITLE></TITLESTMT></FILEDESC></HEADER>
        <EEBO><IDG S="marc" R="UM" ID="A00000"/><TEXT LANG="eng"><BODY><DIV1 TYPE="text">
        <P>the sentence begins <PB N="2" REF="2"/><FW PLACE="pageTop">The Running Title.</FW>and ends across the page.</P>
        </DIV1></BODY></TEXT></EEBO></ETS>
      XML
    )
    assert_equal 1, document.count
    assert_equal "the sentence begins and ends across the page.", document.first.text,
                 "the running title must not leak into the passage"
  end

  def test_idno_type_matching_is_case_insensitive
    # CME headers write <IDNO TYPE="dlps">, the EEBO-TCP generation writes
    # <IDNO TYPE="DLPS"> (censused: all 3,325 sampled EEBO files) — same
    # schema, case drift between generations.
    document = Nabu::Adapters::TcpXmlParser.new.parse(
      StringIO.new(<<~XML), urn: "urn:nabu:eebo-tcp:dlps", language: "en", canonical_path: "dlps.xml"
        <?xml version="1.0" encoding="utf-8"?>
        <ETS><HEADER><FILEDESC><TITLESTMT><TITLE>DLPS</TITLE></TITLESTMT></FILEDESC>
        <PUBLICATIONSTMT><IDNO TYPE="DLPS">A00000</IDNO></PUBLICATIONSTMT></HEADER>
        <EEBO><IDG S="marc" R="UM" ID="A00000"/><TEXT LANG="eng"><BODY><DIV1 TYPE="text">
        <P>text</P>
        </DIV1></BODY></TEXT></EEBO></ETS>
      XML
    )
    assert_equal "A00000", document.metadata["idno"]
  end

  # -- the NBSP placeholder (regression — offending bytes from CME00006) ------

  def test_an_nbsp_only_unit_consumes_no_ordinal_and_mints_no_passage
    # <P>&#xA0;</P> survives String#strip but collapses to nothing under
    # [[:space:]] — the two notions disagreeing minted an empty Passage
    # (ValidationError) on 4 real files (CME00006/46/47/48, censused
    # 2026-08-23). The blank gate uses the collapse's own notion.
    document = Nabu::Adapters::TcpXmlParser.new.parse(
      StringIO.new(<<~XML), urn: "urn:nabu:cme:nbsp", language: "enm", canonical_path: "nbsp.xml"
        <?xml version="1.0" encoding="utf-8"?>
        <ETS><HEADER><FILEDESC><TITLESTMT><TITLE>NBSP</TITLE></TITLESTMT></FILEDESC></HEADER>
        <EEBO><IDG S="marc" R="UM" ID="CME00006"/><TEXT><BODY><DIV1 TYPE="text">
        <P> </P>
        <P>real reading text</P>
        </DIV1></BODY></TEXT></EEBO></ETS>
      XML
    )
    assert_equal 1, document.count
    assert_equal "urn:nabu:cme:nbsp:d1.p1", document.first.urn,
                 "the NBSP placeholder consumes no ordinal"
    assert_equal "real reading text", document.first.text
  end

  # -- damage ------------------------------------------------------------------

  def test_malformed_xml_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::TcpXmlParser.new.parse(
        StringIO.new("<ETS><HEADER></ETS>"), urn: "urn:nabu:cme:bad",
                                             language: "enm", canonical_path: "bad.xml"
      )
    end
    assert_match(/bad\.xml/, error.message)
  end

  def test_a_document_without_any_text_element_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::TcpXmlParser.new.parse(
        StringIO.new("<ETS><HEADER><FILEDESC/></HEADER></ETS>"), urn: "urn:nabu:cme:empty",
                                                                 language: "enm", canonical_path: "empty.xml"
      )
    end
    assert_match(/no <TEXT>/, error.message)
  end

  # -- determinism -------------------------------------------------------------

  def test_two_parses_mint_identical_urns_and_text
    first = parse("CME00121.xml")
    second = parse("CME00121.xml")
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
  end
end
