# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::OraccJsonParser — the ORACC JSON `cdl` tree family
  # (P10-1), exercised against the real fixture extracts (rimanum = Akkadian
  # P-numbers, etcsri = Sumerian Q-numbers). Expected texts/labels/lemmas were
  # computed independently from the fixture JSON at extraction time.
  class OraccJsonParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("oracc")

    # The P11-7 defect fixtures (real trimmed dcclt slices) live in their own
    # tree so the discover-walked main fixtures stay a clean, all-parsing corpus.
    DEFECTS = Nabu::TestSupport.fixtures("oracc_p11_7")

    # P14-9 collision fixtures: trimmed real blms (bilingual literary) and
    # saao-saa08 (omen) slices whose label-less line-starts share one sentence
    # label (the P11-7 fallback), so distinct physical lines mint one suffix.
    P14 = Nabu::TestSupport.fixtures("oracc_p14_9")

    def parse(project, id, urn: nil, title: nil, root: FIXTURES)
      Nabu::Adapters::OraccJsonParser.new.parse(
        File.join(root, project, "corpusjson", "#{id}.json"),
        urn: urn || "urn:nabu:oracc:#{project}:#{id}",
        title: title
      )
    end

    # -- P11-7 fix 3: catalog-only skeleton skips, never quarantines ----------

    def test_no_content_skeleton_is_skipped_not_quarantined
      error = assert_raises(Nabu::DocumentSkipped) do
        parse("dcclt", "P000725", root: DEFECTS)
      end
      # a DocumentSkipped is NOT a ParseError — the loader counts it honestly
      # (skipped-by-rule) rather than quarantining it.
      refute_kind_of Nabu::ParseError, error
      assert_equal "catalog-only (no content)", error.reason
    end

    # -- P11-7 fix 4: a label-less line-start falls back to the sentence label -

    def test_label_less_line_start_falls_back_to_enclosing_sentence_label
      document = parse("dcclt", "P010104", root: DEFECTS)
      suffixes = document.map { |p| p.urn.split(":").last }
      # the bare line-start (no @label/@n) recovers the enclosing sentence
      # c-node's label "r xi' 10'" → suffix "r.xi'.10'", so the whole document
      # loads instead of quarantining over one upstream data gap.
      assert_includes suffixes, "r.xi'.10'"
      assert_includes suffixes, "o.i'.1" # an ordinary labeled line rides alongside
      refute_empty document
    end

    # -- P14-9 fix 1: repeated fallback labels get a positional :b suffix -----

    def test_bilingual_labelless_line_collision_gets_positional_b_suffix
      # blms P345480 is interlinear Sumerian/Akkadian: the Akkadian line is a
      # label-less line-start that P11-7 falls back to the sentence label "o 1'",
      # colliding with the Sumerian line's own "o 1'". Two distinct physical
      # lines → the second takes a ":b2" positional suffix (GRETIL/ccmh
      # precedent), never quarantined, never merged.
      document = parse("blms", "P345480", root: P14)
      suffixes = document.map { |p| p.urn.delete_prefix("#{document.urn}:") }
      assert_includes suffixes, "o.1'"
      assert_includes suffixes, "o.1':b2"
      assert_equal suffixes.size, suffixes.uniq.size, "every passage urn is unique"
      # the two "o 1'" lines are the Sumerian and its Akkadian version — kept
      # apart, not merged into one text.
      original = document.find { |p| p.urn.end_with?(":o.1'") }
      restart  = document.find { |p| p.urn.end_with?(":o.1':b2") }
      refute_equal original.text, restart.text
    end

    def test_range_sentence_fallback_collision_gets_positional_b_suffix
      # saao-saa08 P336559: several label-less line-starts all fall back to the
      # one whole-text sentence label "o 1 - r 6" → repeated suffix, disambiguated
      # in document order rather than quarantining the tablet.
      document = parse("saao-saa08/saa08", "P336559",
                       root: P14, urn: "urn:nabu:oracc:saao-saa08:P336559")
      suffixes = document.map { |p| p.urn.delete_prefix("#{document.urn}:") }
      assert_includes suffixes, "o.1.-.r.6"
      assert_includes suffixes, "o.1.-.r.6:b2"
      assert_equal suffixes.size, suffixes.uniq.size
    end

    # -- the rich Akkadian exemplar (P405432) --------------------------------

    def test_parses_p405432_into_one_passage_per_line_start
      document = parse("rimanum", "P405432")
      assert_equal "urn:nabu:oracc:rimanum:P405432", document.urn
      assert_equal 8, document.size
      assert_equal(%w[o.1 o.2 o.3 r.1 r.2 r.3 r.4 r.5],
                   document.map { |p| p.urn.split(":").last })
    end

    def test_line_text_is_the_transliteration_joined_from_l_node_forms
      document = parse("rimanum", "P405432")
      assert_equal "2(BARIG) ZI₃ US₂ a-na GEŠBUN", document.first.text
      by_suffix = document.to_h { |p| [p.urn.split(":").last, p] }
      # determinatives and subscript numerals survive verbatim (pristine text)
      assert_equal "LU₂ du-un-nu-um{ki}", by_suffix["o.2"].text
      assert_equal "{iti}KIN.{d}INANNA U₄ 2-KAM", by_suffix["r.3"].text
      # the nonw d-node fragment ("/") is not reading text — l-node forms only
      assert_equal "u₃ a-hi-a-tim ZI.GA", by_suffix["o.3"].text
    end

    def test_cof_continuation_tail_contributes_no_text_but_keeps_its_token
      # P405432 r 2: ONE written form NIG₂.ŠU carries TWO lemma words
      # (ša + qātu) as a cof-head/cof-tails l-node pair. The form must appear
      # once in the text; both lemmas must appear in the tokens.
      passage = parse("rimanum", "P405432").find { |p| p.urn.end_with?(":r.2") }
      assert_equal "NIG₂.ŠU {d}EN.ZU-še-mi", passage.text
      lemmas = passage.annotations["tokens"].map { |t| t["lemma"] }
      assert_equal %w[ša qātu Sîn-šeme], lemmas
    end

    def test_tokens_carry_the_gold_lemmatization_fields
      passage = parse("rimanum", "P405432").first
      flour = passage.annotations["tokens"][1]
      assert_equal "ZI₃", flour["form"]
      assert_equal "qēmu", flour["lemma"] # cf, the citation form
      assert_equal "qēmu", flour["norm"]
      assert_equal "flour", flour["gw"]
      assert_equal "flour", flour["sense"]
      assert_equal "N", flour["pos"]
      assert_equal "akk-x-oldbab", flour["lang"]
      # the unlemmatized numeral carries form/pos/lang but no lemma keys
      numeral = passage.annotations["tokens"][0]
      assert_equal "2(BARIG)", numeral["form"]
      assert_equal "n", numeral["pos"]
      refute numeral.key?("lemma")
    end

    def test_tokens_record_per_grapheme_logolang
      # NIG₂.ŠU is a Sumerian logogram inside an Akkadian text: its gdl signs
      # carry logolang "sux", surfaced as a distinct-values token annotation.
      # The personal name {d}EN.ZU-še-mi carries it too (EN.ZU is a logogram,
      # nested one gdl group deeper); the purely syllabic a-na does not.
      document = parse("rimanum", "P405432")
      r2 = document.find { |p| p.urn.end_with?(":r.2") }
      assert_equal ["sux"], r2.annotations["tokens"][0]["logolang"]
      assert_equal ["sux"], r2.annotations["tokens"][2]["logolang"]
      a_na = document.first.annotations["tokens"][3]
      assert_equal "a-na", a_na["form"]
      refute a_na.key?("logolang")
    end

    def test_document_language_is_the_per_text_primary_base_code
      # P405432 is majority akk-x-oldbab with Sumerian year-name lines: the
      # document and EVERY passage carry the base code "akk" (per-text primary
      # language); per-word langs stay honest in the token annotations.
      document = parse("rimanum", "P405432")
      assert_equal "akk", document.language
      assert(document.all? { |p| p.language == "akk" })
      year_name = document.find { |p| p.urn.end_with?(":r.4") }
      assert_equal "mu ri-im-an lugal", year_name.text
      assert_equal(%w[sux sux sux], year_name.annotations["tokens"].map { |t| t["lang"] })
    end

    def test_sentence_membership_rides_in_annotations
      document = parse("rimanum", "P405432")
      assert_equal ["o 1 - r 5"], document.first.annotations["sentences"]
    end

    def test_primed_labels_and_seal_surfaces_mint_stable_suffixes
      document = parse("rimanum", "P405134")
      assert_equal(["o.1", "r.1’", "r.2’", "seal.1.1’", "seal.1.2’"],
                   document.map { |p| p.urn.split(":").last })
      assert_equal "mu ri-im-{d}a-nu-um lugal-e",
                   document.find { |p| p.urn.end_with?(":r.2’") }.text
    end

    # -- the Sumerian Q-number side (etcsri) ---------------------------------

    def test_parses_sumerian_q_text_with_plain_numeric_labels
      document = parse("etcsri", "Q004151")
      assert_equal "urn:nabu:oracc:etcsri:Q004151", document.urn
      assert_equal "sux", document.language
      assert_equal 6, document.size
      assert_equal(%w[1 2 3 4 5 6], document.map { |p| p.urn.split(":").last })
      assert_equal "{d}amar-{d}suen", document.first.text
      assert_equal "lugal kalag-ga", document.to_a[1].text
    end

    def test_minimal_single_line_document_parses
      document = parse("etcsri", "Q001299")
      assert_equal 1, document.size
      assert_equal "urn:nabu:oracc:etcsri:Q001299:1", document.first.urn
      assert_equal "alim-šu", document.first.text
      assert_equal "Alimšu", document.first.annotations["tokens"][0]["lemma"]
    end

    def test_sequences_are_document_order
      document = parse("rimanum", "P405432")
      assert_equal (0..7).to_a, document.map(&:sequence)
    end

    def test_title_and_canonical_path_pass_through
      path = File.join(FIXTURES, "etcsri", "corpusjson", "Q004151.json")
      document = Nabu::Adapters::OraccJsonParser.new.parse(
        path, urn: "urn:nabu:oracc:etcsri:Q004151", title: "Amar-Suena 2049add"
      )
      assert_equal "Amar-Suena 2049add", document.title
      assert_equal path, document.canonical_path
    end

    # -- identity + damage ----------------------------------------------------

    def test_urn_mismatch_is_a_parse_error
      error = assert_raises(Nabu::ParseError) { parse("rimanum", "P405432", urn: "urn:nabu:oracc:rimanum:P999999") }
      assert_match(/urn mismatch/, error.message)
    end

    def test_malformed_json_is_a_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.json")
        File.write(path, "{ not json")
        assert_raises(Nabu::ParseError) do
          Nabu::Adapters::OraccJsonParser.new.parse(path, urn: "urn:nabu:oracc:x:bad")
        end
      end
    end

    def test_empty_file_is_a_parse_error
      # The ADAPTER's discover skips catalog-only empty files; a parser handed
      # one anyway must fail loudly, not fabricate a document.
      path = File.join(FIXTURES, "rimanum", "corpusjson", "P405254.json")
      assert_raises(Nabu::ParseError) do
        Nabu::Adapters::OraccJsonParser.new.parse(path, urn: "urn:nabu:oracc:rimanum:P405254")
      end
    end

    def test_text_is_nfc
      parse("rimanum", "P405432").each do |passage|
        assert passage.text.unicode_normalized?(:nfc)
      end
    end
  end
end
