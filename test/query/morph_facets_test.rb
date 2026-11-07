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
    # → source scope (nil = any source). The scoped rows' keys collide
    # across the library ("morph", "msd", "analyses", "msa" each name
    # DIFFERENT tagsets in other sources), so a scoped row decodes only its
    # own sources' tokens. The treebank rows stay unscoped; AES — whose
    # "morphology" is an Egyptian morpheme label, not a PROIEL tag — is the
    # one scoped row placed AHEAD of them, so its tokens never reach them.
    def test_decoder_table_is_explicit_and_ordered
      assert_equal %w[form morphology feats postag analyses vt morpho morph msd morph msd msa pos pos_code pos
                      analysis form gloss],
                   MF::DECODERS.map(&:first)
      MF::DECODERS.each do |_key, method, sources|
        assert MF.respond_to?(method), "#{method} is a module function"
        assert(sources.nil? || (sources.is_a?(Array) && !sources.empty?), "#{method}: nil or a slug list")
      end
      assert_equal %w[aes], MF::DECODERS.first.last
      assert_equal [nil, nil, nil], MF::DECODERS[1, 3].map(&:last), "the treebank rows stay unscoped"
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

    # -- CorA morph (REF) ---------------------------------------------------------

    # Real ReF tokens (test/fixtures/ref, plus deposit-censused tags for the
    # syncretic genders). German spellings (Mask, Akk, Präs, Prät, Konj,
    # Komp); MN/MF/FN are gender alternatives; "*", the inflection classes
    # (Unr/St/Sw) and Unflekt/Flekt (infinitives) are skipped.
    def test_cora_ref_finite_verb_nominal_and_adjective
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "pres", "mood" => "ind" },
                   MF.features({ "pos" => "VAFIN", "morph" => "3.Sg.Präs.Ind.Unr" }, source: "ref"))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "pres", "mood" => "sub" },
                   MF.features({ "pos" => "VVFIN", "morph" => "3.Sg.Präs.Konj.Sw" }, source: "ref"))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "past" },
                   MF.features({ "pos" => "VAFIN", "morph" => "3.Sg.Prät.*.Unr" }, source: "ref"))
      assert_equal({ "gender" => "masc", "case" => "acc", "number" => "sing" },
                   MF.features({ "pos" => "NA", "morph" => "Mask.Akk.Sg" }, source: "ref"))
      assert_equal({ "degree" => "sup", "gender" => "masc", "case" => "nom", "number" => "sing" },
                   MF.features({ "pos" => "ADJA", "morph" => "Sup.Mask.Nom.Sg" }, source: "ref"))
      assert_equal({ "degree" => "cmp" }, MF.features({ "pos" => "ADJD", "morph" => "Komp" }, source: "ref"))
      assert_equal({ "number" => "sing", "case" => "nom" },
                   MF.features({ "pos" => "PPER", "morph" => "*.Sg.*.Nom" }, source: "ref"))
      assert_empty MF.features({ "pos" => "VVINF", "morph" => "Unflekt" }, source: "ref")
      assert_empty MF.features({ "pos" => "APPR", "morph" => "*" }, source: "ref")
    end

    def test_cora_ref_syncretic_genders
      wurm = { "lemma" => "wurm", "pos" => "NA", "morph" => "MN.Akk.Sg" }
      assert_equal({ "case" => "acc", "number" => "sing" }, MF.features(wurm, source: "ref"))
      assert MF.match?(wurm, MF.parse("gender=masc,case=acc"), source: "ref")
      assert MF.match?(wurm, MF.parse("gender=neut"), source: "ref")
      refute MF.match?(wurm, MF.parse("gender=fem"), source: "ref")
      assert MF.match?({ "lemma" => "gewalt", "morph" => "MF.Akk.Sg" }, MF.parse("gender=fem"), source: "ref")
      assert MF.match?({ "lemma" => "glied", "morph" => "FN.Nom.Sg" }, MF.parse("gender=neut"), source: "ref")
      assert_empty MF.features({ "morph" => "Mask.Akk.Sg" }, source: "rem"), "REF's morph key is REF-scoped"
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

    # Coptic Scriptorium `pos` (real besa tokens): only what the TAG fixes —
    # the features upstream's own CoNLL-U conversion attaches to every
    # feature-bearing token of that tag. Person/number/gender ride the
    # word form, not the tag (the CoNLL-U FEATS join carries those).
    def test_coptic_tags_decode_what_the_tag_fixes
      cop = "coptic-scriptorium"
      assert_equal({ "polarity" => "neg" }, MF.features({ "lemma" => "ⲙⲡⲉ", "pos" => "ANEGPST" }, source: cop))
      assert_equal({ "polarity" => "neg" }, MF.features({ "lemma" => "ⲧⲙ", "pos" => "NEG" }, source: cop))
      assert_equal({ "prontype" => "prs", "definite" => "def" },
                   MF.features({ "lemma" => "ⲁⲛⲟⲛ", "pos" => "PPERS" }, source: cop))
      assert_equal({ "prontype" => "prs", "definite" => "def", "poss" => "yes" },
                   MF.features({ "lemma" => "ⲡⲉⲩ", "pos" => "PPOS" }, source: cop))
      assert_equal({ "prontype" => "dem", "definite" => "def" },
                   MF.features({ "lemma" => "ⲡⲁⲓ", "pos" => "PDEM" }, source: cop))
      assert_equal({ "prontype" => "art" }, MF.features({ "lemma" => "ⲟⲩ", "pos" => "ART" }, source: cop),
                   "definiteness rides the article's lemma, not the tag")
      assert_equal({ "numtype" => "card" }, MF.features({ "pos" => "NUM" }, source: cop))
      assert_equal({ "verbform" => "fin", "mood" => "imp" }, MF.features({ "pos" => "VIMP" }, source: cop))
      assert_equal({ "verbform" => "fin" }, MF.features({ "pos" => "VSTAT" }, source: cop))
    end

    # Fused tags (a pronoun cliticized onto its host) decode every part;
    # tags that fix nothing (V finite-or-infinitive, N, PREP, the plain
    # auxiliaries) decode nothing — honest absence; another source's "pos"
    # (ORACC's N/PN/V) is never read as Coptic.
    def test_coptic_fused_and_featureless_tags
      cop = "coptic-scriptorium"
      assert_equal({ "polarity" => "neg", "prontype" => "prs", "definite" => "def" },
                   MF.features({ "pos" => "ANEGPST_PPERS" }, source: cop))
      assert_equal({ "prontype" => "prs", "definite" => "def" }, MF.features({ "pos" => "AOPT_PPERS" }, source: cop))
      %w[V N PREP APST CONJ PINT EXIST].each do |tag|
        assert_empty MF.features({ "pos" => tag }, source: cop), tag
      end
      assert_empty MF.features({ "pos" => "NEG" }, source: "oracc")
    end

    # The FEATS join (UD feats on the token) outranks the tag decode: the
    # richer person/number/gender read, never a merge of both.
    def test_coptic_ud_feats_outrank_the_tag
      token = { "lemma" => "ⲛⲧⲱⲧⲛ", "pos" => "PPERS",
                "feats" => "Definite=Def|Number=Plur|Person=2|PronType=Prs" }
      assert_equal({ "definite" => "def", "number" => "plur", "person" => "2", "prontype" => "prs" },
                   MF.features(token, source: "coptic-scriptorium"))
    end

    # -- CEIPoM pos_code ----------------------------------------------------------

    # Real CEIPoM tokens (test/fixtures/ceipom + deposit-censused ones):
    # pos_code is the 9-slot AGDT tag, decoded through the AGDT table —
    # Venetic doto "v3sria---" (perf-3-sg), Old Latin tatod "v3sfma---"
    # (fut-impr-3-sg), [fiet "v3sfip---", Umbrian upsatuh "v-prppnn-",
    # Oscan faciundis-type gerundives "v-p-g-nd-", the comparative maior.
    def test_ceipom_pos_code_decodes_through_the_agdt_table
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "perf", "mood" => "ind", "voice" => "act" },
                   MF.features({ "form" => "doto", "pos_code" => "v3sria---" }, source: "ceipom"))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "fut", "mood" => "imp", "voice" => "act" },
                   MF.features({ "form" => "tatod", "pos_code" => "v3sfma---" }, source: "ceipom"))
      assert_equal "pass", MF.features({ "form" => "[fiet", "pos_code" => "v3sfip---" }, source: "ceipom")["voice"]
      assert_equal({ "number" => "plur", "tense" => "perf", "mood" => "part", "voice" => "pass", "gender" => "neut",
                     "case" => "nom" },
                   MF.features({ "form" => "upsatuh⁝", "pos_code" => "v-prppnn-" }, source: "ceipom"))
      assert_equal "gdv", MF.features({ "form" => "faciundis", "pos_code" => "v-p-g-nd-" }, source: "ceipom")["mood"]
      assert_equal({ "number" => "sing", "gender" => "fem", "case" => "nom", "degree" => "cmp" },
                   MF.features({ "form" => "maior", "pos_code" => "a-s---fnc" }, source: "ceipom"))
      assert_empty MF.features({ "form" => "asted", "pos_code" => "---------" }, source: "ceipom")
      assert_empty MF.features({ "pos_code" => "v3sria---" }, source: "glaux"), "pos_code is CEIPoM-scoped"
    end

    # The positional tag is lossy where the explicit Case/Gender columns are
    # not: locative/instrumental (slot 8 "-": Oscan okreí⁝ "n-s---m--"
    # case LOC) and the syncretic genders (manom "a-s---ma-" gender M/N —
    # the tag writes only the first) and case pairs. A fully decodable
    # explicit column refines the tag's case/gender; "?" and the odd
    # stray value ("da", "ABL?") leave the tag's reading alone.
    def test_ceipom_explicit_case_and_gender_refine_the_tag
      okrei = { "form" => "okreí⁝", "pos_code" => "n-s---m--", "case" => "LOC", "gender" => "M" }
      assert_equal({ "number" => "sing", "gender" => "masc", "case" => "loc" }, MF.features(okrei, source: "ceipom"))
      assert_equal "ins", MF.features({ "pos_code" => "n-s---f--", "case" => "INS", "gender" => "F" },
                                      source: "ceipom")["case"]
      manom = { "form" => "manom", "pos_code" => "a-s---ma-", "case" => "ACC", "gender" => "M/N" }
      assert_equal({ "number" => "sing", "case" => "acc" }, MF.features(manom, source: "ceipom"))
      assert MF.match?(manom, MF.parse("gender=neut,case=acc"), source: "ceipom")
      assert MF.match?(manom, MF.parse("gender=masc"), source: "ceipom")
      refute MF.match?(manom, MF.parse("gender=fem"), source: "ceipom")
      pair = { "pos_code" => "n-s---fa-", "case" => "ACC/DAT", "gender" => "F" }
      assert MF.match?(pair, MF.parse("case=dat"), source: "ceipom")
      unsure = { "pos_code" => "n-s---fb-", "case" => "ABL?", "gender" => "?" }
      assert_equal({ "number" => "sing", "gender" => "fem", "case" => "abl" }, MF.features(unsure, source: "ceipom"))
    end

    # The 12 multi-analysis tokens keep upstream's other analyses under
    # "alternatives"; those can be OTHER lexemes (cei/p() — capio, or
    # cippus), and the lemma anchor reads only the first analysis's
    # Latin equivalent, so only the first analysis decodes.
    def test_ceipom_decodes_the_first_analysis_only
      ceip = { "form" => "cei/p()", "pos_code" => "v3sria---", "latin_equivalent" => "capio",
               "alternatives" => [{ "latin_equivalent" => "cippus", "pos_code" => "n-p---ma-", "case" => "ACC" }] }
      refute MF.match?(ceip, MF.parse("case=acc"), source: "ceipom")
      assert MF.match?(ceip, MF.parse("tense=perf"), source: "ceipom")
    end

    # -- HeliPaD (Penn-psd pos + "^" morph) ------------------------------------

    # Real HeliPaD tokens (test/fixtures/helipad + deposit-censused tags):
    # the "^" morph atoms are case/person/number; the verb tag's suffix is
    # tense + mood (the YCOE family convention: P/D present/past, I/S
    # indicative/subjunctive, bare head = infinitive, head+I = imperative);
    # GE+/NEG+ prefixes ride along.
    def test_helipad_morph_atoms_and_verb_tags
      hp = "helipad"
      assert_equal({ "case" => "acc", "number" => "sing" },
                   MF.features({ "form" => "uuord", "lemma" => "word", "pos" => "N", "morph" => "A^SG" }, source: hp))
      assert_equal({ "case" => "acc", "person" => "3", "number" => "plur" },
                   MF.features({ "form" => "sia", "lemma" => "he", "pos" => "PRO", "morph" => "A^3^PL" }, source: hp))
      assert_equal({ "tense" => "past", "mood" => "ind", "person" => "3", "number" => "plur" },
                   MF.features({ "form" => "bigunnun", "pos" => "VBDI", "morph" => "3^PL" }, source: hp))
      assert_equal({ "tense" => "past", "mood" => "ind", "person" => "3", "number" => "sing" },
                   MF.features({ "form" => "gespon", "pos" => "GE+VBDI", "morph" => "3^SG" }, source: hp))
      assert_equal({ "tense" => "pres", "mood" => "sub", "person" => "3", "number" => "sing" },
                   MF.features({ "pos" => "MDPS", "morph" => "3^SG" }, source: hp))
      assert_equal({ "tense" => "pres", "mood" => "ind" }, MF.features({ "pos" => "NEG+BEPI" }, source: hp))
      assert_equal({ "mood" => "inf" }, MF.features({ "form" => "uuisean", "pos" => "VB" }, source: hp))
      assert_equal({ "mood" => "imp", "person" => "2", "number" => "sing" },
                   MF.features({ "form" => "lat", "pos" => "VBI", "morph" => "2^SG" }, source: hp))
      assert_equal({ "mood" => "part", "case" => "nom", "number" => "plur" },
                   MF.features({ "form" => "cumana", "pos" => "VNI", "morph" => "N^PL" }, source: hp),
                   "VGI/VNI are inflected participles, not imperatives")
      assert_equal({ "mood" => "part" }, MF.features({ "form" => "giboran", "pos" => "GE+VN" }, source: hp))
      assert_equal({ "case" => "ins", "number" => "sing" },
                   MF.features({ "pos" => "N", "morph" => "I^SG" }, source: hp))
      assert_equal({ "case" => "nom", "person" => "1", "number" => "dual" },
                   MF.features({ "pos" => "PRO", "morph" => "N^1^DU" }, source: hp))
    end

    # Degree rides the adjective/adverb/quantifier tag (R comparative, S
    # superlative); unmarked positives decode nothing. Stray atoms (SGL,
    # SPL, RFL, 3PL — 5 tags deposit-wide) and tags fixing nothing are
    # skipped; G^D^SG (one token) is a genitive|dative alternative.
    def test_helipad_degree_and_residue
      hp = "helipad"
      assert_equal({ "degree" => "cmp", "case" => "nom", "number" => "sing" },
                   MF.features({ "pos" => "ADJR", "morph" => "N^SG" }, source: hp))
      assert_equal({ "degree" => "sup" }, MF.features({ "pos" => "ADVS" }, source: hp))
      assert_equal({ "degree" => "cmp" }, MF.features({ "pos" => "QR" }, source: hp))
      assert_equal({ "case" => "dat" }, MF.features({ "pos" => "N", "morph" => "D^SGL" }, source: hp))
      assert_equal({ "case" => "acc" }, MF.features({ "pos" => "PRO", "morph" => "A^3PL" }, source: hp))
      assert_empty MF.features({ "form" => "endi", "pos" => "CONJ" }, source: hp)
      assert_empty MF.features({ "pos" => "RN" }, source: hp)
      gd = { "pos" => "N", "morph" => "G^D^SG" }
      assert MF.match?(gd, MF.parse("case=gen"), source: hp)
      assert MF.match?(gd, MF.parse("case=dat"), source: hp)
      assert_empty MF.features({ "pos" => "VBDI", "morph" => "3^SG" }, source: "ycoe"), "HeliPaD-scoped"
    end

    # -- CorPH analysis ----------------------------------------------------------

    # Real CorPH tokens (test/fixtures/corph + deposit-censused analyses):
    # "."-joined self-describing atoms; person+number fuse ("3sg"); a
    # "/"-led segment continues the previous one as an alternative.
    def test_corph_nominal_and_verbal_analyses
      ch = "corph"
      assert_equal({ "case" => "gen", "number" => "sing", "gender" => "masc" },
                   MF.features({ "form" => "loigde", "lemma" => "Lóegdae", "analysis" => "gen.sg.masc." }, source: ch))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "fut" },
                   MF.features({ "form" => "íbth", "lemma" => "ibid", "analysis" => "3sg.fut." }, source: ch))
      assert_equal({ "person" => "3", "number" => "plur", "tense" => "pres", "mood" => "sub", "voice" => "pass" },
                   MF.features({ "form" => "asa·mesatar", "analysis" => "3pl.pres.subj.pass." }, source: ch))
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "past" },
                   MF.features({ "analysis" => "augm.3sg.pret." }, source: ch), "augm is skipped")
      assert_equal({ "person" => "3", "number" => "sing", "tense" => "past", "mood" => "sub" },
                   MF.features({ "analysis" => "3sg.past.subj." }, source: ch))
      assert_equal({ "person" => "2", "number" => "sing", "mood" => "imp" },
                   MF.features({ "analysis" => "2sg.impv." }, source: ch))
      assert_equal({ "person" => "3", "number" => "sing", "mood" => "cnd" },
                   MF.features({ "lemma" => "ad·tá", "analysis" => "3sg.cond." }, source: ch))
      assert_equal({ "person" => "3", "number" => "sing", "aspect" => "hab" },
                   MF.features({ "lemma" => "ad·tá", "analysis" => "3sg.hab." }, source: ch))
      assert_equal({ "degree" => "cmp" }, MF.features({ "lemma" => "mór", "analysis" => "comp." }, source: ch))
      assert_equal({ "degree" => "equ" }, MF.features({ "analysis" => "equ." }, source: ch))
      assert_equal({ "mood" => "inf", "tense" => "pres", "voice" => "pass" },
                   MF.features({ "analysis" => "pres.inf.pass." }, source: ch))
    end

    # Alternatives within a segment; a CASE is decoded only beside a
    # separate number atom — a bare case ("dat.", "dat./acc.") is the case a
    # PREPOSITION governs (do, i, ó, di …), and a fused person-number + case
    # is a conjugated preposition (dó "to him") whose case is governed too.
    def test_corph_alternatives_and_governed_case
      ch = "corph"
      nom = { "analysis" => "nom.sg.masc./fem." }
      assert MF.match?(nom, MF.parse("gender=fem,case=nom"), source: ch)
      assert MF.match?(nom, MF.parse("gender=masc"), source: ch)
      assert_equal({ "case" => "nom", "number" => "sing" }, MF.features(nom, source: ch))
      assert MF.match?({ "analysis" => "dat./acc.sg." }, MF.parse("case=acc,number=sg"), source: ch)
      assert_empty MF.features({ "form" => "co", "lemma" => "co", "analysis" => "dat." }, source: ch)
      assert_empty MF.features({ "lemma" => "i", "analysis" => "dat./acc." }, source: ch)
      fuiri = { "form" => "fuiri", "lemma" => "for", "analysis" => "3sg.fem.dat." }
      assert_equal({ "person" => "3", "number" => "sing", "gender" => "fem" }, MF.features(fuiri, source: ch))
      do_him = { "lemma" => "do", "analysis" => "3sg.masc./neut.dat." }
      assert MF.match?(do_him, MF.parse("gender=neut,person=3"), source: ch)
      refute MF.match?(do_him, MF.parse("case=dat"), source: ch)
    end

    # Undecodable residue: upstream-uncertain analyses ("(?)", "?"), a
    # segment whose alternatives span categories ("acc.sg./gen.pl." — two
    # whole readings run together), the secondary-future modifier, and the
    # infixed-pronoun classes A/B/C and compos./rel./augm. flags.
    def test_corph_residue_decodes_nothing
      ch = "corph"
      ["dat.sg.(?)", "gen.pl.masc./fem.(?)", "?", "acc.sg./gen.pl.", "3sg.sec.fut.pass.", "A", "B", "C",
       "compos.", "len.rel.", "sub.conj."].each do |analysis|
        assert_empty MF.features({ "analysis" => analysis }, source: ch), analysis
      end
      assert_empty MF.features({ "analysis" => "gen.sg." }, source: "aoxml"), "CorPH-scoped"
    end

    # -- AES explicit features ---------------------------------------------------

    # Real AES tokens (test/fixtures/aes + deposit-censused values): the
    # fine morphology rides verbatim under upstream's own names (numerus,
    # genus, status, pronoun, inflection, voice, number).
    def test_aes_explicit_features
      aes = "aes"
      thnt = { "form" => "[ṯḥ]n,t", "lemma" => "ṯḥn.t", "pos" => "substantive", "numerus" => "singular",
               "genus" => "feminine", "status" => "st_absolutus" }
      assert_equal({ "number" => "sing", "gender" => "fem", "state" => "abs" }, MF.features(thnt, source: aes))
      rn = { "form" => "rn", "lemma" => "rn", "pos" => "substantive", "numerus" => "singular",
             "status" => "st_pronominalis" }
      assert_equal({ "number" => "sing", "state" => "pron" }, MF.features(rn, source: aes))
      assert_equal "cons", MF.features({ "form" => "ẖ,t", "lemma" => "ẖ.t", "numerus" => "singular",
                                         "status" => "st_constructus" }, source: aes)["state"]
      assert_equal({ "verbform" => "fin", "voice" => "act" },
                   MF.features({ "form" => "ḏd", "pos" => "verb", "inflection" => "suffixConjugation",
                                 "voice" => "active" }, source: aes))
      assert_equal({ "mood" => "inf" }, MF.features({ "form" => "sḏm", "inflection" => "infinitive" }, source: aes))
      assert_equal({ "number" => "sing", "gender" => "masc", "mood" => "part", "voice" => "act" },
                   MF.features({ "form" => "pri̯", "numerus" => "singular", "genus" => "masculine",
                                 "inflection" => "participle", "voice" => "active" }, source: aes))
      assert_equal({ "mood" => "imp", "number" => "sing" },
                   MF.features({ "form" => "⸢dwꜣ⸣", "lemma" => "dwꜣ", "inflection" => "imperative",
                                 "numerus" => "singular" }, source: aes))
      assert_equal({ "prontype" => "dem" },
                   MF.features({ "form" => "pꜣ", "lemma" => "pꜣ", "pronoun" => "demonstrative_pronoun" }, source: aes))
      assert_equal({ "numtype" => "card" }, MF.features({ "form" => "⸢13⸣", "number" => "cardinal" }, source: aes))
      assert_equal({ "numtype" => "ord" }, MF.features({ "form" => "mḥ-3", "number" => "ordinal" }, source: aes))
      assert_equal({ "gender" => "com", "number" => "sing" },
                   MF.features({ "form" => "ḥmsi̯.k", "genus" => "commonGender", "inflection" => "pseudoParticiple",
                                 "numerus" => "singular" }, source: aes))
    end

    # AES's "morphology" holds Egyptian verb-morpheme labels (n-morpheme,
    # t-morpheme, geminated …) — never a PROIEL positional tag: the
    # AES-scoped row decides before the unscoped `morphology` row could
    # read "n-morpheme" as mood=opt. The Egyptian-specific forms
    # (pseudoParticiple, relativeform), the lexical subtype leaking into
    # numerus (substantive_masc/fem) and verbalClass decode nothing; the
    # agreement those forms carry still does.
    def test_aes_morpheme_labels_are_never_proiel_tags
      aes = "aes"
      samn = { "form" => "sḏm.n", "pos" => "verb", "inflection" => "suffixConjugation", "voice" => "active",
               "morphology" => "n-morpheme" }
      assert_equal({ "verbform" => "fin", "voice" => "act" }, MF.features(samn, source: aes))
      refute MF.match?(samn, MF.parse("mood=opt"), source: aes)
      assert_equal({ "mood" => "inf" },
                   MF.features({ "form" => "mꜣꜣ", "inflection" => "infinitive", "morphology" => "geminated" },
                               source: aes))
      assert_equal({ "number" => "sing", "gender" => "masc" },
                   MF.features({ "form" => "kꜣꜣ.n", "numerus" => "singular", "genus" => "masculine",
                                 "inflection" => "relativeform" }, source: aes))
      assert_empty MF.features({ "form" => "zꜣw.tj", "inflection" => "pseudoParticiple" }, source: aes)
      assert_empty MF.features({ "form" => "ꜥnḫ", "pos" => "substantive", "numerus" => "substantive_masc" },
                               source: aes)
      assert_equal "ind", MF.features({ "morphology" => "-p-i------" })["mood"], "other sources: PROIEL as before"
    end

    # -- TraCES explicit features ------------------------------------------------

    # Real TraCES tokens (test/fixtures/traces + deposit-censused values):
    # one upstream feature per category, Gǝʿǝz verbs under the Semitic
    # keys (Perfect/Imperfect → conjugation perf/impf, never a Greek tense).
    def test_traces_verbs_pronouns_and_suffixes
      tr = "traces"
      motat = { "form" => "motat", "pos" => "Verb", "tam" => "Perfect", "person" => "Third", "gender" => "Feminine",
                "number" => "Singular", "lemma" => "ሞተ" }
      assert_equal({ "conjugation" => "perf", "person" => "3", "gender" => "fem", "number" => "sing" },
                   MF.features(motat, source: tr))
      ana = { "form" => "ʾana", "pos" => "Independent Personal Pronoun", "person" => "First", "gender" => "Communis",
              "number" => "Singular", "case" => "Nominative" }
      assert_equal({ "person" => "1", "gender" => "com", "number" => "sing", "case" => "nom" },
                   MF.features(ana, source: tr))
      assert_equal({ "person" => "3", "gender" => "masc", "number" => "plur" },
                   MF.features({ "form" => "ama", "pos" => "Pronominal Suffix", "person" => "Third",
                                 "gender" => "Masculine", "number" => "Plural" }, source: tr))
      assert_equal({ "conjugation" => "impf" },
                   MF.features({ "form" => "yǝbl", "pos" => "Verb", "tam" => "Imperfect" }, source: tr))
      [%w[yǝkun Subjunctive sub], %w[yǝkun subjunctive sub], %w[hab Imperative imp], %w[kawina Infinitive inf],
       %w[samiʿo Gerund ger]].each do |form, tam, mood|
        verb = { "form" => form, "pos" => "Verb", "tam" => tam }
        assert_equal({ "mood" => mood }, MF.features(verb, source: tr), tam)
      end
      assert_equal({ "conjugation" => "perf" },
                   MF.features({ "form" => "baṣḥa", "pos" => "Verb", "tamp" => "Perfect" }, source: tr),
                   "tamp/temp are upstream misspellings of the tam feature name")
    end

    # Nouns and proper names carry LAYERED number/gender ("SingularP
    # UnmarkedS", "masculineNP") whose layers the held export does not
    # define — undecoded, as are "unmarked" and the prepositions' "Nominal
    # state"; case and the other states decode.
    def test_traces_layered_noun_values_stay_undecoded
      tr = "traces"
      sama = { "form" => "sǝma", "pos" => "Common Noun", "gender" => "unmarked", "number" => "SingularP UnmarkedS",
               "case" => "Nominative", "state" => "Construct state" }
      assert_equal({ "case" => "nom", "state" => "cons" }, MF.features(sama, source: tr))
      harif = { "form" => "ḫarif", "pos" => "Common Noun", "gender" => "unmarked", "number" => "SingularP UnmarkedS",
                "case" => "Nominative", "state" => "Pronominal state" }
      assert_equal({ "case" => "nom", "state" => "pron" }, MF.features(harif, source: tr))
      qaddusa = { "form" => "qaddusa", "pos" => "Common Noun", "gender" => "masculineP", "number" => "SingularP" }
      assert_empty MF.features(qaddusa, source: tr)
      assert_equal "acc", MF.features({ "form" => "zanta", "case" => "Accusative" }, source: tr)["case"]
      assert_equal "voc", MF.features({ "form" => "ʾǝgziʾo", "case" => "Vocative" }, source: tr)["case"]
      assert_equal({ "state" => "abs" }, MF.features({ "form" => "śarq", "state" => "Absolute state" }, source: tr))
      assert_empty MF.features({ "form" => "ba", "pos" => "Preposition", "state" => "Nominal state" }, source: tr)
      assert_empty MF.features({ "form" => "motat", "tam" => "Perfect" }, source: "aes"), "TraCES-scoped"
    end

    # -- TLA glossing (tla-hf) ---------------------------------------------------

    # Real tla-hf tokens (test/fixtures/tla-hf + deposit-censused labels):
    # the "gloss" is the TLA's GRAMMATICAL glossing (Leipzig-style labels),
    # decoded atom by atom. A head-less person label is a personal pronoun.
    def test_tla_glossing_labels
      tla = "tla-hf"
      assert_equal({ "person" => "3", "number" => "sing", "gender" => "masc", "prontype" => "prs" },
                   MF.features({ "form" => "=f", "upos" => "PRON", "gloss" => "-3sg.m" }, source: tla))
      assert_equal({ "person" => "3", "number" => "sing", "gender" => "com", "prontype" => "prs" },
                   MF.features({ "form" => "s", "upos" => "PRON", "gloss" => "=3sg.c" }, source: tla))
      assert_equal({ "gender" => "masc", "number" => "plur" },
                   MF.features({ "form" => "kꜣ(.PL)", "upos" => "NOUN", "gloss" => "N.m:pl" }, source: tla))
      assert_equal({ "number" => "sing", "state" => "pron" },
                   MF.features({ "form" => "ḥꜣ.tꞽ", "upos" => "NOUN", "gloss" => "N:sg:stpr" }, source: tla))
      assert_equal({ "state" => "pron" }, MF.features({ "form" => "r", "gloss" => "PREP:stpr" }, source: tla))
      assert_equal({ "voice" => "pass" }, MF.features({ "form" => "nḏ", "gloss" => "V\\tam.pass" }, source: tla))
      assert_equal({ "mood" => "imp", "number" => "sing" },
                   MF.features({ "form" => "ꜥḥꜥ", "gloss" => "V\\imp.sg" }, source: tla))
      assert_equal({ "mood" => "inf" }, MF.features({ "form" => "šmi̯.t", "gloss" => "V\\inf" }, source: tla))
      assert_equal({ "person" => "3", "number" => "sing", "gender" => "masc" },
                   MF.features({ "form" => "ḥwꜣ", "gloss" => "V\\res-3sg.m" }, source: tla),
                   "a verb's agreement ending, not a pronoun")
      assert_equal({ "mood" => "part", "voice" => "act", "gender" => "masc", "number" => "sing" },
                   MF.features({ "gloss" => "V\\ptcp.act.m.sg" }, source: tla))
      assert_equal({ "prontype" => "art", "gender" => "masc", "number" => "sing" },
                   MF.features({ "form" => "pꜣ", "gloss" => "art:m.sg" }, source: tla))
      assert_equal({ "prontype" => "art", "poss" => "yes", "gender" => "fem", "number" => "sing" },
                   MF.features({ "form" => "tꜣy", "gloss" => "ART.poss:f.sg" }, source: tla))
      assert_equal({ "prontype" => "dem", "gender" => "masc", "number" => "sing" },
                   MF.features({ "gloss" => "dem.m.sg" }, source: tla))
      assert_equal({ "prontype" => "rel", "gender" => "masc", "number" => "sing" },
                   MF.features({ "gloss" => "REL:m.sg" }, source: tla))
      assert_equal({ "numtype" => "ord", "gender" => "masc", "number" => "sing" },
                   MF.features({ "gloss" => "NUM.ord:m.sg" }, source: tla))
      assert_equal({ "number" => "dual", "state" => "cons", "gender" => "fem" },
                   MF.features({ "gloss" => "N.f:du:stc" }, source: tla))
    end

    # The possessive article's "-1sg" is the POSSESSOR, not the article's
    # own person/number (ART.poss:pl-1sg — a plural article, "my"); flags
    # with no facet (tam, ant, res, adjz, gen — the genitival adjective,
    # never the genitive case) and the head-only/undefined labels decode
    # nothing beyond their real atoms.
    def test_tla_glossing_possessor_and_flags
      tla = "tla-hf"
      assert_equal({ "prontype" => "art", "poss" => "yes", "number" => "plur" },
                   MF.features({ "gloss" => "ART.poss:pl-1sg" }, source: tla))
      assert_equal({ "gender" => "masc", "number" => "sing" },
                   MF.features({ "gloss" => "PREP-adjz:m.sg" }, source: tla))
      assert_equal({ "voice" => "act", "state" => "pron" },
                   MF.features({ "gloss" => "V\\tam.act-ant:stpr" }, source: tla))
      %w[V N PREP PTCL gen (undefined) PERSN TITL V(unclear) Q].each do |label|
        assert_empty MF.features({ "gloss" => label }, source: tla), label
      end
      assert_empty MF.features({ "gloss" => "-3sg.m" }, source: "aes"), "tla-hf-scoped"
    end
  end
end
