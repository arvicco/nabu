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
    end
  end
end
