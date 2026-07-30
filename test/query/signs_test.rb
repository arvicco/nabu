# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Signs (P53-2): ATF transliteration → sign identities through
  # the P53-1 SignList seam, with the frozen per-token status vocabulary
  # (deterministic / qualified / ambiguous / no-codepoint / broken / unknown)
  # and the frozen JSON contract the Edubba downstream consumes. Resolution
  # tests run against the REAL osl fixture; URN-mode tests load a REAL cdli /
  # etcsl fixture document through the production Loader.
  class SignsTest < Minitest::Test
    include StoreTestDB

    SIGN_LIST = Nabu::SignList.load(File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl"))

    def signs(catalog: nil)
      Nabu::Query::Signs.new(sign_list: SIGN_LIST, catalog: catalog)
    end

    def first_token(text, language: nil, dialect: :catf)
      result = signs.run_text(text, language: language, dialect: dialect)
      result.lines.first.tokens.first
    end

    # -- the kunga₃ incident (owner, 2026-07-29): a value living on a variant
    # form must NAME the owning sign, or same-named candidates render as
    # inexplicable twins. form_of is nil for top-level signs, present-only in
    # the JSON contract (the determinative precedent).
    def test_a_form_borne_value_names_its_owning_sign
      token = first_token("nannax(|ŠEŠ.NA|)")
      assert_equal "|ŠEŠ.NA|", token.sign_name
      assert_equal "|ŠEŠ.KI|", token.form_of, "the form candidate names its parent sign"

      json = Nabu::Query::Signs.json_payload(signs.run_text("nannax(|ŠEŠ.NA|)"))
      record = json["lines"].first["tokens"].first
      assert_equal "|ŠEŠ.KI|", record["form_of"]

      plain = Nabu::Query::Signs.json_payload(signs.run_text("szesz"))
      refute plain["lines"].first["tokens"].first.key?("form_of"),
             "form_of is present-only — absent on top-level signs"
    end

    # -- the status vocabulary, each against the fixture -----------------------

    def test_a_folded_value_resolves_deterministically
      token = first_token("szesz")
      assert_equal "šeš", token.input_value
      assert_equal "deterministic", token.status
      assert_equal "ŠEŠ", token.sign_name
      assert_equal ["U+122C0"], token.codepoints
      assert_equal "𒋀", token.glyph
      assert_empty token.candidates
      assert_nil token.language_qualifier
    end

    def test_a_compound_value_resolves_to_its_sequence
      token = first_token("uri5")
      assert_equal "|ŠEŠ.AB|", token.sign_name
      assert_equal %w[U+122C0 U+1200A], token.codepoints
      assert_equal "𒋀𒀊", token.glyph
    end

    def test_an_ambiguous_value_lists_every_candidate_never_one_silently
      token = first_token("idₓ")
      assert_equal "ambiguous", token.status
      assert_nil token.sign_name
      assert_empty token.codepoints.to_a
      assert_equal ["|A.BARA₂|", "|UD.ŠEŠ.KI|"], token.candidates.map(&:sign_name)
      assert_equal [%w[U+12000 U+12048], %w[U+12313 U+122C0 U+121A0]],
                   token.candidates.map(&:codepoints)
    end

    def test_a_qualified_value_resolves_the_explicit_sign
      token = first_token("zahx(SZESZ)")
      assert_equal "qualified", token.status
      assert_equal "zahₓ(ŠEŠ)", token.input_value
      assert_equal "ŠEŠ", token.sign_name
      assert_equal ["U+122C0"], token.codepoints
    end

    def test_an_unencoded_sign_is_no_codepoint_never_an_error
      token = first_token("|AxAN|")
      assert_equal "no-codepoint", token.status
      assert_equal "|A×AN|", token.sign_name
      assert_nil token.codepoints
      assert_nil token.glyph
    end

    def test_broken_tokens_are_broken
      tokens = signs.run_text("x [...]").lines.first.tokens
      assert_equal %w[broken broken], tokens.map(&:status)
    end

    def test_an_unknown_value_says_so_plainly
      token = first_token("blah99")
      assert_equal "unknown", token.status
      assert_equal "blah₉₉", token.input_value
      assert_nil token.sign_name
    end

    # -- numbers ----------------------------------------------------------------

    def test_a_number_token_is_itself_a_value_lookup
      token = first_token("2(disz)")
      assert_equal "2(diš)", token.input_value
      assert_equal "deterministic", token.status
      assert_equal "MIN", token.sign_name
      assert_equal ["U+1222B"], token.codepoints
    end

    def test_an_unlisted_number_notation_is_unknown
      token = first_token("1(N01)")
      assert_equal "1(N01)", token.input_value
      assert_equal "unknown", token.status
    end

    # -- logograms (documented resolution order: name, then value fallback) ----

    def test_uppercase_logogram_resolves_by_sign_name_first
      token = first_token("MIN")
      assert_equal "deterministic", token.status
      assert_equal "MIN", token.sign_name
    end

    def test_uppercase_logogram_falls_back_to_its_value
      token = first_token("URI5")
      assert_equal "deterministic", token.status
      assert_equal "|ŠEŠ.AB|", token.sign_name, "no sign is NAMED URI₅ — the value uri₅ resolves it"
    end

    def test_dotted_logogram_group_resolves_as_a_compound_first
      token = first_token("UD.SZESZ.KI")
      assert_equal "|UD.ŠEŠ.KI|", token.sign_name
      assert_equal "deterministic", token.status
    end

    def test_dotted_group_without_a_compound_splits_into_component_signs
      tokens = signs.run_text("SZESZ.MIN").lines.first.tokens
      assert_equal %w[ŠEŠ MIN], tokens.map(&:input_value)
      assert_equal %w[ŠEŠ MIN], tokens.map(&:sign_name)
    end

    # -- language qualifiers ----------------------------------------------------

    def test_language_qualified_value_surfaces_its_qualifier
      token = first_token("s,illu")
      assert_equal "ṣillu", token.input_value
      assert_equal "|AN.SAG@g|", token.sign_name
      assert_equal "akk", token.language_qualifier
    end

    def test_the_passage_language_filters_qualified_values
      assert_equal "deterministic", first_token("s,illu", language: "akk").status
      assert_equal "unknown", first_token("s,illu", language: "sux").status,
                   "an %akk reading is not a Sumerian reading"
    end

    # -- determinatives and dialect ---------------------------------------------

    def test_determinative_tokens_are_marked
      tokens = signs.run_text("{szesz}ma").lines.first.tokens
      assert tokens.first.determinative
      assert_equal "šeš", tokens.first.input_value
      refute tokens.last.determinative
    end

    def test_etcsl_dialect_folds_before_resolution
      token = first_token("aj", dialect: :etcsl)
      assert_equal "aŋ", token.input_value
      assert_equal "AK", token.sign_name, "the deprecated reading still resolves (P53-1)"
    end

    def test_structural_lines_are_counted_skipped
      result = signs.run_text("@obverse\n1. szesz\n$ rest broken")
      assert_equal 1, result.lines.size
      assert_equal 2, result.skipped_lines
    end

    # -- URN mode (real fixture-loaded documents) -------------------------------

    def test_urn_mode_reads_a_real_cdli_passage
      catalog = store_test_db
      passage_urn = load_cdli_document(catalog)
      result = signs(catalog: catalog).run_urn(passage_urn)
      assert_equal :urn, result.mode
      assert_equal passage_urn, result.urn
      assert_equal "sux", result.language
      assert_equal :catf, result.dialect
      assert_equal "cdli", result.source_slug
      assert_equal "attribution", result.license_class
      line = result.lines.first
      assert_equal passage_urn, line.urn
      # The real P469841 obverse 1: "1(gesz2) 4(disz) 1/2(disz) gurusz u4 1(disz)-sze3"
      assert_equal %w[1(geš₂) 4(diš) 1/2(diš) guruš u₄ 1(diš) še₃],
                   line.tokens.map(&:input_value)
    end

    def test_urn_mode_document_urn_walks_every_passage
      catalog = store_test_db
      load_cdli_document(catalog)
      result = signs(catalog: catalog).run_urn("urn:nabu:cdli:p469841")
      assert_operator result.lines.size, :>=, 5
      assert(result.lines.all? { |line| line.urn.start_with?("urn:nabu:cdli:p469841:") })
    end

    def test_urn_mode_auto_selects_the_etcsl_dialect
      catalog = store_test_db
      urn = load_etcsl_document(catalog)
      result = signs(catalog: catalog).run_urn(urn)
      assert_equal :etcsl, result.dialect, "the etcsl shelf's URNs fold c→š / j→ŋ automatically"
      assert_includes result.lines.first.tokens.map(&:input_value), "šu",
                      "the fixture's real '{d}cu-i3-li2-cu' folds c→š"
    end

    def test_urn_mode_unknown_urn_is_nil
      assert_nil signs(catalog: store_test_db).run_urn("urn:nabu:cdli:p9999999")
    end

    # -- the frozen JSON contract (Edubba consumes this shape) ------------------

    def test_json_payload_pins_the_contract
      result = signs.run_text("szesz idₓ {d}x")
      payload = Nabu::Query::Signs.json_payload(result)
      assert_equal(
        {
          "mode" => "text", "urn" => nil, "language" => nil, "dialect" => "catf",
          "source" => nil,
          "lines" => [
            { "n" => 1, "urn" => nil, "text" => "szesz idₓ {d}x",
              "tokens" => [
                { "input_value" => "šeš", "status" => "deterministic", "sign_name" => "ŠEŠ",
                  "codepoints" => ["U+122C0"], "candidates" => [], "language_qualifier" => nil },
                { "input_value" => "idₓ", "status" => "ambiguous", "sign_name" => nil,
                  "codepoints" => [],
                  "candidates" => [
                    { "input_value" => "idₓ", "status" => "deterministic",
                      "sign_name" => "|A.BARA₂|", "codepoints" => %w[U+12000 U+12048],
                      "language_qualifier" => nil },
                    { "input_value" => "idₓ", "status" => "deterministic",
                      "sign_name" => "|UD.ŠEŠ.KI|",
                      "codepoints" => %w[U+12313 U+122C0 U+121A0],
                      "language_qualifier" => nil }
                  ],
                  "language_qualifier" => nil },
                { "input_value" => "d", "status" => "unknown", "sign_name" => nil,
                  "codepoints" => [], "candidates" => [], "language_qualifier" => nil,
                  "determinative" => true },
                { "input_value" => "x", "status" => "broken", "sign_name" => nil,
                  "codepoints" => [], "candidates" => [], "language_qualifier" => nil }
              ] }
          ],
          "skipped_lines" => 0
        },
        payload
      )
    end

    def test_json_payload_no_codepoint_serializes_an_empty_codepoint_list
      payload = Nabu::Query::Signs.json_payload(signs.run_text("|AxAN|"))
      token = payload.fetch("lines").first.fetch("tokens").first
      assert_equal "no-codepoint", token.fetch("status")
      assert_equal "|A×AN|", token.fetch("sign_name")
      assert_equal [], token.fetch("codepoints")
    end

    # -- helpers ---------------------------------------------------------------

    def load_cdli_document(catalog)
      source = Nabu::Store::Source.create(
        slug: "cdli", name: "CDLI", adapter_class: "Nabu::Adapters::Cdli",
        license_class: "attribution"
      )
      adapter = Nabu::Adapters::Cdli.new
      ref = adapter.discover(Nabu::TestSupport.fixtures("cdli"))
                   .find { |r| r.id == "urn:nabu:cdli:p469841" }
      document = adapter.parse(ref)
      Nabu::Store::Loader.new(db: catalog, source: source).load([document], full: false)
      document.passages.first.urn
    end

    def load_etcsl_document(catalog)
      source = Nabu::Store::Source.create(
        slug: "etcsl", name: "ETCSL", adapter_class: "Nabu::Adapters::Etcsl",
        license_class: "nc"
      )
      adapter = Nabu::Adapters::Etcsl.new
      ref = adapter.discover(Nabu::TestSupport.fixtures("etcsl"))
                   .find { |r| r.id == "urn:nabu:etcsl:2.5.2.3" }
      document = adapter.parse(ref)
      Nabu::Store::Loader.new(db: catalog, source: source).load([document], full: false)
      document.passages.find { |p| p.text.include?("cu-i3-li2-cu") }.urn
    end
  end
end
