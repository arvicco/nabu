# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# HsmsVrtParser (P77-2): the hsms family's verticalized lane — OSTA's
# lemmatized/tagged token streams (verticalized/TEXT.xxx.vrt.html):
# <w data1='token•lemma•EAGLES-POS'>diplomatic</w> under the same HSMS
# structure as the transcriptions (<RMK> header/section groups, <FOL>/
# <folio>, <CB2> columns, <LN id> manuscript lines). Passage grain =
# the HSMS numbered section; passage text = the DIPLOMATIC surfaces in
# line layout (in-token wrap hyphens and all); the clean token/lemma/
# pos triples ride the "tokens" annotation — the Indexer's lemma
# contract — and text_normalized derives from the clean token stream
# (the ccmh-txt annotation-derivation precedent). RMK/PUNCT pseudo-tags
# never mint lemma keys. Lemma tier: SILVER, ruled on upstream evidence
# (Gago Jover & Pueyo Mena, Scriptum Digital 7: FreeLing + HSMS-app —
# automatic lemmatization; the GLAUx precedent).
class HsmsVrtParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("osta")

  def ac2
    @ac2 ||= Nabu::Adapters::HsmsVrtParser.new.parse(
      File.join(FIXTURES, "verticalized", "TEXT.AC2.vrt.html"),
      urn: "urn:nabu:osta:ac2-vrt", language: "osp", siglum: "AC2"
    )
  end

  # --- header metadata ------------------------------------------------------

  def test_header_rmk_groups_ride_metadata_with_shape_extraction
    metadata = ac2.metadata
    assert_equal "HSMS-0317", metadata["hsms_id"]
    assert_equal "AC2", metadata["siglum"]
    assert_equal "Leyes del estilo", metadata["title"]
    assert_equal "Leyes del estilo", ac2.title
    assert_equal ["HSMS-0317.", "desconocido.", "AC2 Leyes del estilo.", ".",
                  "San Lorenzo de El Escorial | Real Biblioteca del Monasterio " \
                  "de San Lorenzo de El Escorial | Z-II-14.",
                  "Terrence A. Mannetter."],
                 metadata["header"], "header RMK groups flatten to the slot list verbatim"
  end

  # --- passage grain and text -----------------------------------------------

  def test_ac2_parses_to_one_numbered_section_of_diplomatic_lines
    document = ac2
    assert_equal 1, document.size
    section = document.first
    assert_equal "urn:nabu:osta:ac2-vrt:2", section.urn,
                 "the fixture head opens at section HSMS-0317-0002 — the ordinal mints"
    assert_equal "HSMS-0317-0002", section.annotations["hsms"]
    assert_equal "Leyes del estilo", section.annotations["title"]
    assert_equal ["429r"], section.annotations["folios"]
    assert_equal %w[CB2], section.annotations["columns"]
    lines = section.text.lines(chomp: true)
    assert_equal 17, lines.size, "one text line per <LN> with tokens (LN 18 is empty at the trim)"
    assert_equal "Aquj comiença el libro del declaramjento que", lines.first,
                 "diplomatic surfaces flatten their <ABB>/<SUP> children seamlessly"
    assert lines.last.end_with?("contestado que quiere de-zir")
    assert_includes section.text, "per-done", "in-token wrap hyphens stay in the pristine text"
    assert_includes section.text, "co-sas"
  end

  # --- the tokens annotation (the Indexer's lemma contract) -----------------

  def test_tokens_carry_clean_form_lemma_and_eagles_pos
    tokens = ac2.first.annotations["tokens"]
    assert_equal({ "form" => "Aquj", "lemma" => "aquí", "pos" => "RG" }, tokens.first)
    assert_includes tokens, { "form" => "perdone", "lemma" => "perdonar", "pos" => "VMSP3S0" },
                    "the clean token field heals the wrap hyphen the surface keeps"
    assert_includes tokens, { "form" => "del", "lemma" => "de·el", "pos" => "SPS00·DA0MS0" },
                    "contraction composites ride verbatim — the ReN chained-lemma precedent"
  end

  def test_pseudo_tags_never_mint_lemma_keys
    tokens = ac2.first.annotations["tokens"]
    assert(tokens.none? { |token| %w[RMK PUNCT].include?(token["lemma"]) },
           "RMK/PUNCT are structural pseudo-tags, not citation forms")
    assert(tokens.all? { |token| token.key?("form") })
  end

  # --- the search-form derivation -------------------------------------------

  def test_search_source_is_the_clean_token_stream
    section = ac2.first
    source = Nabu::Adapters::HsmsVrtParser.search_source(section.text, section.annotations)
    assert_includes source, "perdone"
    refute_includes source, "per-done"
    expected = Nabu::Normalize.search_form(source, language: "osp")
    assert_equal expected, section.text_normalized
  end

  def test_search_source_falls_back_to_text_without_tokens
    assert_equal "raw", Nabu::Adapters::HsmsVrtParser.search_source("raw", {})
  end

  # --- damage ----------------------------------------------------------------

  def test_a_token_with_a_malformed_data1_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "TEXT.TST.vrt.html")
      File.write(path, <<~HTML)
        <BODY><DIV class="paleo">
        <RMK><w data1='HSMS-9•RMK•RMK'>HSMS-9.</w></RMK>
        <LN id='1'></LN>
        <w data1='broken•only-two-fields'>broken</w>
        </DIV></BODY>
      HTML
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::HsmsVrtParser.new.parse(path, urn: "urn:nabu:osta:tst-vrt",
                                                      language: "osp", siglum: "TST")
      end
      assert_match(/data1/, error.message)
    end
  end
end
