# frozen_string_literal: true

require "test_helper"
require "nabu/query/morph_facets"

module Query
  # Nabu::Query::MorphFacets (P13-6): the facet parser + the per-family
  # morphology normalizer that folds UD `feats` and PROIEL positional
  # `morphology` into ONE UD-named query vocabulary (and honestly declines
  # ORACC, which carries no inflectional morphology). Token shapes here are the
  # real fixture shapes verified against the live catalog.
  class MorphFacetsTest < Minitest::Test
    MF = Nabu::Query::MorphFacets

    # -- parsing --------------------------------------------------------------

    def test_parse_canonicalizes_and_resolves_aliases
      assert_equal [%w[case dat], %w[number plur]], MF.parse("case=dat,number=pl")
      assert_equal [%w[case dat], %w[number plur]], MF.parse("Case=Dat, Number=PL")
      assert_equal [%w[number sing]], MF.parse("number=sg"), "sg → sing alias"
    end

    def test_parse_rejects_malformed
      assert_raises(MF::Error) { MF.parse("case") }
      assert_raises(MF::Error) { MF.parse("case=") }
      assert_raises(MF::Error) { MF.parse("=dat") }
      assert_raises(MF::Error) { MF.parse("") }
      assert_raises(MF::Error) { MF.parse("  ,  ") }
    end

    # -- UD (CoNLL-U) passthrough ---------------------------------------------

    # The real grc-perseus token shape: `feats` is the raw UD string.
    def test_ud_feats_parsed_lowercased
      token = { "form" => "λόγοις", "lemma" => "λόγος",
                "feats" => "Case=Dat|Gender=Masc|Number=Plur", "upos" => "NOUN" }
      assert_equal({ "case" => "dat", "gender" => "masc", "number" => "plur" },
                   MF.features(token))
      assert MF.match?(token, [%w[case dat], %w[number plur]])
      refute MF.match?(token, [%w[case gen]])
    end

    # -- PROIEL positional decode ---------------------------------------------

    # Real orv/chu shapes: `morphology` is the 10-position tag. Each position
    # decodes to the SAME UD facet names as the UD family.
    def test_proiel_positional_morphology_decoded
      # "-s---fa--i": number sing, gender fem, case acc (молитва accusative).
      token = { "form" => "млтвѹ", "lemma" => "молитва", "morphology" => "-s---fa--i" }
      assert_equal({ "number" => "sing", "gender" => "fem", "case" => "acc" },
                   MF.features(token))
      assert MF.match?(token, [%w[case acc], %w[number sing]])
      refute MF.match?(token, [%w[case dat]])
    end

    def test_proiel_finite_verb_decoded
      # "2spma----i": 2nd person sing present imperative active (imperative остави).
      token = { "form" => "остави", "lemma" => "оставити", "morphology" => "2spma----i" }
      assert_equal({ "person" => "2", "number" => "sing", "tense" => "pres",
                     "mood" => "imp", "voice" => "act" }, MF.features(token))
      assert MF.match?(token, [%w[mood imp], %w[voice act]])
    end

    def test_proiel_genitive_plural_with_degree
      # "-p---mgpwi": plural masc genitive positive (святыи gen pl); strength (w)
      # and inflection (i) positions are intentionally not decoded.
      token = { "form" => "стхъ", "lemma" => "святыи", "morphology" => "-p---mgpwi" }
      assert_equal({ "number" => "plur", "gender" => "masc", "case" => "gen", "degree" => "pos" },
                   MF.features(token))
      assert MF.match?(token, [%w[case gen], %w[number plur]])
    end

    def test_proiel_indeclinable_yields_no_features
      token = { "form" => "за", "lemma" => "за", "morphology" => "---------n" }
      assert_empty MF.features(token)
      refute MF.match?(token, [%w[case dat]]), "no morphology matches no facet"
    end

    # -- AGDT positional decode (GLAUx `postag`) -------------------------------

    # Real GLAUx shapes (test/fixtures/glaux/xml): `postag` is the 9-slot AGDT
    # tag — pos, person, number, tense, mood, voice, gender, case, degree.
    # Slots 2-9 decode to the SAME UD facet names as the other families.
    def test_agdt_noun_decoded
      token = { "form" => "Δημόκριτος", "lemma" => "Δημόκριτος", "postag" => "n-s---mn-" }
      assert_equal({ "number" => "sing", "gender" => "masc", "case" => "nom" }, MF.features(token))
      assert MF.match?(token, [%w[case nom], %w[number sing]])
      refute MF.match?(token, [%w[case gen]])
    end

    def test_agdt_finite_verb_decoded_with_proiel_aorist_spelling
      token = { "form" => "ἔφυ", "lemma" => "φύω", "postag" => "v3saia---" }
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "aor",
                     "mood" => "ind", "voice" => "act" }, MF.features(token))
      assert MF.match?(token, [%w[tense aor], %w[mood ind]])
    end

    def test_agdt_participle_carries_verbal_and_nominal_slots
      token = { "form" => "τέρψας", "lemma" => "τέρπω", "postag" => "v-sapamn-" }
      assert_equal({ "number" => "sing", "tense" => "aor", "mood" => "part", "voice" => "act",
                     "gender" => "masc", "case" => "nom" }, MF.features(token))
    end

    def test_agdt_infinitive_and_passive_subjunctive
      assert_equal({ "tense" => "pres", "mood" => "inf", "voice" => "act" },
                   MF.features({ "form" => "ὁρᾶν", "postag" => "v--pna---" }))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "aor",
                     "mood" => "sub", "voice" => "pass" },
                   MF.features({ "form" => "ἑψηθῇ", "postag" => "v3sasp---" }))
    end

    def test_agdt_degree_slot_decoded
      token = { "form" => "πλεῖστα", "lemma" => "πολύς", "postag" => "a-p---nas" }
      assert_equal({ "number" => "plur", "gender" => "neut", "case" => "acc", "degree" => "sup" },
                   MF.features(token))
    end

    # AGDT gender `c` (common, on personal pronouns like σε) is UD's
    # Gender=Com — AGDT's one code beyond the shared PROIEL rows.
    def test_agdt_common_gender_decoded
      token = { "form" => "σε", "lemma" => "σύ", "postag" => "p-s---ca-" }
      assert_equal({ "number" => "sing", "gender" => "com", "case" => "acc" }, MF.features(token))
      assert MF.match?(token, MF.parse("gender=com"))
    end

    def test_agdt_unknown_slot_code_dropped
      assert_equal({ "case" => "acc" }, MF.features({ "postag" => "n-x---qa-" }))
    end

    def test_agdt_punctuation_and_artificial_yield_no_features
      assert_empty MF.features({ "form" => "·", "lemma" => "·", "postag" => "u--------" })
      assert_empty MF.features({ "form" => "E", "lemma" => "E", "postag" => "z--------" })
      refute MF.match?({ "postag" => "u--------" }, [%w[case dat]])
    end

    # Precedence: morphology → feats → postag; a token carrying an earlier
    # key never falls through to a later one.
    def test_decoder_precedence
      assert_equal({ "case" => "dat" },
                   MF.features({ "feats" => "Case=Dat", "postag" => "n-s---mn-" }))
      assert_equal({ "number" => "plur" },
                   MF.features({ "morphology" => "-p--------", "postag" => "n-s---mn-" }))
      assert_empty MF.features({ "morphology" => "---------n", "postag" => "n-s---mn-" }),
                   "an all-blank earlier tag does not fall through"
    end

    # -- ORACC honest absence -------------------------------------------------

    # ORACC tokens carry a NER-flavoured `pos` and NO inflectional morphology:
    # inflectional facets never match — absence, not error.
    def test_oracc_pos_only_token_has_no_inflectional_features
      token = { "form" => "LU₂", "lemma" => "awīlu", "pos" => "N", "norm" => "awīl" }
      assert_empty MF.features(token)
      refute MF.match?(token, [%w[case dat]])
    end

    def test_featureless_and_non_hash_tokens_never_match
      refute MF.match?({ "form" => "x" }, [%w[case dat]])
      refute MF.match?(nil, [%w[case dat]])
      assert_empty MF.features("not a hash")
    end

    # -- evidence rendering ---------------------------------------------------

    def test_describe_renders_features_in_readable_order
      ud = { "feats" => "Number=Plur|Case=Dat|Gender=Masc" }
      assert_equal "number=plur|gender=masc|case=dat", MF.describe(ud)
      proiel = { "morphology" => "2spma----i" }
      assert_equal "person=2|number=sing|tense=pres|mood=imp|voice=act", MF.describe(proiel)
      agdt = { "postag" => "v-sapamn-" }
      assert_equal "number=sing|gender=masc|case=nom|tense=aor|mood=part|voice=act", MF.describe(agdt)
    end

    # The decoder seam: an explicit ordered table, token key → decode method
    # → source scope (nil = any source; the treebank families' keys are
    # unambiguous). The scoped rows' keys collide across the library
    # ("morph", "msd", "analyses", "msa" each name DIFFERENT tagsets in
    # other sources), so a scoped row decodes only its own sources' tokens.
    def test_decoder_table_is_explicit_and_ordered
      assert_equal %w[morphology feats postag analyses vt morpho morph msd msd msa],
                   MF::DECODERS.map(&:first)
      MF::DECODERS.each do |_key, method, sources|
        assert MF.respond_to?(method), "#{method} is a module function"
        assert(sources.nil? || (sources.is_a?(Array) && !sources.empty?), "#{method}: nil or a slug list")
      end
      assert_equal [nil, nil, nil], MF::DECODERS.first(3).map(&:last), "the treebank rows stay unscoped"
    end

    # A scoped row never decodes another source's token, even one carrying
    # its key: REF/coptic/vakk "morph" tags are not OSHB codes.
    def test_scoped_rows_decode_only_their_own_sources
      oshb = { "form" => "בָּרָ֣א", "lemma" => "1254 a", "morph" => "HVqp3ms" }
      assert_equal "perf", MF.features(oshb, source: "oshb")["conjugation"]
      assert_empty MF.features(oshb), "no source → no scoped decode"
      assert_empty MF.features(oshb, source: "ref"), "another source's morph is not OSHB"
      refute MF.match?(oshb, MF.parse("person=3"), source: "coptic-scriptorium")
    end

    # -- ambiguity: readings ----------------------------------------------------

    # A decoder may return alternative READINGS (Diorisis lists every
    # candidate analysis; CorA/Menota/OSHB tags carry value alternatives).
    # match? is true when ANY reading satisfies every facet; features keeps
    # only what is CERTAIN (one value shared by every reading).
    def test_readings_any_match_and_certain_features
      token = { "form" => "τῶν", "lemma" => "ὁ", "analyses" => ["fem gen pl", "masc/neut gen pl"] }
      assert_equal({ "case" => "gen", "number" => "plur" }, MF.features(token, source: "diorisis"))
      %w[fem masc neut].each do |gender|
        assert MF.match?(token, MF.parse("gender=#{gender},case=gen"), source: "diorisis")
      end
      refute MF.match?(token, MF.parse("case=dat"), source: "diorisis")
    end

    def test_readings_keep_cross_feature_correlation
      # Real Thucydides token: masc acc OR neut nom/voc/acc — never masc nom.
      token = { "form" => "ἀξιολογώτατον", "lemma" => "ἀξιόλογος",
                "analyses" => ["masc acc superl sg", "neut nom/voc/acc superl sg"] }
      assert MF.match?(token, MF.parse("gender=masc,case=acc"), source: "diorisis")
      assert MF.match?(token, MF.parse("gender=neut,case=nom"), source: "diorisis")
      refute MF.match?(token, MF.parse("gender=masc,case=nom"), source: "diorisis")
      assert_equal({ "degree" => "sup", "number" => "sing" }, MF.features(token, source: "diorisis"))
    end

    # The evidence shows the readings that MATCHED, alternatives "/"-joined.
    def test_describe_renders_matching_readings
      token = { "analyses" => ["masc acc superl sg", "neut nom/voc/acc superl sg"] }
      assert_equal "number=sing|gender=masc|case=acc|degree=sup",
                   MF.describe(token, source: "diorisis", facets: MF.parse("gender=masc"))
      assert_equal "number=sing|gender=masc/neut|case=acc/nom/voc|degree=sup",
                   MF.describe(token, source: "diorisis")
    end

    # -- Diorisis (Morpheus-style analysis strings) ---------------------------

    # Real fixture tokens (test/fixtures/diorisis, Thucydides 1.1).
    def test_diorisis_finite_verb
      token = { "form" => "ξυνέγραψε", "lemma" => "συγγράφω", "pos" => "verb",
                "analyses" => ["aor ind act 3rd sg"] }
      assert_equal({ "tense" => "aor", "mood" => "ind", "voice" => "act", "person" => "3",
                     "number" => "sing" }, MF.features(token, source: "diorisis"))
    end

    def test_diorisis_participle_mediopassive
      token = { "form" => "καθισταμένου", "lemma" => "καθίστημι",
                "analyses" => ["pres part mp masc/neut gen sg"] }
      assert_equal({ "tense" => "pres", "mood" => "part", "voice" => "mp", "case" => "gen",
                     "number" => "sing" }, MF.features(token, source: "diorisis"))
      assert MF.match?(token, MF.parse("gender=neut,voice=mp"), source: "diorisis")
    end

    # Dialect parentheticals and lexical flags (indeclform, proclitic,
    # adverbial …) carry no inflection — skipped, never mapped.
    def test_diorisis_skips_dialect_and_lexical_flags
      assert_empty MF.features({ "analyses" => ["indeclform (conj)"] }, source: "diorisis")
      assert_equal({ "case" => "acc", "number" => "sing", "gender" => "fem" },
                   MF.features({ "analyses" => ["fem acc sg (attic epic ionic)"] }, source: "diorisis"))
      assert_equal({ "tense" => "impf", "mood" => "sub", "degree" => "cmp" },
                   MF.features({ "analyses" => ["imperf subj irreg_comp"] }, source: "diorisis"))
    end

    # -- ETCBC (BHSA word features) -------------------------------------------

    # Real BHSA tokens (test/fixtures/bhsa): Dan 2:4 יְדַבְּרוּ, Hag 2:4
    # נְאֻם / חֲזַק, Dan 2:4 Aramaic מַלְכָּא (emphatic), Jonah 2:6 חָבוּשׁ.
    def test_etcbc_finite_verb
      token = { "form" => "יְדַבְּר֧וּ", "lex_utf8" => "דבר", "sp" => "verb", "vs" => "piel",
                "vt" => "wayq", "gn" => "m", "nu" => "pl", "ps" => "p3", "st" => "NA" }
      assert_equal({ "person" => "3", "number" => "plur", "gender" => "masc", "stem" => "piel",
                     "conjugation" => "wayq" }, MF.features(token, source: "bhsa"))
    end

    def test_etcbc_state_and_imperative_mood
      construct = { "form" => "נְאֻם", "vs" => "NA", "vt" => "NA", "gn" => "m", "nu" => "sg",
                    "ps" => "NA", "st" => "c" }
      assert_equal({ "gender" => "masc", "number" => "sing", "state" => "cons" },
                   MF.features(construct, source: "bhsa"))
      emphatic = { "form" => "מַלְכָּא֙", "vs" => "NA", "vt" => "NA", "gn" => "m", "nu" => "sg",
                   "ps" => "NA", "st" => "e" }
      assert_equal "emph", MF.features(emphatic, source: "bhsa")["state"]
      impv = { "form" => "חֲזַ֣ק", "vs" => "qal", "vt" => "impv", "gn" => "m", "nu" => "sg",
               "ps" => "p2", "st" => "NA" }
      assert_equal({ "person" => "2", "gender" => "masc", "number" => "sing", "stem" => "qal",
                     "conjugation" => "impv", "mood" => "imp" }, MF.features(impv, source: "bhsa"))
    end

    def test_etcbc_participle_and_unknown_person
      token = { "form" => "חָב֥וּשׁ", "vs" => "qal", "vt" => "ptcp", "gn" => "m", "nu" => "sg",
                "ps" => "unknown", "st" => "a" }
      assert_equal({ "gender" => "masc", "number" => "sing", "state" => "abs", "stem" => "qal",
                     "conjugation" => "ptcp", "mood" => "part" }, MF.features(token, source: "bhsa"))
    end

    # -- Abegg (DSS word features), in the ETCBC spelling ---------------------

    # Real DSS tokens (test/fixtures/dss). Abegg's stem/tense names are
    # recoded to the ETCBC spelling by upstream's OWN harmonization pairs
    # (vs → vs_etcbc, vt → vt_etcbc), so one query reaches bhsa and dss.
    def test_abegg_wayyiqtol_jussive_recoded
      token = { "form" => "יהי", "lex" => "היה", "sp" => "verb", "ps" => "3", "gn" => "m", "nu" => "s",
                "vs" => "qal", "vt" => "wayy", "md" => "juss", "morpho" => "vqw3msj",
                "vt_etcbc" => "wayq" }
      assert_equal({ "person" => "3", "gender" => "masc", "number" => "sing", "stem" => "qal",
                     "conjugation" => "wayq", "mood" => "jus" }, MF.features(token, source: "dss"))
    end

    def test_abegg_stems_recoded_to_etcbc
      hifil = { "form" => "מדח", "gn" => "m", "nu" => "s", "st" => "a", "vs" => "hifil", "vt" => "ptca",
                "morpho" => "vhPmsa", "vs_etcbc" => "hif" }
      assert_equal({ "gender" => "masc", "number" => "sing", "state" => "abs", "stem" => "hif",
                     "conjugation" => "ptca", "mood" => "part" }, MF.features(hifil, source: "dss"))
      aphel = { "form" => "יעל", "ps" => "3", "gn" => "m", "nu" => "s", "vs" => "aphel", "vt" => "impf",
                "morpho" => "vAi3ms", "vs_etcbc" => "afel" }
      assert_equal "afel", MF.features(aphel, source: "dss")["stem"]
    end

    # Abegg gender "b" (both — OSHB's sibling code, which its parser names
    # "both") is a masc|fem alternative; state "d" (determined) is the
    # emphatic state, queryable as emph or det.
    def test_abegg_both_gender_and_determined_state
      both = { "form" => "נפש", "gn" => "b", "nu" => "s", "st" => "c", "morpho" => "ncbsc" }
      assert_equal({ "number" => "sing", "state" => "cons" }, MF.features(both, source: "dss"))
      assert MF.match?(both, MF.parse("gender=masc"), source: "dss")
      assert MF.match?(both, MF.parse("gender=fem"), source: "dss")
      determined = { "form" => "פרכת", "gn" => "f", "nu" => "s", "st" => "d", "morpho" => "ncfsd" }
      assert MF.match?(determined, MF.parse("state=det"), source: "dss")
      assert MF.match?(determined, MF.parse("state=emph"), source: "dss")
    end

    # The *_etcbc layer is silver (BHSA + machine learning) and is NOT merged
    # into Abegg's gold features: a gn_etcbc fill never becomes a gender.
    def test_abegg_ignores_the_silver_etcbc_layer
      token = { "form" => "x", "morpho" => "ncxs", "nu" => "s", "gn_etcbc" => "m", "nu_etcbc" => "sg" }
      assert_equal({ "number" => "sing" }, MF.features(token, source: "dss"))
    end

    # -- OSHB morph codes ------------------------------------------------------

    # Real OSHB tokens (test/fixtures/oshb); the code table is upstream's
    # own read/Script/MorphologyParser.js.
    def test_oshb_verb_and_prefixed_noun
      assert_equal({ "stem" => "qal", "conjugation" => "perf", "person" => "3", "gender" => "masc",
                     "number" => "sing" }, MF.features({ "morph" => "HVqp3ms" }, source: "oshb"))
      assert_equal({ "gender" => "fem", "number" => "sing", "state" => "abs" },
                   MF.features({ "morph" => "HR/Ncfsa" }, source: "oshb"), "the prefix segment is not the word")
    end

    def test_oshb_suffix_segment_is_not_the_word
      # Real canonical code: wayyiqtol 3ms + 3ms pronominal suffix.
      assert_equal({ "stem" => "qal", "conjugation" => "wayq", "person" => "3", "gender" => "masc",
                     "number" => "sing" }, MF.features({ "morph" => "HC/Vqw3ms/Sp3fs" }, source: "oshb"))
    end

    def test_oshb_participle_jussive_cohortative_and_aramaic
      assert_equal({ "stem" => "qal", "conjugation" => "ptcp", "mood" => "part", "gender" => "fem",
                     "number" => "sing", "state" => "cons" },
                   MF.features({ "morph" => "HVqsfsc" }, source: "oshb"))
      assert_equal({ "stem" => "qal", "conjugation" => "impf", "mood" => "jus", "person" => "3",
                     "gender" => "masc", "number" => "sing" },
                   MF.features({ "morph" => "HVqj3ms" }, source: "oshb"))
      assert_equal "coh", MF.features({ "morph" => "HVqh1cp" }, source: "oshb")["mood"]
      assert_equal "com", MF.features({ "morph" => "HVqh1cp" }, source: "oshb")["gender"]
      assert_equal "peal", MF.features({ "morph" => "AVqi2mp" }, source: "oshb")["stem"],
                   "Aramaic q is peal (the Aramaic stem table)"
      assert_equal "niphal", MF.features({ "morph" => "HVNp3ms" }, source: "oshb")["stem"]
    end

    def test_oshb_both_gender_and_infinitive
      token = { "morph" => "HNcbsc" }
      assert MF.match?(token, MF.parse("gender=masc,state=cons"), source: "oshb")
      assert MF.match?(token, MF.parse("gender=fem"), source: "oshb")
      assert_equal({ "stem" => "qal", "conjugation" => "infc", "mood" => "inf" },
                   MF.features({ "morph" => "HVqc" }, source: "oshb"))
      assert_empty MF.features({ "morph" => "HTo" }, source: "oshb")
      assert_empty MF.features({ "morph" => "Xbogus" }, source: "oshb")
    end

    # -- CorA msd (ReM / ReN) ---------------------------------------------------

    # Real ReM/ReN tokens (test/fixtures/rem, test/fixtures/ren). The values
    # are self-describing; alternatives are ","- (ReM) or "-"-joined (ReN);
    # "*" / "_" / inflection classes (st/wk, Sw/St/Irr/Prpr) are skipped.
    def test_cora_rem_finite_verb_and_weak_adjective
      assert_equal({ "mood" => "ind", "tense" => "pres", "number" => "sing", "person" => "3" },
                   MF.features({ "form" => "ſtet", "pos" => "VVFIN", "msd" => "Ind.Pres.Sg.3" }, source: "rem"))
      assert_equal({ "degree" => "pos", "gender" => "neut", "case" => "gen", "number" => "plur" },
                   MF.features({ "pos" => "ADJS", "msd" => "Pos.Neut.Gen.Pl.wk" }, source: "rem"))
      assert_equal({ "mood" => "sub", "tense" => "past", "number" => "sing", "person" => "3" },
                   MF.features({ "pos" => "VVFIN", "msd" => "Subj.Past.Sg.3" }, source: "rem"))
      assert_empty MF.features({ "pos" => "NA", "msd" => "[.?.]" }, source: "rem")
      assert MF.match?({ "msd" => "Masc,Neut.Dat.Sg" }, MF.parse("gender=neut,case=dat"), source: "rem")
    end

    def test_cora_ren_alternatives_and_konjunktiv
      hof = { "form" => "hof", "pos" => "NA<NA", "msd" => "Masc-Neut.Dat-Akk.Sg" }
      assert_equal({ "number" => "sing" }, MF.features(hof, source: "ren"))
      assert MF.match?(hof, MF.parse("gender=neut,case=acc"), source: "ren")
      refute MF.match?(hof, MF.parse("case=nom"), source: "ren")
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "pres", "mood" => "sub" },
                   MF.features({ "pos" => "VVFIN<VV", "msd" => "Irr.3.Sg.Pres.Konj" }, source: "ren"))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "past" },
                   MF.features({ "pos" => "VVFIN<VV", "msd" => "Sw.3.Sg.Past.*" }, source: "ren"))
      assert_equal({ "person" => "1", "number" => "plur" },
                   MF.features({ "pos" => "PPER<PPER", "msd" => "1.Pl._.Dat-Akk" }, source: "ren"))
      assert_equal "sup", MF.features({ "msd" => "Sup.Neut.Dat.Sg.*" }, source: "ren")["degree"]
    end

    # -- IMP msd (goo300k) -------------------------------------------------------

    # Real goo300k tokens; the closed table is the corpus root's own fvLib
    # (Ncm … Rgs). Coarse tags: nominal gender, verbal aspect, degree.
    def test_imp_coarse_tags
      assert_equal({ "gender" => "fem" }, MF.features({ "form" => "oblaſt", "msd" => "Ncf" }, source: "goo300k"))
      assert_equal({ "aspect" => "perf" }, MF.features({ "msd" => "Vme" }, source: "goo300k"))
      assert_equal({ "aspect" => "imp" }, MF.features({ "msd" => "Vmp" }, source: "goo300k"))
      assert_equal({ "degree" => "cmp" }, MF.features({ "msd" => "Agc" }, source: "goo300k"))
      assert_equal({ "degree" => "cmp" }, MF.features({ "msd" => "Rgc" }, source: "goo300k"))
      assert_empty MF.features({ "msd" => "Va" }, source: "goo300k")
      biaspectual = { "msd" => "Vmb" }
      assert_empty MF.features(biaspectual, source: "goo300k")
      assert MF.match?(biaspectual, MF.parse("aspect=perf"), source: "goo300k")
      assert MF.match?(biaspectual, MF.parse("aspect=imp"), source: "goo300k")
    end

    # -- Menota msa ----------------------------------------------------------------

    # Real Menota tokens (test/fixtures/menota). vR (the -sk/-st forms) is
    # the middle voice — menotec, the PROIEL conversion of the same Menota
    # texts, codes those forms voice m.
    def test_menota_finite_verb_and_noun
      assert_equal({ "tense" => "pres", "mood" => "ind", "person" => "3", "number" => "sing",
                     "voice" => "act" },
                   MF.features({ "lemma" => "vera", "msa" => "xVB fF tPS mIN p3 nS vA" }, source: "menota"))
      assert_equal({ "gender" => "neut", "number" => "plur", "case" => "dat" },
                   MF.features({ "lemma" => "vígskarð", "msa" => "xNC gN nP cD sI" }, source: "menota"))
    end

    def test_menota_infinitive_mediopassive_participle_and_grade
      assert_equal({ "mood" => "inf", "tense" => "pres", "voice" => "mid" },
                   MF.features({ "lemma" => "þarfna", "msa" => "xVB fI tPS vR" }, source: "menota"))
      assert_equal({ "mood" => "part", "tense" => "past", "voice" => "act", "gender" => "neut",
                     "number" => "sing", "case" => "acc" },
                   MF.features({ "lemma" => "ganga", "msa" => "xVB fP tPT vA gN nS cA sI" }, source: "menota"))
      assert_equal({ "degree" => "cmp", "number" => "plur", "case" => "nom" },
                   MF.features({ "lemma" => "hár", "msa" => "xAJ rC gU nP cN sD" }, source: "menota"))
      assert_equal "sub", MF.features({ "msa" => "xVB fF tPS mSU p3 nP vA" }, source: "menota")["mood"]
    end

    def test_menota_value_alternatives_and_alternative_analyses
      dem = { "lemma" => "sá", "msa" => "xDD nP gMFN cD" }
      assert_equal({ "number" => "plur", "case" => "dat" }, MF.features(dem, source: "menota"))
      assert MF.match?(dem, MF.parse("gender=fem"), source: "menota")
      # Real canonical msa: two full analyses, present OR preterite.
      tense = { "msa" => "xVB fF tPS mIN p3 nS vA | xVB fF tPT mIN p3 nS vA" }
      assert MF.match?(tense, MF.parse("tense=past"), source: "menota")
      assert MF.match?(tense, MF.parse("tense=pres"), source: "menota")
      assert_nil MF.features(tense, source: "menota")["tense"]
      assert MF.match?({ "msa" => "xVB fF tPS mINSU p3 nS vA" }, MF.parse("mood=sub"), source: "menota")
    end
  end
end
