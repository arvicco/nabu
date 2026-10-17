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

    # The decoder seam: an explicit ordered table, token key → decode method.
    def test_decoder_table_is_explicit_and_ordered
      assert_equal %w[morphology feats postag], MF::DECODERS.map(&:first)
      MF::DECODERS.map(&:last).each do |method|
        assert MF.respond_to?(method), "#{method} is a module function"
      end
    end
  end
end
