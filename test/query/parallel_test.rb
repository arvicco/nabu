# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Parallel (P7-4, span-grouped P8-1b): resolve a document or
  # passage urn to its sibling edition of the same CTS work in a target
  # language and SPAN-GROUP the two passage lists by citation suffix. Catalog is
  # a fresh in-memory SQLite seeded through the real Loader (the house
  # store-test pattern).
  class ParallelTest < Minitest::Test
    include StoreTestDB

    GRC_URN = "urn:cts:greekLit:tg1.w1.perseus-grc2"
    ENG_URN = "urn:cts:greekLit:tg1.w1.perseus-eng2"

    def setup
      @catalog = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "attribution"
      )
      @loader = Nabu::Store::Loader.new(db: @catalog, source: @source)
    end

    # -- helpers -------------------------------------------------------------

    def load_edition(urn, language, passages, title: nil)
      document = Nabu::Document.new(
        urn: urn, language: language, title: title, canonical_path: "/canonical/src/#{urn.split(':').last}.xml"
      )
      passages.each_with_index do |(suffix, text), index|
        document << Nabu::Passage.new(
          urn: "#{urn}:#{suffix}", language: language, text: text, sequence: index
        )
      end
      @loader.load([document], full: false)
    end

    def load_default_pair
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]], title: "Iliad")
      load_edition(ENG_URN, "eng", [%w[pref Preface], %w[1 Wrath], %w[3 goddess]], title: "Iliad (tr.)")
    end

    # A card-cited translation over a line-cited original: grc lines 1.1..1.8,
    # eng cards anchored at 1.1 (owns 1.1–1.4) and 1.5 (owns 1.5–1.8).
    def load_card_pair
      load_edition(GRC_URN, "grc", (1..8).map { |n| ["1.#{n}", "grc#{n}"] }, title: "Odyssey")
      load_edition(ENG_URN, "eng", [["1.1", "Block one"], ["1.5", "Block two"]], title: "Odyssey (tr.)")
    end

    def run_parallel(urn, lang: "eng")
      Nabu::Query::Parallel.new(catalog: @catalog).run(urn, lang: lang)
    end

    def kinds(result)
      result.groups.map(&:kind)
    end

    # -- verse-for-verse: every anchor is a 1:1 pair --------------------------

    # P30 review: the P25/P29 nabu-urn sibling shapes were never wired into
    # the work-pattern chain — riig's 74 -fr siblings, open-etruscan's 1,798
    # -en and itant's -eng/-ita/-dipl were loaded but invisible to
    # --parallel (found live during the P29 tour).
    def test_riig_fr_sibling_pairs
      load_edition("urn:nabu:riig:all-01-01", "xtg", [%w[1 ieuru]], title: "RIIG ALL-01-01")
      load_edition("urn:nabu:riig:all-01-01-fr", "fra", [%w[1 offrit]], title: "RIIG ALL-01-01 (fr)")

      result = run_parallel("urn:nabu:riig:all-01-01:1", lang: "fra")
      assert_equal "fra", result.right&.language, "the riig -fr sibling must pair"
      assert_equal 1, result.groups.count { |g| g.kind == :pair }
    end

    def test_open_etruscan_en_sibling_pairs
      load_edition("urn:nabu:open-etruscan:cr-2.20", "ett", [%w[1 mi]], title: "Cr 2.20")
      load_edition("urn:nabu:open-etruscan:cr-2.20-en", "eng", [%w[1 I]], title: "Cr 2.20 (en)")

      result = run_parallel("urn:nabu:open-etruscan:cr-2.20:1", lang: "eng")
      assert_equal "eng", result.right&.language, "the open-etruscan -en sibling must pair"
    end

    def test_itant_translation_and_layer_siblings_pair
      load_edition("urn:nabu:itant:oscan-2", "osc", [%w[1 pakis]], title: "ItAnt Oscan 2")
      load_edition("urn:nabu:itant:oscan-2-eng", "eng", [%w[1 Pakis]], title: "ItAnt Oscan 2 (eng)")
      load_edition("urn:nabu:itant:oscan-2-ita", "ita", [%w[1 Pacio]], title: "ItAnt Oscan 2 (ita)")

      assert_equal "eng", run_parallel("urn:nabu:itant:oscan-2:1", lang: "eng").right&.language
      assert_equal "ita", run_parallel("urn:nabu:itant:oscan-2:1", lang: "ita").right&.language
    end

    # ISO 639-2 B/T equivalence (owner repro 2026-07-18: tla-hf siblings are
    # deu, aes siblings are ger — `--parallel ger` must find a deu edition
    # and vice versa, fold-both-sides style).
    def test_parallel_lang_accepts_the_equivalent_iso_code_spelling
      load_edition(GRC_URN, "grc", [%w[1 original]], title: "Work")
      load_edition(ENG_URN, "deu", [%w[1 übersetzt]], title: "Work (de tr.)")

      assert_equal "deu", run_parallel("#{GRC_URN}:1", lang: "ger").right&.language,
                   "ger must reach the deu sibling"
      assert_equal "deu", run_parallel("#{GRC_URN}:1", lang: "de").right&.language,
                   "the two-letter spelling must reach it too"
    end

    def test_verse_for_verse_translation_is_all_pairs
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]], title: "Iliad")
      load_edition(ENG_URN, "eng", [%w[1 Wrath], %w[2 sing], %w[3 goddess]], title: "Iliad (tr.)")

      result = run_parallel(GRC_URN)
      assert_equal %i[pair pair pair], kinds(result)
      one, two, three = result.groups
      assert_equal ":1", one.anchor
      assert_equal %w[μῆνιν Wrath], [one.originals.first.text, one.translation.text]
      assert_equal "sing", two.translation.text
      assert_equal "goddess", three.translation.text
      refute one.clipped
    end

    # -- coarse span grouping (the owner feedback) ----------------------------

    def test_card_anchor_owns_the_span_up_to_the_next_anchor
      load_card_pair

      result = run_parallel(GRC_URN)
      assert_equal %i[block block], kinds(result)
      first, second = result.groups
      # Anchor 1.1 owns lines 1.1..1.4, once, as a block — no dashed lines.
      assert_equal ":1.1", first.anchor
      assert_equal ":1.1", first.covers_first
      assert_equal ":1.4", first.covers_last
      assert_equal %w[grc1 grc2 grc3 grc4], first.originals.map(&:text)
      assert_equal "Block one", first.translation.text
      refute first.clipped
      # Anchor 1.5 owns the rest.
      assert_equal ":1.5", second.covers_first
      assert_equal ":1.8", second.covers_last
      assert_equal "Block two", second.translation.text
    end

    def test_translation_only_suffix_stays_one_sided_and_never_owns
      load_default_pair # grc [1,2,3]; eng [pref,1,3]

      result = run_parallel(GRC_URN)
      # :pref is eng-only (one-sided); :1 owns 1..2 as a block; :3 is a 1:1 pair.
      assert_equal %i[translation block pair], kinds(result)
      pref, block, pair = result.groups
      assert_equal :translation, pref.kind
      assert_nil pref.originals.first
      assert_equal "Preface", pref.translation.text
      assert_equal %w[μῆνιν ἄειδε], block.originals.map(&:text)
      assert_equal "Wrath", block.translation.text
      assert_equal %w[θεά goddess], [pair.originals.first.text, pair.translation.text]
    end

    def test_original_before_the_first_anchor_is_one_sided
      load_edition(GRC_URN, "grc", [%w[0 proem], %w[1 μῆνιν], %w[2 ἄειδε]], title: "Iliad")
      load_edition(ENG_URN, "eng", [%w[1 Wrath]], title: "Iliad (tr.)")

      result = run_parallel(GRC_URN)
      # :0 precedes the only anchor (:1) → grc-only; :1 owns 1..2 as a block.
      assert_equal %i[original block], kinds(result)
      assert_equal "proem", result.groups.first.originals.first.text
      assert_nil result.groups.first.translation
    end

    # -- passage scope ---------------------------------------------------------

    def test_passage_urn_scopes_to_the_owning_block_clipped_to_that_line
      load_card_pair

      result = run_parallel("#{GRC_URN}:1.2")
      assert_equal ":1.2", result.scope
      # 1.2 is owned by the card anchored at 1.1 — the block still shows, but
      # clipped to the single queried line, coverage intact.
      assert_equal [:block], kinds(result)
      group = result.groups.first
      assert_equal ":1.1", group.anchor
      assert_equal ":1.1", group.covers_first
      assert_equal ":1.4", group.covers_last
      assert group.clipped
      assert_equal ":1.2", group.shown_first
      assert_equal ":1.2", group.shown_last
      assert_equal %w[grc2], group.originals.map(&:text)
      assert_equal "Block one", group.translation.text
    end

    def test_verse_passage_urn_scopes_to_its_pair
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε]], title: "Iliad")
      load_edition(ENG_URN, "eng", [%w[1 Wrath], %w[2 sing]], title: "Iliad (tr.)")

      result = run_parallel("#{GRC_URN}:1")
      assert_equal [:pair], kinds(result)
      refute result.groups.first.clipped
      assert_equal %w[μῆνιν Wrath],
                   [result.groups.first.originals.first.text, result.groups.first.translation.text]
    end

    # -- range composition + clipping (the key regression) --------------------

    def test_mid_card_range_clips_the_block_and_keeps_the_note
      load_card_pair

      result = run_parallel("#{GRC_URN}:1.2-1.3")
      # Only lines 1.2..1.3 are in the slice; the owning card anchored at 1.1
      # still renders, clipped, coverage intact.
      assert_equal [:block], kinds(result)
      group = result.groups.first
      assert_equal ":1.1", group.covers_first
      assert_equal ":1.4", group.covers_last
      assert group.clipped
      assert_equal ":1.2", group.shown_first
      assert_equal ":1.3", group.shown_last
      assert_equal %w[grc2 grc3], group.originals.map(&:text)
    end

    def test_range_starting_inside_a_card_still_shows_the_outside_anchor
      load_card_pair

      # 1.3..1.6 straddles two cards; BOTH owning anchors (1.1 and 1.5) lie
      # partly/wholly outside the slice — the case that used to render all "—".
      result = run_parallel("#{GRC_URN}:1.3-1.6")
      assert_equal %i[block block], kinds(result)
      first, second = result.groups
      assert_equal ":1.1", first.anchor
      assert first.clipped
      assert_equal ":1.3", first.shown_first
      assert_equal ":1.4", first.shown_last
      assert_equal "Block one", first.translation.text, "the card anchored outside the slice still renders"
      assert_equal ":1.5", second.anchor
      assert second.clipped
      assert_equal ":1.5", second.shown_first
      assert_equal ":1.6", second.shown_last
    end

    def test_range_end_not_found_raises_through_parallel
      load_card_pair
      assert_raises(Nabu::Query::Range::Error) { run_parallel("#{GRC_URN}:1.1-9.9") }
    end

    # -- alignment from the translation side ----------------------------------

    def test_alignment_is_symmetric_from_the_translation_side
      load_default_pair

      result = run_parallel(ENG_URN, lang: "grc")
      assert_equal ENG_URN, result.left.urn
      assert_equal GRC_URN, result.right.urn
      # Left is now the eng edition [pref,1,3]; grc [1,2,3]. Anchor grc:1 owns
      # eng pref? No — pref is not in grc, so pref is one-sided; grc:1 pairs 1,
      # grc:2 is grc-only (translation side), grc:3 pairs 3.
      assert_equal ENG_URN, result.left.urn
    end

    # -- sibling selection -------------------------------------------------------

    def test_multiple_lang_siblings_pick_the_highest_version_numerically
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν]])
      load_edition("urn:cts:greekLit:tg1.w1.perseus-eng2", "eng", [%w[1 old]])
      load_edition("urn:cts:greekLit:tg1.w1.perseus-eng10", "eng", [%w[1 new]])

      result = run_parallel(GRC_URN)
      assert_equal "urn:cts:greekLit:tg1.w1.perseus-eng10", result.right.urn,
                   "eng10 beats eng2 numerically (not lexicographically)"
    end

    def test_sibling_lookup_never_crosses_works
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν]])
      load_edition("urn:cts:greekLit:tg1.w2.perseus-eng2", "eng", [%w[1 other]])

      result = run_parallel(GRC_URN)
      assert_nil result.right, "an eng edition of a DIFFERENT work is not a sibling"
      assert_empty result.groups
    end

    def test_no_sibling_in_the_requested_language_returns_result_without_right
      load_default_pair

      result = run_parallel(GRC_URN, lang: "lat")
      assert_equal GRC_URN, result.left.urn
      assert_nil result.right
      assert_empty result.groups
    end

    def test_non_cts_urn_has_no_siblings
      load_edition("urn:nabu:ddbdp:aegyptus:89:240", "grc", [%w[1 κτλ]])

      result = run_parallel("urn:nabu:ddbdp:aegyptus:89:240")
      refute_nil result
      assert_nil result.right
    end

    # -- ORACC tablets (P13-4): <tablet-urn> ↔ <tablet-urn>-en ------------------

    TABLET_URN = "urn:nabu:oracc:saao-saa01:P224395"
    TABLET_EN_URN = "urn:nabu:oracc:saao-saa01:P224395-en"

    def load_tablet_pair
      load_edition(TABLET_URN, "akk",
                   [["o.1", "a-na LUGAL"], ["o.2", "ARAD-ka"], ["o.3", "lu šul-mu"], ["o.4", "ša LUGAL"]],
                   title: "SAA 01 175")
      load_edition(TABLET_EN_URN, "eng",
                   [["o.1", "To the king, my lord: your servant. Good health!"], ["o.4", "As to the king."]],
                   title: "SAA 01 175 (English translation)")
    end

    def test_oracc_tablet_finds_its_en_sibling_and_span_groups_the_units
      load_tablet_pair

      result = run_parallel(TABLET_URN)
      assert_equal TABLET_EN_URN, result.right.urn
      # The paragraph unit anchored at o.1 owns tablet lines o.1..o.3 (up to
      # the next anchor) — the card-cited-Homer block, on a tablet.
      assert_equal %i[block pair], kinds(result)
      block = result.groups.first
      assert_equal ":o.1", block.covers_first
      assert_equal ":o.3", block.covers_last
      assert_equal ["a-na LUGAL", "ARAD-ka", "lu šul-mu"], block.originals.map(&:text)
      assert_equal "To the king, my lord: your servant. Good health!", block.translation.text
    end

    def test_oracc_translation_side_resolves_back_to_the_tablet
      load_tablet_pair

      result = run_parallel(TABLET_EN_URN, lang: "akk")
      assert_equal TABLET_EN_URN, result.left.urn
      assert_equal TABLET_URN, result.right.urn
    end

    def test_oracc_tablet_without_a_translation_has_no_sibling
      load_edition(TABLET_URN, "akk", [["o.1", "a-na LUGAL"]])

      result = run_parallel(TABLET_URN)
      assert_nil result.right
      assert_empty result.groups
    end

    def test_oracc_sibling_lookup_never_crosses_tablets
      load_edition(TABLET_URN, "akk", [["o.1", "a-na LUGAL"]])
      load_edition("urn:nabu:oracc:saao-saa01:P224396-en", "eng", [["o.1", "Other tablet."]])

      result = run_parallel(TABLET_URN)
      assert_nil result.right, "an -en document of a DIFFERENT tablet is not a sibling"
    end

    def test_unknown_urn_returns_nil
      load_default_pair
      assert_nil run_parallel("urn:cts:greekLit:tg1.w1.nope")
    end

    # -- Freising monuments (P13-11): bs<n> ↔ bs<n>-dt/-pt/-tr-* -----------------

    BS_URN = "urn:nabu:freising:bs1"

    def load_monument_layers
      load_edition(BS_URN, "sl",
                   [%w[1 GLAGOLITE], %w[2 Bose]], title: "BS I — critical")
      load_edition("#{BS_URN}-dt", "sl",
                   [%w[1 GLAGOLITE·], %w[2 Boſe]], title: "BS I — diplomatic")
      load_edition("#{BS_URN}-tr-slv", "sl",
                   [%w[1 GOVORITE], %w[2 Bog]], title: "BS I — modern Slovene")
      load_edition("#{BS_URN}-tr-eng", "eng",
                   [%w[1 SAY], %w[2 God]], title: "BS I — English")
    end

    def test_freising_monument_finds_its_translation_sibling_as_verse_pairs
      load_monument_layers

      result = run_parallel(BS_URN)
      assert_equal "#{BS_URN}-tr-eng", result.right.urn
      assert_equal %i[pair pair], kinds(result), "line-for-line layers pair 1:1"
      assert_equal(%w[SAY God], result.groups.map { |g| g.translation.text })
    end

    def test_freising_translation_resolves_back_to_the_critical_primary
      load_monument_layers

      result = run_parallel("#{BS_URN}-tr-eng", lang: "sl")
      assert_equal BS_URN, result.right.urn,
                   "the work's own document outranks its -dt/-tr-slv variants"
    end

    def test_freising_sibling_lookup_never_crosses_monuments
      load_edition(BS_URN, "sl", [%w[1 GLAGOLITE]])
      load_edition("urn:nabu:freising:bs2-tr-eng", "eng", [%w[1 If]])

      result = run_parallel(BS_URN)
      assert_nil result.right, "an English layer of a DIFFERENT monument is not a sibling"
    end

    # -- Damaskini witnesses (P23-1): <doc-id> ↔ <doc-id>-en ---------------------

    DAM_URN = "urn:nabu:damaskini:veles--trojanskata"

    def test_damaskini_witness_finds_its_en_sibling_as_verse_pairs
      load_edition(DAM_URN, "chu",
                   [%w[5601 slovo], ["5602", "kako oubi siona"]], title: "Trojanska")
      load_edition("#{DAM_URN}-en", "eng",
                   [%w[5601 Chapter], ["5602", "How he slew Sion"]], title: "Trojanska — English")

      result = run_parallel(DAM_URN)
      assert_equal "#{DAM_URN}-en", result.right.urn
      assert_equal %i[pair pair], kinds(result), "sentence-for-sentence siblings pair 1:1"

      back = run_parallel("#{DAM_URN}-en", lang: "chu")
      assert_equal DAM_URN, back.right.urn, "the -en resolves back to its witness"
    end

    def test_damaskini_sibling_lookup_never_crosses_witnesses
      load_edition(DAM_URN, "chu", [%w[5601 slovo]])
      load_edition("urn:nabu:damaskini:berlinski--slovo-petki-en", "eng", [%w[1 sun]])

      result = run_parallel(DAM_URN)
      assert_nil result.right, "an -en document of a DIFFERENT witness is not a sibling — " \
                               "hyphen-rich doc ids must not confuse the variant split"
    end

    # -- SuttaCentral texts (P26-1): <stem> ↔ <stem>-en --------------------------

    SC_URN = "urn:nabu:suttacentral:sn35.24"

    def test_suttacentral_root_finds_its_en_sibling_as_verse_pairs
      load_edition(SC_URN, "pli",
                   [["1.1", "“Sabbappahānāya vo, bhikkhave, dhammaṁ desessāmi."],
                    ["1.2", "Taṁ suṇātha."]], title: "Pahānasutta")
      load_edition("#{SC_URN}-en", "eng",
                   [["1.1", "“Mendicants, I will teach you the principle for giving up the all."],
                    ["1.2", "Listen …"]], title: "Giving Up")

      result = run_parallel(SC_URN)
      assert_equal "#{SC_URN}-en", result.right.urn
      assert_equal %i[pair pair], kinds(result), "shared segment ids pair 1:1"

      back = run_parallel("#{SC_URN}-en", lang: "pli")
      assert_equal SC_URN, back.right.urn, "the -en resolves back to its root text"
    end

    def test_suttacentral_sibling_lookup_never_crosses_texts
      load_edition(SC_URN, "pli", [["1.1", "Sabbappahānāya"]])
      load_edition("urn:nabu:suttacentral:dhp21-32-en", "eng", [["dhp21:1", "Heedfulness"]])

      result = run_parallel(SC_URN)
      assert_nil result.right, "an -en document of a DIFFERENT text is not a sibling — " \
                               "hyphen-rich range stems must not confuse the variant split"
    end

    # -- visibility (show-family semantics) --------------------------------------

    def test_withdrawn_passages_are_included_and_flagged
      load_edition(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε]], title: "Iliad")
      load_edition(ENG_URN, "eng", [%w[1 Wrath], %w[2 sing]], title: "Iliad (tr.)")
      Nabu::Store::Passage.first(urn: "#{ENG_URN}:1").update(withdrawn: true)

      result = run_parallel(GRC_URN)
      pair = result.groups.find { |group| group.anchor == ":1" }
      assert pair.translation.withdrawn, "parallel is a show-family inspector: withdrawn shown, flagged"
    end
  end
end
