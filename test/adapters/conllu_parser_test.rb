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
