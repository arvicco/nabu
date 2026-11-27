# frozen_string_literal: true

require "test_helper"
require "stringio"

# ConlluParser unit tests (P3-3), run against the REAL trimmed UD fixtures in
# test/fixtures/ud/ — one directory per treebank. The parser is the second
# parser family (sibling to EpidocParser): sentence = passage, 10-column TSV,
# lemma/upos/feats → annotations JSON, mandatory sent_id → passage urn.
class ConlluParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/ud", __dir__)
  GOTHIC = File.join(FIXTURES, "gothic-proiel", "got_proiel-ud-test-head50.conllu")
  GREEK  = File.join(FIXTURES, "greek-proiel", "grc_proiel-ud-test-head50.conllu")
  LATIN  = File.join(FIXTURES, "latin-ittb", "la_ittb-ud-test-head50+mwt.conllu")

  GOTHIC_URN = "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50"
  LATIN_URN  = "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt"

  # --- happy path: gothic head50 -----------------------------------------

  def test_gothic_head50_yields_fifty_passages
    doc = parse(GOTHIC, urn: GOTHIC_URN, language: "got")
    assert_equal 50, doc.size
  end

  def test_first_passage_urn_and_text_and_sequence
    first = parse(GOTHIC, urn: GOTHIC_URN, language: "got").first
    assert_equal "#{GOTHIC_URN}:46928", first.urn
    assert_equal "þata auk ist witoþ jah praufeteis", first.text
    assert_equal 0, first.sequence
    assert_equal "got", first.language
  end

  def test_first_passage_tokens_and_spot_annotations
    first = parse(GOTHIC, urn: GOTHIC_URN, language: "got").first
    tokens = first.annotations.fetch("tokens")
    assert_equal 6, tokens.length

    t1 = tokens.first
    assert_equal "1", t1["id"]
    assert_equal "þata", t1["form"]
    assert_equal "sa", t1["lemma"]
    assert_equal "PRON", t1["upos"]
    assert_equal "Pd", t1["xpos"] # PROIEL terse 2-char XPOS
    assert_equal "3", t1["head"]
    assert_equal "nsubj", t1["deprel"]
    assert_equal "Ref=MATT_7.12", t1["misc"] # PROIEL MISC citation carried through
    refute t1.key?("deps"), "DEPS column must not be carried"
    assert_equal "Case=Nom|Gender=Neut|Number=Sing", t1["feats"]

    # `_` placeholder columns are dropped, not kept as "_" or nil: token 2
    # (auk) has FEATS `_`.
    assert_equal "auk", tokens[1]["lemma"]
    refute tokens[1].key?("feats"), "token 2 FEATS is `_` and must be dropped"
  end

  def test_source_comment_becomes_annotation
    first = parse(GOTHIC, urn: GOTHIC_URN, language: "got").first
    assert_equal "The Gothic Bible, Matthew 7", first.annotations["source"]
  end

  # --- sentence translations + references (P118-R4 S6) -------------------
  # The held-but-dark audit: UD sentence-level translation comments
  # (text_en, translation, translated_text, sent_transl_*, transl_*) and
  # the reference comment were read past. One whitelist now carries them.

  def test_text_en_translation_rides_annotations
    path = File.join(FIXTURES, "coptic-bohairic", "cop_bohairic-ud-test-head50.conllu")
    first = parse_whitelisted(path, language: "cop").first
    assert_equal({ "text_en" => "The beginning of the Good News of Jesus Christ, the Son of God." },
                 first.annotations["translations"])
  end

  def test_translation_comment_rides_annotations
    path = File.join(FIXTURES, "hittite-hittb", "hit_hittb-ud-test-head50.conllu")
    first = parse_whitelisted(path, language: "hit").first
    assert_equal "If someone injures a person and makes him ill, he will heal that person.",
                 first.annotations.dig("translations", "translation")
  end

  def test_reference_comment_rides_annotations
    first = parse_whitelisted(LATIN, language: "lat").first
    assert_equal "ittb-scg-s2102", first.annotations["reference"]
    refute first.annotations.key?("translations"), "no translation comment, no key"
  end

  def test_empty_translation_comments_mint_nothing
    io = StringIO.new("# sent_id = 1\n# text = a\n# sent_transl_en = \n" \
                      "1\ta\ta\tX\t_\t_\t0\troot\t_\t_\n\n")
    refute parse_whitelisted(io, language: "orv").first.annotations.key?("translations")
  end

  def test_sentence_comment_whitelist_is_opt_in
    path = File.join(FIXTURES, "coptic-bohairic", "cop_bohairic-ud-test-head50.conllu")
    annotations = parse(path, urn: "urn:x", language: "cop").first.annotations
    refute annotations.key?("translations"),
           "callers serving translations as sibling documents (old-tibetan) keep them out"
    dipi = parse(File.join(FIXTURES, "prakrit-dipi", "pra_dipi-ud-test.conllu"), urn: "urn:x", language: "pra")
    refute dipi.first.annotations.key?("orig"), "the original readings are opt-in too"
  end

  # The language-tagged translation spelling (`# text[eng] =`, any tag):
  # Manchu GDUD carries one on nearly every block, under its verbatim key.
  def test_language_tagged_text_translations_ride_annotations
    passages = parse_whitelisted(File.join(FIXTURES, "manchu-gdud", "mnc_gdud-ud-test.conllu"), language: "mnc").to_a
    assert_equal({ "text[eng]" => "I went with that person." }, passages.first.annotations["translations"])
    tagged = passages.count { |p| p.annotations.dig("translations", "text[eng]") }
    assert_equal 80, tagged
    assert_equal 81, passages.count { |p| p.annotations["translations"] }, "plus the one block's text_en"
  end

  def test_tagged_translations_of_any_language_ride_verbatim
    io = StringIO.new("# sent_id = 1\n# text = a\n# text[spa] = una\n# text[eng] = \n" \
                      "1\ta\ta\tX\t_\t_\t0\troot\t_\t_\n\n")
    assert_equal({ "text[spa]" => "una" }, parse_whitelisted(io, language: "mnc").first.annotations["translations"])
  end

  # The TuDeT treebanks' per-language translation keys and TUECL's English
  # `# gloss` sentence rendering.
  def test_modern_language_text_keys_and_the_tuecl_gloss_ride_translations
    guarani = parse_whitelisted(File.join(FIXTURES, "guarani-oldtudet", "gn_oldtudet-ud-test.conllu"),
                                language: "gn").to_a
    assert_equal({ "text_eng" => "to the men", "text_spa" => "a los hombres" },
                 guarani.first.annotations["translations"])
    assert(guarani.any? { |p| p.annotations.dig("translations", "text_port") == "\"Isso é para Deus\"." })

    tuecl = parse_whitelisted(File.join(FIXTURES, "classical-chinese-tuecl", "lzh_tuecl-ud-test-head50.conllu"),
                              language: "lzh").first
    assert_equal({ "gloss" => "In the Northern Ocean there is a fish" }, tuecl.annotations["translations"])
  end

  # Birchbark letters written on two sides split their translations
  # (`transl_ru-1`, `transl_en_2-1` …); HittB spells one block `translated`.
  # Comment lines copied verbatim from the live treebanks.
  def test_split_and_variant_translation_keys_ride_translations
    io = StringIO.new("# sent_id = 1\n# text = a\n# transl_ru-1 = берестяную грамоту отдай Якиму сам.\n" \
                      "# transl_en_2-1 = [Outer side] + From Ivan to Dristliv.\n" \
                      "# translated = And the four which you, Ištanu, have hitched up\n" \
                      "1\ta\ta\tX\t_\t_\t0\troot\t_\t_\n\n")
    assert_equal({ "translated" => "And the four which you, Ištanu, have hitched up",
                   "transl_ru-1" => "берестяную грамоту отдай Якиму сам.",
                   "transl_en_2-1" => "[Outer side] + From Ivan to Dristliv." },
                 parse_whitelisted(io, language: "orv").first.annotations["translations"])
  end

  # --- original readings ---------------------------------------------------
  # The same sentence in another form beside the `# text` surface: DIPI's
  # Leiden-bracketed `# orig`, the transliterations (PTNK/GLC `translit`,
  # CAVaL `transliterated_text`) and BOUN's Ottoman-script `text_arabic`.
  # Each rides its verbatim key on its OWN sentence (the reference
  # precedent — never carried across a newdoc's sentences).

  def test_the_dipi_original_reading_rides_its_own_sentence
    passages = parse_whitelisted(File.join(FIXTURES, "prakrit-dipi", "pra_dipi-ud-test.conllu"), language: "pra").to_a
    first = passages.first
    assert_equal "iy[aṃ] dhaṃma-lipī Devānaṃpriyena Priyadasinā rāña lekh[ā]pitā", first.annotations["orig"]
    assert_equal "iyaṃ dhaṃma-lipī Devānaṃpriyena Priyadasinā rāña lekhāpitā", first.text
    assert_equal(84, passages.count { |p| p.annotations["orig"] })
    refute first.annotations.key?("translations")
  end

  def test_transliterations_and_original_script_readings_ride_verbatim
    caval = parse_whitelisted(File.join(FIXTURES, "classical-armenian-caval", "xcl_caval-ud-test-head50.conllu"),
                              language: "xcl").first
    assert caval.annotations["transliterated_text"].start_with?("Zgoyš lerowkʻ ołormowtʻean jerowm;")
    assert caval.annotations.dig("translations", "translated_text").start_with?("Take heed")

    ptnk = parse_whitelisted(File.join(FIXTURES, "hebrew-ptnk", "hbo_ptnk-ud-test-head50.conllu"),
                             language: "hbo").first
    assert ptnk.annotations["translit"].start_with?("ṿayavoʼu shene hamalʼakhim sedomah")

    boun = parse_whitelisted(File.join(FIXTURES, "ottoman-boun", "ota_boun-ud-test-head50.conllu"),
                             language: "ota").first
    assert boun.annotations["text_arabic"].start_with?(". مصاحبه مه نهايت")
    refute boun.annotations.key?("translations"), "an original-script reading is no translation"
  end

  # --- sentence metadata comments (the newdoc-scoped whitelist) ----------

  BIRCHBARK = File.join(FIXTURES, "old-east-slavic-birchbark", "orv_birchbark-ud-test-head50.conllu")
  RNC = File.join(FIXTURES, "old-east-slavic-rnc", "orv_rnc-ud-test-head50.conllu")
  RUTHENIAN = File.join(FIXTURES, "old-east-slavic-ruthenian", "orv_ruthenian-ud-test-head50.conllu")
  EGYPTIAN = File.join(FIXTURES, "egyptian-pc", "egy_pc-ud-test-head50.conllu")
  COPTIC = File.join(FIXTURES, "coptic-bohairic", "cop_bohairic-ud-test-head50.conllu")

  # A `# newdoc id` block opens an upstream document: the whitelisted
  # comments in that block (birchbark's date_created) belong to EVERY
  # sentence until the next newdoc, never only to the first.
  def test_newdoc_comments_scope_to_every_sentence_of_their_document
    passages = parse_whitelisted(BIRCHBARK, language: "orv").to_a
    first, second = passages.first(2)
    assert_equal "texts/birchbark/002", first.annotations["newdoc_id"]
    assert_equal "1360-1380", first.annotations["date_created"]
    assert_equal %w[texts/birchbark/002 1360-1380], second.annotations.values_at("newdoc_id", "date_created"),
                 "002-2 carries no comment of its own — the document's scope does"
    letter = passages.find { |p| p.urn.end_with?(":005-1") } || flunk("005-1")
    assert_equal %w[texts/birchbark/005 1320-1340], letter.annotations.values_at("newdoc_id", "date_created")
  end

  def test_rnc_and_ruthenian_document_titles_and_creation_dates
    rnc = parse_whitelisted(RNC, language: "orv").to_a
    assert_equal "kungur__Kungur_akty_75", rnc.first.annotations["newdoc_id"]
    assert_equal "1698-05-02", rnc.first.annotations["created"]
    assert_match(/\AЦарская грамота кунгурскому воеводе/, rnc.first.annotations["title"])
    duel = rnc.find { |p| p.urn.end_with?(":Delo_duel_1637-2") } || flunk("Delo_duel_1637-2")
    assert_equal %w[varia__Delo_duel_1637 1637], duel.annotations.values_at("newdoc_id", "created")

    # The bare `# newdoc = …` spelling opens a document too.
    ruthenian = parse_whitelisted(RUTHENIAN, language: "orv").first
    assert_equal "litopys.org.ua__statut2__st1566_05", ruthenian.annotations["newdoc_id"]
    assert_equal "orv-be", ruthenian.annotations["lang"]
    assert_match(/\AДругий \(Волинський\) статут/, ruthenian.annotations["title"])
  end

  # egyptian-pc states its metadata on every sentence (no newdoc): each
  # sentence keeps its own, verbatim.
  def test_egyptian_sentence_metadata_rides_verbatim
    first = parse_whitelisted(EGYPTIAN, language: "egy").first
    expected = { "title" => "PT", "edition" => "Sethe", "spell" => "23", "section" => "16a",
                 "king" => "Unas", "date" => "5th Dynasty", "lang" => "Old_Egyptian",
                 "genre" => "religious", "place" => "Saqqara",
                 "TLA" => "IBUBd7piZ5pZrUceohIbqW09xnA; IBUBdWfjUXae5UrZjn2Peb3DWVs" }
    assert_equal expected, first.annotations.slice(*expected.keys)
    refute first.annotations.key?("newdoc_id")
  end

  # The GUM-style meta:: namespace (coptic-bohairic) sheds its prefix;
  # the CTS urn is crosswalk material, stored verbatim (no join here).
  def test_meta_namespace_comments_and_cts_ids
    first = parse_whitelisted(COPTIC, language: "cop").first
    assert_equal "bohairic.mark:bohairic.Mark_01", first.annotations["newdoc_id"]
    assert_equal "urn:cts:copticLit:nt.mark.bohairic_ed:1", first.annotations["document_cts_urn"]
    assert_equal "Bohairic Gospel of Mark 1 (Digital Edition)", first.annotations["title"]
    assert_equal "N/A", first.annotations["author"], "upstream's own not-applicable mark, verbatim"
  end

  def test_sentence_metadata_is_opt_in_too
    refute parse(BIRCHBARK, urn: "urn:x", language: "orv").first.annotations.key?("newdoc_id")
  end

  def parse_whitelisted(source, language:)
    Nabu::Adapters::ConlluParser.new.parse(source, urn: "urn:x", language: language, sentence_comments: true)
  end

  # --- multiword tokens: latin-ittb --------------------------------------

  def test_latin_mwt_range_line_present_in_annotations
    doc = parse(LATIN, urn: LATIN_URN, language: "lat")
    sentence = doc.find { |p| p.urn.end_with?(":test-s1") }
    refute_nil sentence, "expected the MWT sentence test-s1"

    tokens = sentence.annotations.fetch("tokens")
    mwt = tokens.find { |t| t["id"] == "14-15" }
    refute_nil mwt, "the 14-15 multiword-token range line must be present"
    assert_equal "essetque", mwt["form"]
    # A range line carries only FORM (+ optional MISC): every other column is
    # `_` and therefore dropped.
    assert_equal %w[id form].sort, mwt.keys.sort

    # Its member tokens are still present as ordinary tokens.
    assert(tokens.any? { |t| t["id"] == "14" && t["form"] == "esset" })
    assert(tokens.any? { |t| t["id"] == "15" && t["form"] == "que" })
  end

  # --- NFC: greek proiel --------------------------------------------------

  def test_greek_text_is_nfc_and_normalized_form_is_the_minted_search_form
    first = parse(GREEK, urn: "urn:nabu:ud:greek-proiel:grc", language: "grc").first
    assert_equal "Δελφῶν οἶδα ἐγὼ οὕτω ἀκούσας γενέσθαι", first.text
    assert first.text.unicode_normalized?(:nfc), "text must be NFC"
    assert first.text_normalized.unicode_normalized?(:nfc), "text_normalized must be NFC"
    # Boundary-minted (P6-4): marks stripped, downcased, final sigma → σ.
    assert_equal "δελφων οιδα εγω ουτω ακουσασ γενεσθαι", first.text_normalized
  end

  # --- error paths (string-surgery tempfiles) ----------------------------

  def test_malformed_line_raises_parse_error_naming_line
    good = File.read(GOTHIC)
    # Corrupt the first token line (line 4) by dropping a tab-delimited column.
    lines = good.lines
    lines[3] = lines[3].sub("\t", " ") # first tab → space ⇒ 9 columns
    error = assert_raises(Nabu::ParseError) { parse_string(lines.join, urn: GOTHIC_URN, language: "got") }
    assert_match(/columns/, error.message)
    assert_match(/:4:/, error.message)
  end

  def test_missing_sent_id_raises_parse_error
    good = File.read(GOTHIC)
    without = good.lines.reject { |l| l.start_with?("# sent_id") }.join
    error = assert_raises(Nabu::ParseError) { parse_string(without, urn: GOTHIC_URN, language: "got") }
    assert_match(/sent_id/, error.message)
  end

  def test_empty_source_raises_parse_error
    error = assert_raises(Nabu::ParseError) { parse_string("\n\n", urn: GOTHIC_URN, language: "got") }
    assert_match(/no sentence blocks/, error.message)
  end

  # --- the citation hook (P23-1) ------------------------------------------

  def test_citation_hook_maps_sent_id_to_the_minted_citation
    doc = Nabu::Adapters::ConlluParser.new.parse(
      GOTHIC,
      urn: GOTHIC_URN, language: "got", citation: ->(sent_id) { "s#{sent_id}" }
    )
    assert_equal "#{GOTHIC_URN}:s46928", doc.first.urn,
                 "the passage urn suffix is the hook's output, not the raw sent_id"
  end

  def test_document_metadata_passes_through
    doc = Nabu::Adapters::ConlluParser.new.parse(
      GOTHIC, urn: GOTHIC_URN, language: "got", metadata: { "scribe" => "Wulfila" }
    )
    assert_equal({ "scribe" => "Wulfila" }, doc.metadata)
  end

  def test_citation_hook_returning_blank_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::ConlluParser.new.parse(GOTHIC, urn: GOTHIC_URN, language: "got",
                                                     citation: ->(_) { "" })
    end
    assert_match(/citation/, error.message)
  end

  private

  def parse(path, urn:, language:)
    Nabu::Adapters::ConlluParser.new.parse(path, urn: urn, language: language)
  end

  def parse_string(content, urn:, language:)
    Nabu::Adapters::ConlluParser.new.parse(StringIO.new(content), urn: urn, language: language)
  end
end
