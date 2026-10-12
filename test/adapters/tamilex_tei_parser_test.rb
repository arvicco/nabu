# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The `tamilex-tei` parser family (P121-3): TAMILEX's critical TEI editions
# of the classical Tamil corpus (github.com/UHH-Tamilex), exercised on four
# whole REAL upstream files (test/fixtures/tamilex, recipe in the README):
# a Tiruvāymoḻi verse with an ambiguous wordsplit, a Kuṟuntokai poem with
# its colophon, witness list and variant apparatus, a Tirukkuṟaḷ couplet
# with two commentaries, and a Tolkāppiyam sūtra with four commentaries
# whose prose blocks carry no xml:id — plus upstream's own empty poem
# template (_KTSAMPLE.xml). The adapter's own test covers
# discovery, exclusion and fetch.
class TamilexTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("tamilex")

  TVM = File.join(FIXTURES, "NalayiratTivviyapPirapantam", "TVM1.8.2.xml")
  KT = File.join(FIXTURES, "Kuruntokai", "KT1.xml")
  TK = File.join(FIXTURES, "Tirukkural", "TK1.xml")
  TOL = File.join(FIXTURES, "Tolkappiyam", "TolC273.xml")

  def parse(path, urn: "urn:t")
    Nabu::Adapters::TamilexTeiParser.new.parse(path, urn: urn)
  end

  def passage(document, id)
    document.find { |p| p.urn == "urn:t:#{id}" } || flunk("no passage #{id}: #{document.map(&:urn)}")
  end

  # -- passages: the edition's xml:id units, positional fallback ------------

  def test_a_verse_is_one_passage_keyed_by_its_xml_id
    doc = parse(TVM)
    assert_equal ["urn:t:TVM1.8.2"], doc.map(&:urn)
    verse = doc.passages.first
    assert_equal "tam-Latn", verse.language
    assert_equal "ammā ṉāyppiṉṉu\nmemmāṇ pumāṉāṉa\nvemmā vāykīṇṭa\ncemmā kaṇṇaṉē", verse.text,
                 "lines join by newline, verbatim"
    assert_equal "Even after being the father\nhe is Kṛṣṇa with large red eyes\n" \
                 "who split the mouth of the cruel horse\nwho was our glorious man.",
                 verse.annotations["translation"], "the parallel English lg rides the Tamil passage"
  end

  def test_colophon_precedes_the_poem_and_footnotes_leave_the_translation
    doc = parse(KT)
    assert_equal %w[urn:t:KT1-kilavi urn:t:KT1], doc.map(&:urn)
    kilavi = passage(doc, "KT1-kilavi")
    assert_equal "tōḻi kaiyuṟai maṟuttatu.", kilavi.text
    assert kilavi.annotations["colophon"], "the -kilavi block is the poem's situation colophon"
    assert_equal "The confidante refusing [the acceptance of his] present.", kilavi.annotations["translation"],
                 "the editor's footnote is not translation text"
    poem = passage(doc, "KT1")
    assert_equal "ceṅkaḷam paṭakkoṉ ṟavuṇart tēytta\nceṅkō lampiṟ ceṅkōṭ ṭiyāṉaik\n" \
                 "kaḻaṟoṭic cēey kuṉṟaṅ\nkurutip pūviṉ kulaikkān taṭṭē.", poem.text
    refute poem.annotations.key?("colophon")
    translation = poem.annotations["translation"]
    assert translation.start_with?("Red the ground from killing, the demons reduced\nby red-stemmed arrows")
    assert_includes translation, "anklets and bracelets", "a choice of renderings keeps the first"
    refute_includes translation, "bracelets becoming loose"
  end

  def test_commentaries_are_their_own_layer_with_the_commentator_named
    doc = parse(TK)
    assert_equal(%w[TK1 TK1-Pari_paayiram TK1-Pari1 TK1-Pari2 TK1-M1 TK1-M2],
                 doc.map { |p| p.urn.delete_prefix("urn:t:") })
    root = passage(doc, "TK1")
    assert_equal "akara mutala veḻuttellā māti\npakavaṉ mutaṟṟē yulaku", root.text
    refute root.annotations.key?("commentator")
    pari = passage(doc, "TK1-Pari1")
    assert_equal "Parimēlaḻakar", pari.annotations["commentator"]
    assert_equal "(itaṉporuḷ) akaramākiya mutalaiyuṭaiyaṉa eḻuttukkaḷellām; atupōla, " \
                 "ātipakavaṉākiya mutalaiyuṭait tulaku.—(eṉṟa vāṟu).", pari.text
    assert pari.annotations["translation"].start_with?("The meaning of this [Kuṟaḷ] is as follows")
    assert_equal "Maṇakkuṭavar", passage(doc, "TK1-M2").annotations["commentator"]
    assert_equal(%w[Parimēlaḻakar Maṇakkuṭavar], doc.metadata["commentaries"].map { |c| c["commentator"] })
  end

  def test_a_sic_corr_choice_reads_the_editors_correction
    text = passage(parse(TK), "TK1-Pari_paayiram").text
    assert_includes text, "muṟaimaiyākaliṉ,"
    refute_includes text, "muṟamaiyākaliṉ"
  end

  def test_id_less_commentary_blocks_get_positional_citations
    doc = parse(TOL)
    ids = doc.map { |p| p.urn.delete_prefix("urn:t:") }
    assert_equal %w[TolC273 2.1 2.2 TolC273-Ilam-cit1 2.4 3.1 3.2 TolC273-Cena-cit1 3.4
                    4.1 4.2 4.3 TolC273-Nacc-cit1 4.5 5.1 5.2 TolC273-Tey-cit1 TolC273-Tey-cit2 5.5], ids,
                 "<text n>.<Tamil block ordinal> where upstream minted no xml:id"
    assert_equal "māveṉ kiḷavi viyaṅkō ḷacaiccol.", passage(doc, "TolC273").text
    assert_equal "varalāṟu:", passage(doc, "2.1").text
    assert_equal "Iḷampūraṇar", passage(doc, "2.1").annotations["commentator"]
    assert_equal "ōrmātōḻiyavartērmaṇikkural", passage(doc, "TolC273-Tey-cit2").text,
                 "a bare sic stays; an apparatus note inside the line is not text"
    assert_equal "eṉavarum. (25)", passage(doc, "4.5").text
    assert_equal(doc.passages.each_index.to_a, doc.passages.map(&:sequence))
  end

  def test_unpaired_english_blocks_record_the_commentary_edition
    commentaries = parse(TOL).metadata["commentaries"]
    assert_equal(%w[Iḷampūraṇar Cēṉāvaraiyar Nacciṉārkkiṉiyar Teyvaccilaiyār],
                 commentaries.map { |c| c["commentator"] })
    assert_equal "ed. Namaccivāya Mutaliyār 1931, 166.", commentaries.first["edition"]
    assert_equal "1929, 177.", commentaries.last["edition"]
  end

  # -- the wordsplit standOff: gold segmentation, lemma, gloss --------------

  def test_wordsplit_entries_load_as_gold_tokens
    tokens = parse(TVM).passages.first.annotations["tokens"]
    assert_equal 14, tokens.size, "13 entries + the ambiguous superEntry's first reading"
    assert_equal({ "form" => "ammāṉ", "lemma" => "ammāṉ", "gloss" => "lord",
                   "roles" => ["masculine singular", "noun"] }, tokens.first)
    assert_equal({ "form" => "āyp", "lemma" => "āy", "gloss" => "become", "roles" => ["absolutive"] },
                 tokens[1], "a sandhi gemination is part of the split form, never of the lemma")
    assert_equal({ "form" => "piṉṉum", "lemma" => "piṉṉum", "gloss" => "moreover" }, tokens[2],
                 "an entry with no gramGrp carries no roles key")
  end

  def test_an_ambiguous_superentry_keeps_its_other_readings
    last = parse(TVM).passages.first.annotations["tokens"].last
    assert_equal "kaṇṇaṉ-ē", last["form"]
    assert_equal "kaṇṇaṉ", last["lemma"], "form[@type=simple] is the headword (the clitic split off)"
    assert_equal "Kaṇṇaṉ", last["gloss"]
    assert_equal "ē", last["enclitic"]
    assert_equal [[{ "form" => "kaṇṇaṉ-ē", "lemma" => "kaṇṇaṉ", "gloss" => "eye-he",
                     "roles" => ["pronominalised noun", "singular", "masculine"], "enclitic" => "ē" }]],
                 last["alternatives"]
  end

  def test_multi_token_alternative_readings_stay_whole
    tokens = passage(parse(TOL), "TolC273-Cena-cit1").annotations["tokens"]
    yunka = tokens[1]
    assert_equal "yuṇka-mā", yunka["form"]
    assert_equal "uṇka", yunka["lemma"]
    assert_equal "uṇka", yunka["sandhi"], "the glide stays out of the cleaned sandhi form, as upstream"
    assert_equal(%w[uṇka mā], yunka["alternatives"].first.map { |t| t["lemma"] },
                 "the other split is two words")
  end

  def test_glide_elision_and_sandhi_follow_upstreams_own_cleaning
    tokens = passage(parse(KT), "KT1").annotations["tokens"]
    assert_equal 20, tokens.size
    konru = tokens[3]
    assert_equal({ "form" => "koṉṟu", "lemma" => "koṉṟu", "gloss" => "felled", "sandhi" => "koṉṟ",
                   "roles" => ["absolutive"] }, konru, "an elided vowel is restored in the lemma")
    kantattu = tokens.last
    assert_equal "kāntaṭṭu-ē", kantattu["form"]
    assert_equal "kāntaṭṭu", kantattu["lemma"]
    assert_equal "kāntaṭṭ", kantattu["sandhi"]
    root = passage(parse(TK), "TK1").annotations["tokens"]
    assert_equal "eḻuttu", root[2]["lemma"], "the glide v drops, the elided u stays"
    assert_equal "veḻuttu", root[2]["form"]
  end

  def test_tokens_only_where_a_wordsplit_targets_the_passage
    doc = parse(TK)
    assert passage(doc, "TK1").annotations.key?("tokens")
    refute passage(doc, "TK1-Pari1").annotations.key?("tokens")
    assert_equal 3, passage(parse(KT), "KT1-kilavi").annotations["tokens"].size
  end

  def test_the_variant_apparatus_rides_its_passage
    apparatus = passage(parse(KT), "KT1").annotations["apparatus"]
    assert_equal 4, apparatus.size
    assert_equal({ "loc" => "35,41", "lemma" => "lampiṟ", "witnesses" => %w[C2 C3v Cam],
                   "readings" => [{ "text" => "lampiṉ", "witnesses" => %w[L1 C1 C3 G1 G2 Nam EA] }] },
                 apparatus.first)
    assert_equal(%w[ceṅkō veṇkōṭ], apparatus[1]["readings"].map { |r| r["text"] })
  end

  # -- header mining -----------------------------------------------------------

  def test_header_title_parts_ride_metadata
    doc = parse(TVM)
    assert_equal "Tiruvāymoḻi 1.8.2. Nammāḻvār", doc.title
    assert_equal "Tiruvāymoḻi", doc.metadata["work"]
    assert_equal "1.8.2", doc.metadata["number"]
    assert_equal "Nammāḻvār", doc.metadata["poet"], "the attributed poet, verbatim"
    assert_equal({ "work" => { "value" => "Tiruvāymoḻi" } }, doc.metadata["facets"])
    kt = parse(KT).metadata
    assert_equal "1", kt["number"], "a bare trailing number is the poem number"
    assert_equal "Tipputtōḷār", kt["poet"]
    tk = parse(TK).metadata
    assert_equal "kaṭavuḷ vāḻttu", tk["section"], "the chapter term inside the title"
    assert_equal [{ "name" => "Jason Cannon-Silber", "role" => "translator" }], tk["editors"]
    tol = parse(TOL).metadata
    assert_equal "Tolkāppiyam Collatikāram", tol["work"]
    assert_equal "273", tol["number"]
    refute tol.key?("poet"), "no persName, no attribution"
  end

  def test_the_witness_list_rides_metadata_verbatim
    witnesses = parse(KT).metadata["witnesses"]
    assert_equal 43, witnesses.size, "top-level witnesses only; sub-sigla stay nested upstream"
    assert_equal({ "id" => "Ed", "siglum" => "Ed", "description" => "Wilden edition" }, witnesses.first)
    london = witnesses.find { |w| w["id"] == "L1" }
    assert_equal "paper manuscript from London [Or. 2726] complete (1874, Maturai, for Burnell)",
                 london["description"]
    refute parse(TVM).metadata.key?("witnesses")
  end

  # -- failure: an edition with no text quarantines --------------------------

  def test_upstreams_textless_skeleton_raises_parse_error
    error = assert_raises(Nabu::ParseError) { parse(File.join(FIXTURES, "Kuruntokai", "_KTSAMPLE.xml")) }
    assert_match(/no edition text/, error.message, "the real empty poem template, never ingested silently")
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.xml")
      File.write(path, "<TEI><text>")
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end
end
