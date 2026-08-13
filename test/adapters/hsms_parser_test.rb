# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# HsmsParser (P77-1): the hsms family — the Hispanic Seminary of Medieval
# Studies transcription format (OSTA transcriptions/TEXT.xxx.txt): a
# {RMK:} header block, curly-brace structure groups ({HD.} headings,
# {CB1.}/{CB2.} column blocks closing with a bare-brace line tail),
# [fol. Nr] folio milestones, and semi-paleographic markup in the text
# (<abbreviation> expansions, [*x] reconstructions, (^x) scribal
# deletions, [??] lacunae). Passage grain = the HSMS numbered section
# ({RMK: HSMS-NNNN-NNNN:}); pre-section text (incl. {HD.} headings) is
# the honest `head` passage. Pristine text keeps the diplomatic markup
# VERBATIM; text_normalized is minted from the documented search_source
# derivation (conventions §9, the ccmh-txt precedent) — a pure function
# of the stored text, pinned by the adapter conformance hook.
#
# Format tests run off the two COMPLETE real fixtures (TEXT.RHJ.txt /
# TEXT.DAC.txt — see test/fixtures/osta/manifest.yml); damage and edge
# tests use minimal synthetic strings (structure simulation only, the
# ccmh damage-test posture — real files document the format).
class HsmsParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("osta")

  def parse(file, urn:)
    Nabu::Adapters::HsmsParser.new.parse(
      File.join(FIXTURES, "transcriptions", file),
      urn: urn, language: "osp", fallback_title: file
    )
  end

  def rhj
    parse("TEXT.RHJ.txt", urn: "urn:nabu:osta:rhj")
  end

  def dac
    parse("TEXT.DAC.txt", urn: "urn:nabu:osta:dac")
  end

  # --- the header block → document metadata ---------------------------------

  def test_header_rmks_ride_metadata_verbatim_with_shape_extraction
    document = rhj
    assert_equal "Glosa al romance \"Rey que no hace justicia\"", document.title
    metadata = document.metadata
    assert_equal "HSMS-0198", metadata["hsms_id"]
    assert_equal "desconocido", metadata["author"]
    assert_equal "RHJ", metadata["siglum"], "the in-file [RHJ] siglum rides verbatim (filename mints)"
    assert_equal "Madrid | Real Biblioteca | II/1520 (2)", metadata["repository"]
    assert_equal "Charles B. Faulhaber", metadata["editor"]
    assert_equal ["HSMS-0198.", "desconocido.",
                  "[RHJ] Glosa al romance \"Rey que no hace justicia\".", ".",
                  "Madrid | Real Biblioteca | II/1520 (2).", "Charles B. Faulhaber."],
                 metadata["header"], "every header RMK content verbatim — the honesty backstop " \
                                     "(the empty '.' slot included: positions are upstream facts)"
  end

  def test_dac_header_varies_and_still_extracts
    metadata = dac.metadata
    assert_equal "HSMS-0345", metadata["hsms_id"]
    assert_equal "Disputa del alma y el cuerpo", metadata["title"]
    assert_equal "Francisco Gago Jover", metadata["editor"]
    assert_equal "Madrid | Archivo Histórico Nacional de España | Clero: carp. 279, n. 22",
                 metadata["repository"]
  end

  # --- passage grain: head + numbered sections ------------------------------

  def test_rhj_parses_to_a_head_passage_plus_one_numbered_section
    document = rhj
    assert_equal 2, document.size
    head, section = document.to_a
    assert_equal "urn:nabu:osta:rhj:head", head.urn
    assert_equal "head", head.annotations["kind"]
    assert_equal "glosa al Roma<n>çe / Rey q<ue> no<n> haσe justiçia", head.text,
                 "the {HD.} heading is pre-section scribal text — searchable, never dropped"
    assert_equal ["93r"], head.annotations["folios"]

    assert_equal "urn:nabu:osta:rhj:1", section.urn
    assert_equal "HSMS-0198-0001", section.annotations["hsms"],
                 "the upstream citable id rides verbatim"
    assert_equal "Glosa al romance \"Rey que no hace justicia\"", section.annotations["title"]
    assert_equal ["93r"], section.annotations["folios"]
    assert_equal %w[CB2 CB2], section.annotations["columns"],
                 "the section spans both column blocks — column tags verbatim, never interpreted"
  end

  def test_section_text_is_diplomatic_lines_verbatim
    section = rhj.to_a.last
    lines = section.text.lines(chomp: true)
    assert_equal 48, lines.size, "28 lines in the first column block + 20 in the second"
    assert_equal "¶ el q<ue> peca de avariçia", lines.first,
                 "same-line text after the section marker belongs to the section; markup verbatim"
    assert_equal "començara de pe<n>sare", lines[27],
                 "the column block's closing brace is structure, stripped from the text"
    assert_equal "quiça algun bje<n> me farave", lines.last
    assert_includes section.text, "q<ue>brantarame las pue<r>tas"
    assert_includes section.text, "(^p)(^??) llaga", "scribal deletions stay in the pristine text"
  end

  def test_dac_parses_to_one_section_with_no_head
    document = dac
    assert_equal 1, document.size
    section = document.first
    assert_equal "urn:nabu:osta:dac:1", section.urn
    assert_equal "Disputa del alma y el cuerpo", section.annotations["title"]
    assert_equal ["1r"], section.annotations["folios"]
    assert_equal %w[CB1], section.annotations["columns"]
    lines = section.text.lines(chomp: true)
    assert_equal 18, lines.size
    assert section.text.start_with?("[*s]i q<ue>reedes oyr"),
           "no space after the marker brace — the section text starts immediately"
    assert section.text.end_with?("e tanbien re[??]")
  end

  def test_urns_are_stable_across_two_parses
    assert_equal rhj.map(&:urn), rhj.map(&:urn)
  end

  # --- the documented search-form derivation (conventions §9) ---------------

  def search_source(text)
    Nabu::Adapters::HsmsParser.search_source(text)
  end

  def test_search_source_resolves_abbreviation_expansions
    assert_equal "quebrantarame las puertas", search_source("q<ue>brantarame las pue<r>tas")
    assert_equal "dentro de mj palomare", search_source("dent<r><<o>> de mj palomare")
  end

  def test_search_source_resolves_editorial_brackets
    assert_equal "esient domingo amanezient", search_source("[*e]sient dom[i]ngo amanezient")
    assert_equal "pues que veo cada dia", search_source("pues q<ue> veo cada[ ]dia")
    assert_equal "puso el rrey barua en onbro",
                 search_source("puso el rrey barua en onb(^s)[^<r>o]"),
                 "nested: deletion dropped, interlinear addition resolved through its expansion"
  end

  def test_search_source_drops_deletions_lacunae_and_pilcrows
    assert_equal "con vn semblante desre", search_source("co<n> vn semblant<e> (^y) des[??]re")
    assert_equal "el que peca de avariçia", search_source("¶ el q<ue> peca de avariçia")
    assert_equal "e todos tos trebeios", search_source("e todos tos(dos) treb[e]ios")
  end

  def test_search_source_falls_back_to_the_raw_text_rather_than_empty
    assert_equal "(^x)", search_source("(^x)"),
                 "a passage that derives to nothing keeps its raw text — text_normalized " \
                 "must never be empty (the ccmh-txt fallback rule)"
  end

  def test_passages_mint_text_normalized_from_the_derivation
    section = rhj.to_a.last
    expected = Nabu::Normalize.search_form(search_source(section.text), language: "osp")
    assert_equal expected, section.text_normalized
    assert_includes section.text_normalized, "quebrantarame"
  end

  # --- structure damage and edges (synthetic, minimal) ----------------------

  def parse_string(content, urn: "urn:nabu:osta:tst")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "TEXT.TST.txt")
      File.write(path, content)
      return Nabu::Adapters::HsmsParser.new.parse(path, urn: urn, language: "osp",
                                                        fallback_title: "TST")
    end
  end

  def test_duplicate_section_numbers_take_the_house_b2_suffix
    document = parse_string(<<~TXT)
      {RMK: HSMS-9.}
      {CB1.
      {RMK: HSMS-9-1: A.} first words
      {RMK: HSMS-9-1: B.} second words
      }
    TXT
    assert_equal ["urn:nabu:osta:tst:1", "urn:nabu:osta:tst:1:b2"], document.map(&:urn)
  end

  def test_unknown_brace_tags_are_censused_loud_and_their_text_flows
    document = parse_string(<<~TXT)
      {RMK: HSMS-9.}
      {XX. some rubric text}
      {CB1.
      {RMK: HSMS-9-1: T.} words here
      }
    TXT
    assert_equal({ "XX" => 1 }, document.metadata["unrecognized_tags"],
                 "an unknown structural tag is censused, never a crash (the aozora posture)")
    assert_equal "some rubric text", document.first.text,
                 "the unknown group's inner text still flows — no silent drops"
  end

  # SPEC OVERTURNED at the first real sync (P77-r7): the two-fixture
  # census read balanced braces as the convention, but the live 663
  # files mix sibling-style and batched column closes — counts
  # genuinely unbalance in ~2% of the corpus. A stray brace is now a
  # CENSUSED defect ("brace_defects"), never a quarantine: the text
  # must never pay for a transcriber's brace.
  def test_an_unmatched_close_brace_is_a_censused_defect_not_an_error
    document = parse_string("{RMK: HSMS-9.}\n{RMK: HSMS-9-1: T.} text line\n}\n}\n")
    assert_equal ["line 3: unmatched close brace ignored",
                  "line 4: unmatched close brace ignored"],
                 document.metadata["brace_defects"]
    assert_includes document.first.text, "text line", "the text flows regardless"
  end

  def test_an_unclosed_container_at_eof_is_a_censused_defect_not_an_error
    document = parse_string("{RMK: HSMS-9.}\n{CB1.\n{RMK: HSMS-9-1: T.} words\n")
    assert_equal ["end of file: unclosed {CB1. implicitly closed"],
                 document.metadata["brace_defects"]
    assert_includes document.first.text, "words"
  end

  def test_a_file_with_no_text_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      parse_string("{RMK: HSMS-9.}\n{RMK: alguien.}\n")
    end
    assert_match(/no passages/, error.message)
  end
end
