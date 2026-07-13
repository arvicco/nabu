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

  # P18-1 offender fixtures (trimmed real files, see the fixtures README)
  HELIAS = File.join(FIXTURES, "helias", "helias_TT", "helias_martyrdom_part1.tt")
  THEODOSIUS = File.join(FIXTURES, "theodosius-alexandria", "theodosius.alexandria_TT",
                         "Encomium_Michael_BL_OR_6781_part1.tt")
  PISTIS = File.join(FIXTURES, "pistis-sophia", "pistis.sophia_TT", "pistis.sophia_book_1_part1.tt")
  ABRAHAM = File.join(FIXTURES, "abraham", "shenoute.abraham_TT", "YA535-540.tt")
  APHOU = File.join(FIXTURES, "life-aphou", "life.aphou_TT", "life.aphou.01.tt")
  COR14 = File.join(FIXTURES, "sahidica.1corinthians", "sahidica.1corinthians_TT", "1Cor_14.tt")
  AP100 = File.join(FIXTURES, "AP", "apophthegmata.patrum_TT", "AP.100.n294.crocodiles.tt")
  JONAH = File.join(FIXTURES, "sahidic.jonah", "sahidic.jonah_TT", "Jonah_01.tt")
  VIGILANCE = File.join(FIXTURES, "besa-letters", "besa.letters_TT", "on_vigilance.tt")
  OCRUM = File.join(FIXTURES, "magical-papyri", "magical.papyri_TT", "OCrum_ST_18.tt")

  def parse(path, lemmas: :gold)
    Nabu::Adapters::CopticTtParser.new(lemmas: lemmas).parse(File.read(path), label: path)
  end

  def parse_member(zip_dir, zip_name, member)
    content = Nabu::Shell.run("unzip", "-p", File.join(FIXTURES, zip_dir, zip_name), member)
    Nabu::Adapters::CopticTtParser.new.parse(content, label: member)
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

  def test_note_spans_ride_as_unit_notes_the_p18_upgrade
    # P17-1 dropped <note> as render-only; the P18-1 census (327 note_note +
    # the element form) argued editorial notes into annotations["notes"].
    notes = parse(AP).units.flat_map { |u| u.annotations["notes"] || [] }
    refute_empty notes
    assert(notes.any? { |n| n.include?("damage") })
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

  # --- P18-1: the meta-line whitespace variant ------------------------------
  #
  # 18 files in the release (helias/theodosius parts, acts-pilate,
  # lament-mary) write one attribute as `msItem_title ="…"` — a space before
  # the `=`. The strict attribute regex saw no meta header at all and the
  # files were "unrecognized". The widened regex tolerates whitespace around
  # `=`; everything else about the line is the ordinary meta dialect.

  def test_meta_header_with_whitespace_before_equals_decodes
    meta = parse(HELIAS).meta
    assert_equal "urn:cts:copticLit:helias.martyrdom.sobhy_ed:0-15", meta["document_cts_urn"]
    assert_equal "Martyrdom of Helias", meta["msItem_title"]
    assert_equal "Martyrdom of Helias (Sobhy ed.) Part 1", meta["title"]
  end

  # --- P18-1: edition topology (ed_page_n/ed_pg_n/ed_page, ed_line_n/ed_lb_n) --

  def test_helias_carries_edition_page_and_line_topology
    result = parse(HELIAS)
    assert_equal 8, result.units.size
    unit = result.units.first
    assert_equal "0001", unit.annotations["ed_page"]
    lines = unit.annotations["tokens"].filter_map { |t| t["ed_line"] }
    assert_includes lines, "1"
    assert_includes lines, "2"
  end

  def test_helias_token_straddling_a_chapter_boundary_belongs_where_it_opened
    # Token u200 (ϩⲁⲙⲏⲛⲁⲥϣⲱⲡⲉⲇⲉ) opens in chapter 3's verse and is still
    # open when the verse AND chapter close — the lb_n split quirk at verse
    # grain (same shape closes Luke 13:20 mid-word). Span-stack semantics:
    # the token belongs to the unit it opened in, never the next one.
    units = parse(HELIAS).units
    owner = units.find { |u| u.annotations["tokens"].any? { |t| t["id"] == "u200" } }
    refute_nil owner, "the straddling token must not vanish"
    refute_equal units.last, owner, "u200 opens before the chapter boundary, not in the final unit"
    following = units[units.index(owner) + 1]
    assert following.citation.start_with?("4."), "the next unit is chapter 4's first verse"
    assert(following.annotations["tokens"].none? { |t| t["id"] == "u200" },
           "a straddling token must not be doubled into the next unit")
  end

  def test_theodosius_ordinal_units_carry_the_ed_pg_n_spelling
    result = parse(THEODOSIUS)
    assert_equal 5, result.units.size # 5 translation units in the trim
    assert(result.units.all? { |u| u.annotations["addressing"] == "translation-ordinal" })
    assert_equal "330", result.units.first.annotations["ed_page"]
  end

  # --- P18-1: alternate citation schemes + extra aligned layers (pistis) ------

  def test_pistis_carries_marcion_and_petermann_citations_and_horner_translation
    result = parse(PISTIS)
    assert_equal 3, result.units.size
    unit = result.units.first
    assert_equal ["1.1"], unit.annotations["cit_petermann"]
    assert_includes unit.annotations["cit_marcion"], "1.1"
    assert unit.annotations["translation_horner"].start_with?("But it happened after that Jesus rose")
    assert_equal "ⲁ̅.ⲁ.", unit.annotations["page_coptic"]
  end

  def test_besa_german_translation_layer_folds_into_an_aligned_span
    unit = parse(VIGILANCE).units.first
    assert unit.annotations["translation_de"].start_with?("[Warum] unterwerft")
  end

  # --- P18-1: token-level Wikification + vid variants --------------------------

  def test_abraham_entity_identity_spans_mint_token_level_identities
    result = parse(ABRAHAM)
    assert_equal 6, result.units.size
    assert_equal "urn:cts:copticLit:shenoute.abraham.monbya:21.8", result.units.first.annotations["vid"]
    identities = result.units.flat_map { |u| u.annotations["entities"] || [] }.select { |e| e["identity"] }
    jesus = identities.find { |e| e["identity"] == "Jesus" }
    refute_nil jesus
    assert_match(/\A#u\d+\z/, jesus["head"])
    refute_nil jesus["text"]
  end

  def test_jonah_folds_fused_vid_and_carries_the_readable_verse_name
    result = parse(JONAH)
    assert_equal 2, result.units.size
    assert_equal "urn:cts:copticLit:ot.jonah.coptot_ed:1.1", result.units[0].annotations["vid"]
    assert_equal "Jonah 1:1", result.units[0].annotations["verse_name"]
    assert_equal "Jonah 1:2", result.units[1].annotations["verse_name"]
    assert_includes result.units[1].annotations["notes"], "haplography"
    marks = result.units[1].annotations["editorial"]
    assert(marks.any? { |m| m["mark"] == "supplied" && m["reason"] == "omitted" })
  end

  # --- P18-1: PATHS entity subtypes and quotation references -------------------

  def test_aphou_paths_subtype_spans_enrich_their_enclosing_entities
    entities = parse(APHOU).units.flat_map { |u| u.annotations["entities"] || [] }
    assert(entities.any? { |e| e["type"] == "person" && e["subtype"] == "monk" })
    assert(entities.any? { |e| e["type"] == "place" && e["ref"] == "paths:places:32" })
    quote = entities.find { |e| e["type"] == "quote" }
    refute_nil quote
    assert_equal "Sal.72 , 22.23", quote["ref"]
    assert_equal "biblical", quote["subtype"]
  end

  # --- P18-1: verse spans as the unit opener (no verse_n in the file) ----------

  def test_1cor_verse_spans_open_units_and_citations_normalize_the_fused_label
    result = parse(COR14)
    assert_equal 3, result.units.size
    assert_equal %w[14.1 14.2 14.3], result.units.map(&:citation)
    # the verbatim upstream label rides in annotations, unnormalized
    assert_equal "1 Corinthians 14:1", result.units.first.annotations["verse"]
  end

  # --- P18-1: editorial marks (gap*/supplied*/abbr) -----------------------------

  def test_ap100_gap_and_supplied_marks_ride_as_editorial_records
    marks = parse(AP100).units.flat_map { |u| u.annotations["editorial"] || [] }
    assert(marks.any? { |m| m["mark"] == "supplied" && m["reason"] == "illegible" })
    assert_includes marks, { "mark" => "gap", "quantity" => "2", "unit" => "character", "reason" => "illegible" }
  end

  def test_genesis_zip_member_carries_abbr_gap_and_supplied_marks
    result = parse_member("sahidic.ot", "sahidic.ot_TT.zip", "01_Genesis_01.tt")
    marks = result.units.flat_map { |u| u.annotations["editorial"] || [] }
    assert_includes marks, { "mark" => "abbr", "type" => "nomSac" }
    assert_includes marks, { "mark" => "gap", "reason" => "lacuna" }
    assert_includes marks, { "mark" => "supplied", "source" => "transcriber", "reason" => "lacuna" }
  end

  # --- P18-1: the omitted-verse lacuna shape ------------------------------------
  #
  # Eight NT zip books and the OCrum magical papyrus open a bound group
  # BEFORE the verse_n it contains — the classic omitted verses (Mark 7:16,
  # John 5:4, Acts 8:37, Rom 16:24…) carried as `[..]`/`[--]`/`[...]`
  # placeholders whose verse span nests INSIDE the group/token. The group
  # and token attach FORWARD to the verse that opens inside them; a group
  # or token that closes with no unit having opened stays a loud error.

  def test_mark7_omitted_verse_16_attaches_its_lacuna_group_forward
    result = parse_member("sahidica.nt", "sahidica.nt_TT.zip", "41_Mark_07.tt")
    assert_equal 16, result.units.size
    unit = result.units.last
    assert_equal "16", unit.annotations["verse"]
    assert_equal "[..]", unit.text
    assert_equal "If anyone has ears to hear, let him hear!'", unit.annotations["translation"]
    assert_equal(["u433"], unit.annotations["tokens"].map { |t| t["id"] })
  end

  def test_acts24_lacuna_group_crossing_a_verse_boundary_attaches_to_the_first_verse
    result = parse_member("bohairic.nt", "bohairic.nt_TT.zip", "05_Acts_24.tt")
    assert_equal 8, result.units.size
    seven, eight = result.units.last(2)
    assert_equal "[...]ⲫⲁⲓ", seven.text
    assert_equal(["u181"], seven.annotations["tokens"].map { |t| t["id"] })
    # the boundary-crossing group attaches whole to the verse it opened
    # into; verse 8 keeps its own tokens (u182's verse attribution is exact)
    assert_equal "u182", eight.annotations["tokens"].first["id"]
    assert eight.text.start_with?("ⲉⲧⲉⲟⲩⲟⲛ")
  end

  def test_ocrum_final_amen_verse_nests_inside_its_bound_group
    result = parse(OCRUM)
    assert_equal 7, result.units.size
    unit = result.units.last
    assert_equal "1.7", unit.citation
    assert_equal "ϥⲑ", unit.text
    assert_equal "Amen!", unit.annotations["translation"]
    assert_equal({ "hbo" => 1 }, unit.annotations["loans"])
  end

  def test_a_stray_group_that_closes_without_a_unit_still_fails_loudly
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CopticTtParser.new.parse(
        "<meta corpus=\"x\" license=\"CC-BY 4.0\" document_cts_urn=\"urn:cts:copticLit:x\">\n" \
        "<norm_group norm_group=\"ⲁ\">\n</norm_group>\n" \
        "<verse_n verse_n=\"1\">\n</verse_n>\n</meta>\n", label: "synthetic"
      )
    end
    assert_match(/unsegmented stretch/, error.message)
  end

  def test_a_stray_token_that_closes_without_a_unit_still_fails_loudly
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CopticTtParser.new.parse(
        "<meta corpus=\"x\" license=\"CC-BY 4.0\" document_cts_urn=\"urn:cts:copticLit:x\">\n" \
        "<norm_group norm_group=\"ⲁ\">\n" \
        "<norm xml:id=\"u1\" norm=\"ⲁ\">\nⲁ\n</norm>\n</norm_group>\n</meta>\n", label: "synthetic"
      )
    end
    assert_match(/unsegmented stretch/, error.message)
  end

  def test_a_stray_group_left_open_at_eof_still_fails_loudly
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CopticTtParser.new.parse(
        "<meta corpus=\"x\" license=\"CC-BY 4.0\" document_cts_urn=\"urn:cts:copticLit:x\">\n" \
        "<norm_group norm_group=\"ⲁ\">\n", label: "synthetic"
      )
    end
    assert_match(/unsegmented stretch/, error.message)
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
