# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::AoxmlParser (P31-1): the hethiter.net AOxml family
# (namespace hethiter.net/ns/AO/1.0 — HPM's own format, NOT TEI), tested
# standalone on byte-verbatim WHOLE real Beta 0.3 manuscripts. Passage =
# the tablet LINE; surface = the TRANSLITERATION with the standard
# Hittitological damage marks ([ ] ⌈ ⌉ ⟦ ⟧), determinatives in upstream's
# own °…° convention; the line's Unicode cuneiform rides annotations.
# The mrp candidate analyses ride tokens VERBATIM; a "lemma" mints only
# for the disambiguated subset (digit selection or single candidate) —
# upstream's hypothesis layer is never flattened.
class AoxmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("tlhdig")

  DAMAGE_URN = "urn:nabu:tlhdig:433:besrit:kbo.43.277"

  def parser = Nabu::Adapters::AoxmlParser.new

  def parse_fixture(relative, urn:, cth: nil, project: nil)
    parser.parse(File.join(FIXTURES, relative), urn: urn, cth: cth, project: project)
  end

  def damage_doc
    parse_fixture("CTH 433_XML_BESRIT/KBo 43.277.xml",
                  urn: DAMAGE_URN, cth: "433", project: "BESRIT")
  end

  # -- the damage-heavy fragment (KBo 43.277) --------------------------------

  def test_parses_the_fragment_one_passage_per_line_with_locations_verbatim
    doc = damage_doc
    assert_equal 12, doc.count, "12 tablet lines, Rs.? 1′–12′"
    assert_equal "hit", doc.language
    assert_equal "KBo 43.277 (CTH 433)", doc.title
    assert_equal "#{DAMAGE_URN}:1", doc.first.urn
    assert_equal "Rs.? 1′", doc.first.annotations["location"]
    assert_equal "Rs.? 12′", doc.passages.last.annotations["location"]
  end

  def test_renders_damage_brackets_determinatives_and_illegible_signs
    doc = damage_doc
    assert_equal "]x°ḪI.A°-it x[", doc.first.text,
                 "del_fin → ], del_in → [, <d> → °…° (upstream's own mrp convention), x = illegible"
    assert_equal ["ḪI.A"], doc.first.annotations["tokens"].first["determinatives"]
    assert_equal "t]ar-na-aḫ-ḫi AN [", doc.passages[2].text,
                 "<space> indentation renders nothing; <c type=\"sign\"> renders its content"
  end

  def test_unresolved_multi_candidate_words_keep_hypotheses_verbatim_and_mint_no_lemma
    token = damage_doc.passages[2].annotations["tokens"].first
    assert_equal "tarnaḫḫi", token["trans"]
    assert_equal " ", token["selection"], "mrp0sel verbatim: candidates offered, none selected"
    assert_equal ["tarn=a-@lassen@1SG.PRS@II.3@", "tarn=aḫḫ-@lassen@3SG.PRS@II.9@"],
                 token["analyses"], "the mrp layer rides verbatim, in candidate order"
    refute token.key?("lemma"), "an unresolved multi-candidate word mints NO lemma (goo300k discipline)"
  end

  def test_damaged_words_carry_the_del_selector_and_no_analyses
    token = damage_doc.first.annotations["tokens"].first
    assert_equal "DEL", token["selection"]
    refute token.key?("analyses")
    refute token.key?("lemma")
  end

  def test_a_single_candidate_with_blank_selector_is_disambiguated
    # Rs.? 7′: EGIR-pa carries exactly one candidate under mrp0sel=" ".
    token = damage_doc.passages[6].annotations["tokens"]
                      .find { |t| t["trans"] == "EGIRpa" } || flunk("EGIRpa token missing")
    assert_equal "EGIR-pa", token["lemma"]
    assert_equal "wieder", token["gloss"]
    assert_equal ["EGIR"], token["sumerograms"]
  end

  def test_akkadograms_are_recorded_per_token
    token = damage_doc.passages[6].annotations["tokens"]
                      .find { |t| t["trans"] == "I-NA" } || flunk("I-NA token missing")
    assert_equal ["I-NA"], token["akkadograms"]
    assert_equal "INA", token["lemma"], "the Akkadogram lemma is the data's own claim"
    assert_equal "I-N[A", token["form"]
  end

  def test_unicode_cuneiform_rides_annotations_never_the_surface
    passage = damage_doc.passages[2]
    assert_equal "𒋻𒈾𒄴𒄭𒀭▒", passage.annotations["cuneiform"],
                 "the cu= attribute verbatim, damaged-glyph blocks included"
    refute_match(/[\u{12000}-\u{12FFF}]/, passage.text, "the surface stays transliteration")
  end

  def test_gaps_and_notes_ride_the_open_lines_annotations
    last = damage_doc.passages.last
    assert_equal ["Rs.? bricht ab"], last.annotations["gaps"]
    assert_equal [{ "n" => "1", "c" => "Vs.? Zeichenspuren von 3 Zeilen." }], last.annotations["notes"]
  end

  # -- the well-preserved merged manuscript (KBo 52.195+) --------------------

  def merged_doc
    parse_fixture("CTH 626_XML_HFR/KBo 52.195+.xml", urn: "urn:nabu:tlhdig:626:hfr:kbo.52.195+",
                                                     cth: "626", project: "HFR")
  end

  def test_parses_the_merged_manuscript_with_the_witness_block
    doc = merged_doc
    assert_equal 32, doc.count
    assert_equal "KBo 52.195++ (CTH 626)", doc.title,
                 "the header docID (with the join ++) — not the filename"
    assert_equal ["KBo 52.195", "Bo 7016", "Bo 6803", "KBo 52.113"], doc.metadata["manuscripts"],
                 "the AO:Manuscripts witness sigla, in order"
    assert_equal({ "cth" => { "value" => "626", "raw" => "CTH 626" },
                   "project" => { "value" => "hfr", "raw" => "HFR" } },
                 doc.metadata["facets"])
  end

  def test_digit_selection_resolves_the_candidate_and_its_letter_sub_alternative
    doc = merged_doc
    first = doc.first.annotations["tokens"].first
    assert_equal " 1a", first["selection"]
    assert_equal "LÚ˽°GIŠ°GIDRU", first["lemma"]
    assert_equal "NOM.SG(UNM)", first["morph"],
                 "the letter picks '{a → NOM.SG(UNM)}' out of the brace list"
    assert_equal "29.1.1", first["morph_class"]

    humant = doc.flat_map { |ps| ps.annotations["tokens"] }
                .find { |t| t["trans"] == "ḫumantuš" } || flunk("ḫumantuš token missing")
    assert_equal "ḫumant", humant["lemma"],
                 "citation derivation: 'ḫumant-' loses only the trailing stem hyphen"
    assert_equal "ḫu-u-ma-an-⌈du⌉-u[š]", humant["form"], "laes → ⌈ ⌉ half-brackets"
    assert_equal "QUANall.ACC.PL.C", humant["morph"]
  end

  def test_slash_variant_lemmas_take_the_first_variant
    token = merged_doc.flat_map { |ps| ps.annotations["tokens"] }
                      .find { |t| t["trans"] == "tai" } || flunk("tai token missing")
    assert_equal "dai", token["lemma"], "'dai-/te-/ti(ya)-' → first variant, parens+hyphen off"
    assert_equal " 4a", token["selection"]
  end

  def test_kola_and_paragraph_separators_ride_annotations
    doc = merged_doc
    assert_equal ["1"], doc.first.annotations["kola"]
    assert doc.any? { |ps| ps.annotations["paragraph_end"] },
           "parsep after a line marks the paragraph end"
  end

  # -- the bilingual (KUB 4.8): per-line languages, honest fallbacks ---------

  def bilingual_doc
    parse_fixture("CTH 314_XML_TLH/KUB 4.8.xml", urn: "urn:nabu:tlhdig:314:tlh:kub.4.8",
                                                 cth: "314", project: "TLH")
  end

  def test_per_line_languages_map_from_the_censused_table
    doc = bilingual_doc
    assert_equal({ "akk" => 8, "hit" => 19 }, doc.map(&:language).tally)
    assert_equal "hit", doc.language,
                 "document language = the majority over mapped line languages — the " \
                 "header's XXXlang placeholder never wins"
  end

  def test_akkadian_words_carry_the_akk_selector_and_no_invented_analysis
    token = bilingual_doc.flat_map { |ps| ps.annotations["tokens"] }
                         .find { |t| t["selection"] == "AKK" }
    refute_nil token, "the AKK word-language selector rides verbatim"
    refute token.key?("lemma")
  end

  # -- the Hurrian ritual (KBo 20.119): HURR words, subscripts ----------------

  def hurrian_doc
    parse_fixture("CTH 786_XML_HFR/KBo 20.119.xml", urn: "urn:nabu:tlhdig:786:hfr:kbo.20.119",
                                                    cth: "786", project: "HFR")
  end

  def test_hurrian_lines_map_to_xhu_and_hurr_words_stay_unanalyzed
    doc = hurrian_doc
    assert_equal "xhu", doc.language
    assert_equal({ "xhu" => 92, "hit" => 4 }, doc.map(&:language).tally)
    token = doc.first.annotations["tokens"].find { |t| t["selection"] == "HURR" }
    refute_nil token
    refute token.key?("lemma")
  end

  def test_sign_variant_subscripts_render_as_unicode_subscripts
    token = hurrian_doc.flat_map { |ps| ps.annotations["tokens"] }
                       .find { |t| t["trans"] == "URUneui" } || flunk("URUneui token missing")
    assert_equal "URU-ne-wiᵢ", token["form"], "<subscr c=\"i\"/> → ᵢ (wiᵢ, the sign-variant index)"
    assert_equal ["URU"], token["sumerograms"]
  end

  # -- quarantine: the Beta reality, loud ------------------------------------

  def test_a_malformed_file_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parse_fixture("quarantine/KUB 10.7.xml", urn: "urn:nabu:tlhdig:612:tlh:kub.10.7",
                                               cth: "612", project: "TLH")
    end
    assert_match(/not well-formed/, error.message)
  end

  def test_a_line_less_stub_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parse_fixture("quarantine/304_e.xml", urn: "urn:nabu:tlhdig:222:tlh:304_e",
                                            cth: "222", project: "TLH")
    end
    assert_match(/no renderable transliteration lines/, error.message)
  end
end
