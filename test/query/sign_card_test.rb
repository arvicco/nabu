# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::SignCard (P65-1): the cuneiform sign desk card — one sign
  # in (glyph, name, or value spelling), the full held identity out: name /
  # uname / codepoints, the @list print concordances (MZL/LAK/HZL/…),
  # values by %lang, the CDLI meaning glosses, variant forms, the form_of
  # parent. NO new source: everything re-joins the held OSL (CC0) + the
  # cdli_sign_readings.tsv riding in its 00etc. The `nabu char` honesty
  # rule binds here too: an absent shelf (no readings file, no fulltext)
  # yields an absent section, never "—". Ambiguous value input lists ALL
  # candidates, never one silently (the `nabu signs` contract).
  class SignCardTest < Minitest::Test
    SIGN_LIST = Nabu::SignList.load(File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl"))
    READINGS = Nabu::CdliSignReadings.load(
      File.join(Nabu::TestSupport.fixtures("osl"), "00etc", "cdli_sign_readings.tsv")
    )

    def card_for(input, readings: READINGS)
      Nabu::Query::SignCard.new(sign_list: SIGN_LIST, readings: readings).run(input)
    end

    # -- the three input lanes -----------------------------------------------

    def test_a_glyph_resolves_to_its_sign_card
      result = card_for("𒋀")
      card = result.card
      assert_equal "ŠEŠ", card.name
      assert_equal "CUNEIFORM SIGN SHESH", card.uname
      assert_equal ["U+122C0"], card.codepoints
      assert_equal "𒋀", card.glyph
      assert_equal "o0002834", card.oid
      refute card.deprecated
      assert_empty card.corpus, "no fulltext handle → the corpus panel is absent, never \"—\""
    end

    def test_a_name_resolves_folded_or_not
      assert_equal "ŠEŠ", card_for("ŠEŠ").card.name
      assert_equal "ŠEŠ", card_for("SZESZ").card.name, "C-ATF ASCII names fold on the way in"
      assert_equal "|ŠEŠ.AB|", card_for("|SZESZ.AB|").card.name
    end

    def test_a_value_resolves_folded_through_the_sign_list
      result = card_for("uri5")
      assert_equal "|ŠEŠ.AB|", result.card.name
      assert_equal %w[U+122C0 U+1200A], result.card.codepoints
    end

    # -- the card sections ---------------------------------------------------

    def test_list_concordances_group_by_list_and_exclude_the_unicode_entry
      lists = card_for("ŠEŠ").card.lists
      assert_equal ["535"], lists["MZL"]
      assert_equal ["079"], lists["HZL"]
      assert_equal ["032"], lists["LAK"]
      assert_equal ["331"], lists["SLLHA"]
      refute lists.key?("U"), "the @list U+122C0 codepoint line is identity, not a concordance"
    end

    def test_values_carry_language_qualifiers_and_deprecation
      values = card_for("|AN.SAG@g|").card.values
      akk = values.find { |v| v.value == "ṣillu" }
      assert_equal "akk", akk.language
      deprecated = card_for("AK").card.values.find { |v| v.value == "aŋ" }
      assert deprecated.deprecated, "@v- values stay on the card, marked — texts using them exist"
    end

    def test_the_cdli_glosses_section_joins_by_sign_name
      glosses = card_for("ŠEŠ").card.glosses
      assert_equal "n. brother", glosses.find { |g| g.reading == "šeš" }.meaning
      assert_empty card_for("ŠEŠ", readings: nil).card.glosses,
                   "no readings shelf → absent section, never an error"
    end

    def test_forms_ride_the_parent_card_and_a_form_names_its_parent
      card = card_for("|ŠEŠ.KI|").card
      assert_includes card.forms.map(&:name), "|ŠEŠ.NA|"
      form_result = card_for("|ŠEŠ.NA|")
      assert_equal "|ŠEŠ.NA|", form_result.card.name
      assert_equal "|ŠEŠ.KI|", form_result.card.parent, "a form card names its owning sign"
    end

    # -- the list-number lane (P65 gate feedback №1) -------------------------

    def test_a_qualified_list_number_is_a_deterministic_card
      assert_equal "ŠEŠ", card_for("MZL535").card.name
      assert_equal "AK", card_for("MZL127").card.name
    end

    def test_a_bare_list_number_unique_across_lists_is_still_one_card
      assert_equal "ŠEŠ", card_for("32").card.name,
                   "32 matches ŠEŠ twice (LAK032, KWU032) — one sign, one card"
    end

    def test_a_bare_list_number_shared_by_signs_lists_candidates_with_via
      result = card_for("70")
      assert_nil result.card
      assert_equal [%w[AK ASY070], ["|IGI.DIB|", "RSP070"]],
                   result.candidates.map { |c| [c.name, c.via] },
                   "each candidate names WHICH list token matched"
    end

    def test_the_json_candidates_carry_via_present_only
      payload = Nabu::Query::SignCard.json_payload(card_for("70"))
      assert_equal "ASY070", payload["candidates"].first["via"]
      ambiguous = Nabu::Query::SignCard.json_payload(card_for("idₓ"))
      refute ambiguous["candidates"].first.key?("via"), "via is present-only — value lanes have none"
    end

    # -- the ASCII-x subscript fold (P65 gate feedback №2) -------------------

    def test_a_trailing_ascii_x_folds_to_the_subscript_on_miss
      result = card_for("idx")
      assert_equal ["|A.BARA₂|", "|UD.ŠEŠ.KI|"], result.candidates.map(&:name),
                   "idx reaches idₓ's candidates (two in the fixture, six upstream)"
      assert_equal "ŠEŠ", card_for("zax").card.name, "zax → zaₓ"
    end

    # -- ambiguity + unknown -------------------------------------------------

    def test_an_ambiguous_value_lists_all_candidates_never_one_silently
      result = card_for("idₓ")
      assert_nil result.card
      assert_equal ["|A.BARA₂|", "|UD.ŠEŠ.KI|"], result.candidates.map(&:name)
    end

    def test_unknown_input_is_an_empty_result
      result = card_for("no-such-sign")
      assert_nil result.card
      assert_empty result.candidates
    end

    # -- the frozen JSON contract (Edubba consumes) --------------------------

    def test_the_json_payload_names_the_sign_and_its_sections
      payload = Nabu::Query::SignCard.json_payload(card_for("𒋀"))
      card = payload["card"]
      assert_equal "ŠEŠ", card["name"]
      assert_equal ["U+122C0"], card["codepoints"]
      assert_equal ["535"], card["lists"]["MZL"]
      plain = card["values"].find { |v| v["value"] == "šeš" }
      refute plain.key?("language"), "language/deprecated are present-only keys"
      gloss = card["glosses"].find { |g| g["reading"] == "šeš" }
      assert_equal "n. brother", gloss["meaning"]
      assert_equal [], payload["candidates"]
    end

    def test_the_json_payload_of_an_ambiguous_input_carries_candidates_only
      payload = Nabu::Query::SignCard.json_payload(card_for("idₓ"))
      assert_nil payload["card"]
      names = payload["candidates"].map { |c| c["name"] }
      assert_equal ["|A.BARA₂|", "|UD.ŠEŠ.KI|"], names
    end
  end
end
