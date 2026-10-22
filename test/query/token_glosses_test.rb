# frozen_string_literal: true

require "test_helper"
require "nabu/query/token_glosses"

module Query
  # Nabu::Query::TokenGlosses — the morph façade's sibling for upstream
  # token-level LEXICAL glosses: a per-source field registry, the gloss read
  # off a token, and a whole-word, case-insensitive gloss matcher. Token
  # shapes and glosses are the real fixture tokens.
  class TokenGlossesTest < Minitest::Test
    TG = Nabu::Query::TokenGlosses

    def test_registry_names_each_sources_gloss_field
      assert_equal %w[achemenet aes bhsa tlhdig], TG::FIELDS.keys.sort
      assert_equal "gloss", TG::FIELDS.fetch("bhsa").key
      assert_equal "eng", TG::FIELDS.fetch("achemenet").key
      assert_equal "de", TG::FIELDS.fetch("aes").language
    end

    def test_gloss_reads_the_registered_field_only
      bhsa = { "form" => "מֶּ֖לֶךְ", "lex_utf8" => "מלך", "gloss" => "king" }
      assert_equal "king", TG.gloss(bhsa, source: "bhsa")
      achemenet = { "form" => "A-ŠA₃", "lemma" => "eqlu", "eng" => "field" }
      assert_equal "field", TG.gloss(achemenet, source: "achemenet")
      assert_nil TG.gloss(bhsa, source: "oshb"), "an unregistered source has no gloss layer"
      assert_nil TG.gloss(bhsa, source: nil)
      assert_nil TG.gloss({ "gloss" => "  " }, source: "bhsa"), "blank is absence"
      assert_nil TG.gloss("not a token", source: "bhsa")
    end

    # tla-hf's "gloss" is GRAMMATICAL (Leipzig labels: 259 distinct values —
    # PREP, N.m, -3sg.m …), not a word meaning: never a lexical gloss.
    def test_grammatical_glosses_are_not_registered
      refute TG::FIELDS.key?("tla-hf")
      assert_nil TG.gloss({ "lemma" => "m", "upos" => "ADP", "gloss" => "PREP" }, source: "tla-hf")
    end

    def test_match_is_whole_word_and_case_insensitive
      matcher = TG.matcher("Fayence")
      aes = { "lemma" => "ṯḥn.t", "gloss" => "Fayence; Glas (aus Silicium)" }
      assert TG.match?(aes, matcher, source: "aes")
      assert TG.match?(aes, TG.matcher("glas"), source: "aes")
      refute TG.match?(aes, TG.matcher("Fay"), source: "aes"), "whole words, not substrings"
      assert TG.match?({ "lemma" => "weritišk", "gloss" => "sich ängstigen" }, TG.matcher("ÄNGSTIGEN"),
                       source: "tlhdig")
      assert TG.match?({ "lemma" => "קדם", "gloss" => "be in front" }, TG.matcher("in front"), source: "bhsa")
      refute TG.match?({ "lex_utf8" => "דבר", "gloss" => "word" }, TG.matcher("speak"), source: "bhsa")
    end

    def test_blank_query_is_an_error
      assert_raises(TG::Error) { TG.matcher("  ") }
      assert_raises(TG::Error) { TG.matcher(nil) }
    end
  end
end
