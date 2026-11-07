# frozen_string_literal: true

require "test_helper"

# Nabu::GlossLines — the gloss-lines lane's extraction contract: a
# passage's upstream token glosses read in token order, each folded by
# its GLOSS language (declared per source in Query::TokenGlosses), never
# by the passage's own.
class GlossLinesTest < Minitest::Test
  GL = Nabu::GlossLines
  TG = Nabu::Query::TokenGlosses

  # The declaration law: the lane's sources are EXACTLY the token-gloss
  # registry's (one declaration, two lanes), each with a declared gloss
  # language — never sniffed from the data.
  def test_the_lane_reads_the_token_gloss_declarations
    assert_equal TG.sources, GL.slugs
    assert_equal({ "bhsa" => "en", "aes" => "de", "achemenet" => "en", "tlhdig" => "de", "ceipom" => "en" },
                 GL.slugs.to_h { |slug| [slug, GL.language(slug)] })
    assert GL.registered?("bhsa")
    refute GL.registered?("tla-hf"), "grammatical Leipzig labels are not a gloss line"
    assert GL.registered?("ceipom"), "the equivalence tier's meanings are wired as English glosses"
    assert_equal %w[en de], GL.languages
  end

  def test_entries_are_the_glossed_tokens_in_token_order
    annotations = { "tokens" => [
      { "form" => "לַמֶּ֖לֶךְ", "gloss" => "king" },
      { "form" => "x" },
      { "form" => "y", "gloss" => "  " },
      { "form" => "מַלְכָּא", "gloss" => " to eternity " },
      "not a token"
    ] }

    assert_equal [[0, "לַמֶּ֖לֶךְ", "king"], [3, "מַלְכָּא", "to eternity"]], GL.entries(annotations, "bhsa")
    assert_equal GL.entries(annotations, "bhsa"), GL.entries(JSON.generate(annotations), "bhsa"),
                 "the stored JSON string reads the same"
    assert_equal "king to eternity", GL.line(GL.entries(annotations, "bhsa"))
  end

  def test_entries_read_each_sources_own_key_only
    annotations = { "tokens" => [{ "form" => "šarru", "eng" => "king", "gloss" => "N" }] }

    assert_equal [[0, "šarru", "king"]], GL.entries(annotations, "achemenet")
    assert_empty GL.entries(annotations, "perseus"), "an unregistered source has no gloss line"
    assert_empty GL.entries({ "tokens" => "nope" }, "bhsa")
    assert_empty GL.entries('{"lemma":"x"}', "bhsa"), "no key, no parse"
    assert_empty GL.entries(nil, "bhsa")
  end

  # The fold law: the gloss folds by its OWN declared language. The
  # achemenet passage is Akkadian, whose fold opens sign-join hyphens to
  # spaces — a gloss is English and must not take that fold.
  def test_a_gloss_folds_by_its_declared_language_never_the_passage_language
    assert_equal Nabu::Normalize.search_form("Son-in-law", language: "en"), GL.fold("Son-in-law", "achemenet")
    refute_equal Nabu::Normalize.search_form("Son-in-law", language: "akk"), GL.fold("Son-in-law", "achemenet")
    assert_equal "konig von ober- und unteragypten", GL.fold("König von Ober- und Unterägypten", "aes")
  end

  # The query side folds once per declared gloss language (the union —
  # the cannot-miss argument at the gloss grain).
  def test_query_forms_are_the_union_over_the_declared_gloss_languages
    assert_equal ["konig"], GL.query_forms("König")
    assert_equal(GL.languages.map { |code| Nabu::Normalize.search_form("Ḥorus", language: code) }.uniq,
                 GL.query_forms("Ḥorus"))
  end
end
