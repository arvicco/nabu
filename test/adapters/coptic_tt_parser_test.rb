# frozen_string_literal: true

require "test_helper"

# CopticTtParser (P17-1): the coptic-tt family — Coptic Scriptorium's
# TreeTagger-SGML span stacks. Exercised against the real fixture files,
# which between them carry all three structural dialects the corpus ships
# (see test/fixtures/coptic-scriptorium/README.md):
#   - modern expanded (besa: translation elements, vid_n, orig_group/orig
#     spans, the morph-split-across-lb quirk)
#   - older expanded (Mark_01 in the zip: translation element OPENS BEFORE
#     verse_n — spans overlap, the format is not a tree)
#   - collapsed (Philemon: orig_group/orig/lang as ATTRIBUTES, translation
#     as a verse_n attribute)
# plus the documentary fallback (cpr.2.237: no verse_n at all → ordinal
# translation units, non-canonical addressing).
class CopticTtParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("coptic-scriptorium")

  BESA = File.join(FIXTURES, "besa-letters", "besa.letters_TT", "on_lack_of_food.tt")
  AP = File.join(FIXTURES, "AP", "apophthegmata.patrum_TT", "AP.004.poemen.65.tt")
  CPR = File.join(FIXTURES, "doc-papyri", "doc.papyri_TT", "cpr.2.237.tt")

  def parse(path, lemmas: :gold)
    Nabu::Adapters::CopticTtParser.new(lemmas: lemmas).parse(File.read(path), label: path)
  end

  # --- meta header --------------------------------------------------------

  def test_meta_decodes_the_header_attributes_including_html_entities
    meta = parse(BESA).meta
    assert_equal "besa.letters", meta["corpus"]
    assert_equal "urn:cts:copticLit:besa.food.monbbb", meta["document_cts_urn"]
    assert_equal "Sahidic Coptic", meta["language"]
    # HTML entities in the license anchor decode (&lt;a href…&gt; → <a href…>)
    assert_includes meta["license"], "<a href='https://creativecommons.org/licenses/by/4.0/'>"
    assert_equal "0500", meta["origDate_notBefore"]
    assert_equal "medium", meta["origDate_precision"]
    assert_equal "108395", meta["Trismegistos"]
  end

  # --- verse units (modern expanded dialect) -------------------------------

  def test_besa_parses_two_verse_units_with_vid_citations
    result = parse(BESA)
    assert_equal 2, result.units.size
    assert_equal %w[1.1 1.2], result.units.map(&:citation)
    assert_equal "1", result.units.first.annotations["verse"]
    assert_equal "urn:cts:copticLit:besa.food.monbbb:1.1", result.units.first.annotations["vid"]
  end

  def test_besa_unit_text_is_the_diplomatic_orig_group_sequence
    unit = parse(BESA).units.first
    assert unit.text.start_with?("ⲉⲧⲉⲧ︤ⲛ︥ϣ︤ⲡ︥ϩⲓⲥⲉ ⲙ︤ⲛ︥ⲛⲉⲧⲙⲏⲣ⳿ ⲉⲧⲉⲛⲉⲧⲙⲟⲕ︤ϩ︥"),
           "diplomatic text must keep supralinear strokes and ⳿: #{unit.text[0, 40].inspect}"
  end

  def test_besa_tokens_carry_the_word_grain_with_gold_lemma_and_pos
    tokens = parse(BESA).units.first.annotations["tokens"]
    assert_equal 53, tokens.size
    first = tokens.first
    assert_equal "u1", first["id"]
    assert_equal "ⲉ", first["form"]
    assert_equal "ⲉⲣⲉ", first["lemma"] # tagging="gold" → lemma minted under the index key
    assert_equal "CFOC", first["pos"]
    assert_equal "mark", first["func"]
    assert_equal "#u3", first["head"]
    assert_equal true, first["new_sent"]
    assert_equal 0, first["group"]
  end

  def test_besa_preserves_the_morph_split_across_line_break_quirk
    tokens = parse(BESA).units.first.annotations["tokens"]
    token = tokens.find { |t| t["id"] == "u3" }
    assert_equal "ϣⲡϩⲓⲥⲉ", token["form"]
    assert_equal %w[ϣⲡ ϩⲓⲥⲉ], token["morphs"]
    assert_equal "1", token["line"]
    assert_equal "2", token["line_split"], "the lb_n 1→2 break INSIDE the token must be preserved"
    assert_equal "ϣ︤ⲡ︥ϩⲓⲥⲉ", token["orig"]
  end

  def test_besa_language_of_origin_tags_ride_per_token_and_as_loan_counts
    units = parse(BESA).units
    assert_equal({ "grc" => 1 }, units[0].annotations["loans"])
    assert_equal({ "grc" => 3 }, units[1].annotations["loans"])
    tagged = units[0].annotations["tokens"].select { |t| t["lang"] }
    assert_equal ["Greek"], tagged.map { |t| t["lang"] }.uniq # upstream value, verbatim
  end

  def test_besa_verse_translations_join_in_order
    unit = parse(BESA).units.first
    assert unit.annotations["translation"].start_with?("It is by those who are bound and suffering")
  end

  def test_besa_entities_attach_to_their_unit
    units = parse(BESA).units
    assert_equal 7, units[0].annotations["entities"].size
    assert_equal 8, units[1].annotations["entities"].size
    entity = units[0].annotations["entities"].first
    assert_equal "person", entity["type"]
    assert_equal "#u5", entity["head"]
  end

  def test_besa_records_page_and_column_topology
    unit = parse(BESA).units.first
    assert_equal "BB553", unit.annotations["page"]
    assert_equal "1", unit.annotations["column"]
  end

  # --- lemma quality gating -------------------------------------------------

  def test_automatic_docs_mint_lemma_auto_not_lemma_by_default
    zip = File.join(FIXTURES, "sahidica.nt", "sahidica.nt_TT.zip")
    content = Nabu::Shell.run("unzip", "-p", zip, "57_Philemon_01.tt")
    result = Nabu::Adapters::CopticTtParser.new(lemmas: :gold).parse(content, label: "57_Philemon_01.tt")
    token = result.units.first.annotations["tokens"].first
    assert_nil token["lemma"], "tagging=automatic must not feed the gold lemma index by default"
    assert_equal "ⲡⲁⲩⲗⲟⲥ", token["lemma_auto"]
    # The gate knob: lemmas: :all flips automatic lemmas into the index key.
    all = Nabu::Adapters::CopticTtParser.new(lemmas: :all).parse(content, label: "57_Philemon_01.tt")
    assert_equal "ⲡⲁⲩⲗⲟⲥ", all.units.first.annotations["tokens"].first["lemma"]
  end

  # --- collapsed dialect (Philemon) ----------------------------------------

  def test_collapsed_dialect_reads_orig_group_orig_and_lang_from_attributes
    zip = File.join(FIXTURES, "sahidica.nt", "sahidica.nt_TT.zip")
    content = Nabu::Shell.run("unzip", "-p", zip, "57_Philemon_01.tt")
    result = Nabu::Adapters::CopticTtParser.new.parse(content, label: "57_Philemon_01.tt")
    assert_equal 25, result.units.size
    unit = result.units.first
    assert unit.text.start_with?("ⲡⲁⲩⲗⲟⲥ ⲡⲉⲧⲙⲏⲣ ⲛⲧⲉⲡⲉⲭⲣⲓⲥⲧⲟⲥ")
    token = unit.annotations["tokens"].first
    assert_equal "ⲡⲁⲩⲗⲟⲥ", token["orig"]
    assert_equal "Greek", token["lang"]
    # translation rides as a verse_n ATTRIBUTE in this dialect
    assert unit.annotations["translation"].start_with?("Paul, a prisoner of Christ Jesus")
  end

  # --- older expanded dialect (Mark) + AP extras -----------------------------

  def test_mark_translation_element_opening_before_verse_attaches_forward
    zip = File.join(FIXTURES, "sahidica.nt", "sahidica.nt_TT.zip")
    content = Nabu::Shell.run("unzip", "-p", zip, "41_Mark_01.tt")
    result = Nabu::Adapters::CopticTtParser.new.parse(content, label: "41_Mark_01.tt")
    assert_equal 12, result.units.size
    assert_equal "The beginning of the Good News of Jesus Christ, the Son of God.",
                 result.units.first.annotations["translation"]
    assert result.units[1].annotations["translation"].start_with?("As it is written in the prophets")
  end

  def test_ap_carries_wikification_identities_and_embedded_arabic
    result = parse(AP)
    assert_equal 3, result.units.size
    identities = result.units.flat_map { |u| u.annotations["entities"] || [] }.filter_map { |e| e["identity"] }
    assert_includes identities, "Poemen"
    assert result.units.first.annotations["translation_ar"].start_with?("فال الأنبا بيمن")
  end

  # --- documentary fallback (no verse_n) -------------------------------------

  def test_cpr_falls_back_to_ordinal_translation_units_flagged_non_canonical
    result = parse(CPR)
    assert_equal 9, result.units.size
    assert_equal (1..9).map(&:to_s), result.units.map(&:citation)
    assert(result.units.all? { |u| u.annotations["addressing"] == "translation-ordinal" })
    assert_equal(84, result.units.sum { |u| u.annotations["tokens"].size })
    # documentary span dialect: pb recto/verso + source_lang
    assert_equal "r", result.units.first.annotations["page"]
    assert_equal({ "hbo" => 1 }, result.units[2].annotations["loans"])
  end

  # --- search source (the conventions §9 derivation) --------------------------

  def test_search_source_is_the_norm_word_sequence_recomputable_from_the_row
    unit = parse(BESA).units.first
    source = Nabu::Adapters::CopticTtParser.search_source(unit.text, unit.annotations)
    assert source.start_with?("ⲉ ⲧⲉⲧⲛ ϣⲡϩⲓⲥⲉ ⲙⲛ ⲛ ⲉⲧ ⲙⲏⲣ"),
           "search source must be the upstream norm layer at word grain: #{source[0, 40].inspect}"
    # falls back to the pristine text when a row carries no tokens
    assert_equal "ⲁⲃⲅ", Nabu::Adapters::CopticTtParser.search_source("ⲁⲃⲅ", {})
  end

  # --- guards -----------------------------------------------------------------

  def test_unknown_span_types_fail_loudly
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CopticTtParser.new.parse(
        "<meta corpus=\"x\" license=\"CC-BY 4.0\" document_cts_urn=\"urn:cts:copticLit:x\">\n" \
        "<mystery_span mystery_span=\"y\">\n</mystery_span>\n</meta>\n", label: "synthetic"
      )
    end
    assert_match(/mystery_span/, error.message)
  end

  def test_a_file_without_a_meta_header_fails_loudly
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CopticTtParser.new.parse("<verse_n verse_n=\"1\">\n</verse_n>\n", label: "synthetic")
    end
  end
end
