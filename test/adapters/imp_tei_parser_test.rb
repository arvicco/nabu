# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# ImpTeiParser tests (P13-9): the imp-tei family — TEI P5 in the IMP schema
# (goo300k + IMP historical Slovene; NOT EpiDoc/CTS). One streaming pass per
# file; a passage block is any element with direct <s> children; the passage
# text is the HISTORICAL orig surface (canonical means canonical) rebuilt
# from <orig>/bare <w> + <c>/<pc> leaves; the <reg> modernization, gold
# lemma and MULTEXT-East MSD ride as tokens (:gold mode) or are dropped
# entirely (:none — the IMP silver decision, owner 2026-07-11).
class ImpTeiParserTest < Minitest::Test
  GOO_FIXTURES = Nabu::TestSupport.fixtures("goo300k")
  IMP_FIXTURES = Nabu::TestSupport.fixtures("imp")

  GOO_PAGE_1 = File.join(GOO_FIXTURES, "pages", "goo168-ZRC_00001-1584.pb.001_Biblia.xml")
  GOO_PAGE_2 = File.join(GOO_FIXTURES, "pages", "goo168-ZRC_00001-1584.pb.002_Biblia.xml")
  IMP_ZRC = File.join(IMP_FIXTURES, "ZRC_00001-1584-ana.xml")
  IMP_WIKI = File.join(IMP_FIXTURES, "WIKI00290-1855-ana.xml")

  def gold = Nabu::Adapters::ImpTeiParser.new(tokens: :gold)
  def plain = Nabu::Adapters::ImpTeiParser.new(tokens: :none)

  # --- header peek ------------------------------------------------------------

  def test_header_reads_source_bibl_not_the_titlestmt_wrapper
    header = gold.header(File.join(GOO_FIXTURES, "goo300k-1584-ZRC_00001.xml"))
    assert_equal "Biblia", header.title_orig
    assert_equal "Biblija (vzorec)", header.title_reg,
                 "the sourceDesc bibl title, not titleStmt's 'goo300k: \"Biblia\" (1584)' wrapper"
    assert_equal "Dalmatin, Jurij", header.author
    assert_equal "1584", header.date
    assert_equal "sl-bohoric", header.xml_lang
  end

  def test_header_reads_the_imp_shape_too
    header = gold.header(IMP_WIKI)
    assert_equal "Kaznovana tercialka", header.title_reg
    assert_equal "Jenko, Simon", header.author
    assert_equal "1855", header.date
    assert_equal "sl", header.xml_lang
  end

  # --- blocks: goo300k page files (gold mode) ---------------------------------

  def test_blocks_yields_one_block_per_ab_with_upstream_id_citations
    blocks = gold.blocks(GOO_PAGE_1).to_a
    assert_equal %w[ab.1 ab.2], blocks.map(&:citation),
                 "citation = the upstream ab xml:id tail, document-global numbering"
    assert_equal %w[pb.001 pb.001], blocks.map(&:page),
                 "the page-file root div type=pb ids every block on the page"
  end

  def test_block_text_is_the_historical_orig_surface
    blocks = gold.blocks(GOO_PAGE_1).to_a
    assert_equal "X. CAP.", blocks[0].text
    assert blocks[1].text.start_with?(
      "INu on je ſvoje dvanajſt Iogre k' ſebi poklizal, inu je nym oblaſt dal " \
      "zhes nezhiſte Duhuve, de bi teiſte"
    ), "orig spelling (long ſ, Bohorič) with pc punctuation attached, got: #{blocks[1].text[0, 120]}"
  end

  def test_gold_tokens_carry_form_reg_lemma_and_hash_stripped_msd
    head_tokens = gold.blocks(GOO_PAGE_1).first.tokens
    assert_equal(
      [{ "form" => "X.", "reg" => "x.", "lemma" => "x.", "msd" => "Mr" },
       { "form" => "CAP.", "reg" => "cap.", "lemma" => "cap.", "msd" => "Y" }],
      head_tokens
    )
  end

  def test_gold_tokens_of_bare_w_use_the_same_text_for_form_and_reg
    tokens = gold.blocks(GOO_PAGE_1).to_a[1].tokens
    on = tokens.find { |t| t["lemma"] == "on" && t["form"] == "on" }
    assert_equal({ "form" => "on", "reg" => "on", "lemma" => "on", "msd" => "P" }, on)
  end

  def test_gold_tokens_capture_the_archaic_vocabulary_gloss
    tokens = gold.blocks(GOO_PAGE_1).to_a[1].tokens
    jogre = tokens.find { |t| t["lemma"] == "joger" }
    assert_equal "Iogre", jogre["form"], "the orig surface attests the lemma"
    assert_equal "jogre", jogre["reg"]
    assert_equal "Ncm", jogre["msd"]
    assert_equal "apostol, učenec", jogre["gloss"]
    assert_equal "[sskj]", jogre["gloss_bibl"]
  end

  def test_a_part_f_block_is_its_own_block_never_merged
    blocks = gold.blocks(GOO_PAGE_2).to_a
    assert_equal ["ab.10"], blocks.map(&:citation),
                 "an ab continuing from the previous page (part=\"F\") keeps its own id"
    assert_equal "pb.002", blocks[0].page
  end

  # --- blocks: IMP self-contained files ----------------------------------------

  def test_imp_blocks_mint_per_tag_counters_where_upstream_has_no_ids
    blocks = plain.blocks(IMP_ZRC).to_a
    assert_equal %w[head.1 p.1 p.2], blocks.map(&:citation)
    assert_equal %w[pb.001 pb.001 pb.001], blocks.map(&:page),
                 "the <pb/> milestone ids the blocks that follow it"
  end

  def test_imp_full_text_parallels_the_goo300k_sample
    blocks = plain.blocks(IMP_ZRC).to_a
    assert_equal "X. CAP.", blocks[0].text
    assert blocks[1].text.start_with?("INu on je ſvoje dvanajſt Iogre"),
           "the same Dalmatin text goo300k samples, here full-page"
  end

  def test_none_mode_yields_no_tokens
    blocks = plain.blocks(IMP_ZRC).to_a
    assert(blocks.all? { |b| b.tokens.nil? },
           "the IMP silver decision: text only, no reg/lemma/msd carried")
  end

  def test_gold_mode_reads_imp_unprefixed_msds_verbatim
    tokens = gold.blocks(IMP_WIKI).first.tokens
    tercjalka = tokens.find { |t| t["lemma"] == "tercjalka" }
    assert_equal({ "form" => "tercjalka", "reg" => "tercjalka",
                   "lemma" => "tercjalka", "msd" => "Ncfsn" }, tercjalka)
  end

  def test_imp_front_matter_and_header_yield_no_blocks
    blocks = plain.blocks(IMP_WIKI).to_a
    assert_equal ["p.1"], blocks.map(&:citation),
                 "titlePage/divGen front matter and the teiHeader carry no <s> — no blocks"
    assert blocks[0].text.start_with?("Neka tercjalka je študente, ki so pri nji stanovali,")
    assert blocks[0].text.include?("v cerkev šla.")
  end

  # --- error discipline ---------------------------------------------------------

  def test_malformed_xml_raises_parse_error_naming_the_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken-1584-ana.xml")
      File.write(path, "<TEI><body><p><s><w>oops</s></p></TEI>")
      error = assert_raises(Nabu::ParseError) { gold.blocks(path).to_a }
      assert_includes error.message, path
    end
  end

  def test_unknown_tokens_mode_is_rejected
    assert_raises(ArgumentError) { Nabu::Adapters::ImpTeiParser.new(tokens: :silver) }
  end
end
