# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::OshbOsisParser (P26-3) — the OSHB/WLC OSIS book parser.
  # Fixtures are byte-verbatim slices of openscriptures/morphhb@3d15126f:
  # Gen 1 + Gen 31 (token-grain Aramaic at 31:47), Ruth 1 (the NFC-instability
  # pin + a ketiv/qere at 1:8), Ps 23 (the psalms-numbering exercise book) and
  # Jer 10 (verse 11 is the one whole-verse Aramaic sentence in Jeremiah —
  # the passage-majority exercise).
  class OshbOsisParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("oshb")

    def parse(book)
      Nabu::Adapters::OshbOsisParser.new.parse(
        File.join(FIXTURES, "wlc", "#{book}.xml"),
        urn: "urn:nabu:oshb:#{book.downcase}"
      )
    end

    # -- shape ---------------------------------------------------------------

    def test_parses_one_passage_per_verse_with_chapter_verse_urns
      document = parse("Ruth")
      assert_equal "urn:nabu:oshb:ruth", document.urn
      assert_equal 22, document.size, "Ruth 1 has 22 verses"
      assert_equal "urn:nabu:oshb:ruth:1.1", document.passages.first.urn
      assert_equal "urn:nabu:oshb:ruth:1.22", document.passages.last.urn
      assert_equal (0..21).to_a, document.passages.map(&:sequence)
    end

    def test_two_chapter_slice_keeps_native_chapter_numbers
      document = parse("Gen")
      assert_equal 85, document.size, "Gen 1 (31) + Gen 31 (54)"
      assert_equal "urn:nabu:oshb:gen:1.1", document.passages.first.urn
      assert_includes document.passages.map(&:urn), "urn:nabu:oshb:gen:31.47"
    end

    # -- the byte-verbatim ruling (owner, 2026-07-18) ------------------------

    # Ruth 1:1 assembled exactly from the upstream bytes: morpheme dividers
    # (`/`, OSHB markup, not WLC text) removed, words joined per the source's
    # own inter-element whitespace (maqqef and sof-pasuq attach directly).
    # The mark order is the WLC's own — dagesh before hiriq — which NFC
    # would REORDER: the pin below proves the stored text is not NFC and
    # byte-identical to upstream (the scout's measured instability example).
    def test_ruth_1_1_text_is_byte_identical_to_upstream_and_not_nfc
      text = parse("Ruth").passages.first.text
      expected = "וַיְהִ֗י " \
                 "בִּימֵי֙ " \
                 "שְׁפֹ֣ט " \
                 "הַשֹּׁפְטִ֔ים " \
                 "וַיְהִ֥י " \
                 "רָעָ֖ב " \
                 "בָּאָ֑רֶץ " \
                 "וַיֵּ֨לֶךְ " \
                 "אִ֜ישׁ " \
                 "מִבֵּ֧ית " \
                 "לֶ֣חֶם " \
                 "יְהוּדָ֗ה " \
                 "לָגוּר֙ " \
                 "בִּשְׂדֵ֣י " \
                 "מוֹאָ֔ב " \
                 "ה֥וּא " \
                 "וְאִשְׁתּ֖וֹ " \
                 "וּשְׁנֵ֥י " \
                 "בָנָֽיו׃"
      assert_equal expected, text, "WLC bytes exactly as upstream ships them"
      refute text.unicode_normalized?(:nfc),
             "Ruth 1:1 is the measured NFC-instability pin — NFC would reorder its marks"
      refute_equal Nabu::Normalize.nfc(text), text,
                   "NFC normalization would rewrite the stored bytes"
    end

    def test_gen_1_1_reads_bereshit_and_folds_findably
      passage = parse("Gen").passages.first
      first_word = passage.annotations["tokens"].first
      # בְּרֵאשִׁ֖ית upstream bytes (bet + dagesh before hiriq is stable here;
      # the shin dot U+05C1 rides after the letter): slash-stripped form.
      assert_equal "בְּרֵאשִׁ֖ית",
                   first_word["form"]
      # The SEARCH side folds through NFC + mark strip regardless of the
      # byte-verbatim storage: an unpointed query finds the pointed verse.
      assert passage.text_normalized.start_with?("בראשית"),
             "text_normalized must open with bare-letter בראשית"
      assert passage.text_normalized.unicode_normalized?(:nfc)
    end

    # -- joining rules -------------------------------------------------------

    def test_maqqef_and_sof_pasuq_attach_without_space
      text = parse("Jer").passages.find { |p| p.urn.end_with?(":10.11") }.text
      # דִּֽי־שְׁמַיָּ֥א: maqqef U+05BE joins the two words directly.
      assert_includes text, "דִּֽי־שׁ"
      assert_includes text, "\u05DC\u05BC\u05B6\u05D4\u05C3",
                      "sof pasuq attaches to the final word (upstream dagesh-before-segol byte order)"
      refute_includes text, " ׃"
      assert text.end_with?("׃ ס"), "the samekh parashah mark is upstream text, space-separated"
      refute_includes text, "/", "morpheme dividers are OSHB markup, not WLC text"
    end

    # -- tokens: the Strong's lemma lane and the OSHM morphology -------------

    def test_tokens_carry_augmented_strongs_lemma_and_oshm_morph_verbatim
      tokens = parse("Ruth").passages.first.annotations["tokens"]
      first = tokens.first
      assert_equal "c/1961", first["lemma"],
                   "the lemma lane carries the augmented Strong's id — no headword is invented"
      assert_equal "HC/Vqw3ms", first["morph"]
      assert_equal "08xeN", first["id"], "the immutable OSHB word id"
      assert_equal "hbo", first["lang"]
      # a suffixed augmented Strong's ("1481 a") survives verbatim
      assert_equal "l/1481 a", tokens[12]["lemma"]
    end

    def test_ketiv_word_carries_its_qere_reading
      # Ruth 1:8 יעשה (ketiv, unpointed in the running text) with qere יַ֣עַשׂ.
      passage = parse("Ruth").passages.find { |p| p.urn.end_with?(":1.8") }
      ketiv = passage.annotations["tokens"].find { |t| t["type"] == "x-ketiv" }
      refute_nil ketiv
      assert_equal "\u05D9\u05E2\u05E9\u05D4", ketiv["form"], "the ketiv is the running text"
      assert_includes passage.text, ketiv["form"]
      qere = ketiv["qere"]
      assert_equal "6213 a", qere.first["lemma"]
      assert_equal "HVqj3ms", qere.first["morph"]
      refute_includes passage.text, qere.first["form"], "the qere is apparatus, not running text"
    end

    # -- language honesty (hbo + arc, the corph majority mechanics) ----------

    def test_aramaic_verse_takes_arc_by_token_majority
      document = parse("Jer")
      assert_equal "hbo", document.language, "Jeremiah is Hebrew by document majority"
      by_urn = document.to_h { |p| [p.urn.split(":").last, p.language] }
      assert_equal "arc", by_urn["10.11"], "the one Aramaic verse in Jeremiah votes arc"
      assert_equal "hbo", by_urn["10.10"]
      arc_token = document.passages.find { |p| p.urn.end_with?(":10.11") }
                                   .annotations["tokens"].first
      assert_equal "arc", arc_token["lang"], "OSHM A-prefix morphs mark Biblical Aramaic"
    end

    def test_token_grain_aramaic_does_not_flip_a_hebrew_verse
      # Gen 31:47: Laban's two Aramaic words (יְגַ֖ר שָׂהֲדוּתָ֑א, ANp) inside
      # a Hebrew verse — token lang arc, passage majority stays hbo.
      passage = parse("Gen").passages.find { |p| p.urn.end_with?(":31.47") }
      assert_equal "hbo", passage.language
      langs = passage.annotations["tokens"].map { |t| t["lang"] }
      assert_equal 2, langs.count("arc")
    end

    # -- notes ---------------------------------------------------------------

    def test_bare_notes_ride_annotations_not_text
      passage = parse("Ps").passages.first
      assert_includes passage.annotations["notes"], "KJV:Ps.23.1",
                      "the WLC-vs-KJV verse-mapping note is apparatus"
      refute_includes passage.text, "KJV"
    end
  end
end
