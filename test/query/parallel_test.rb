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
