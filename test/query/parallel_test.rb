# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Parallel (P7-4): resolve a document or passage urn to its
  # sibling edition of the same CTS work in a target language and align the
  # two passage lists by citation suffix. Catalog is a fresh in-memory SQLite
  # seeded through the real Loader (the house store-test pattern).
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

    def run_parallel(urn, lang: "eng")
      Nabu::Query::Parallel.new(catalog: @catalog).run(urn, lang: lang)
    end

    # -- alignment (document scope) -------------------------------------------

    def test_document_urn_aligns_by_citation_suffix_with_one_sided_rows
      load_default_pair

      result = run_parallel(GRC_URN)
      assert_equal GRC_URN, result.left.urn
      assert_equal "grc", result.left.language
      assert_equal "Iliad", result.left.title
      assert_equal ENG_URN, result.right.urn
      assert_equal "eng", result.right.language

      # Rows follow the left document's order; a right-only suffix ("pref")
      # is interleaved by the right document's own sequence — it precedes the
      # ":1" pair; ":2" has no translation and renders one-sided.
      assert_equal [":pref", ":1", ":2", ":3"], result.rows.map(&:suffix)
      pref, one, two, three = result.rows
      assert_nil pref.left
      assert_equal "Preface", pref.right.text
      assert_equal %w[μῆνιν Wrath], [one.left.text, one.right.text]
      assert_equal "ἄειδε", two.left.text
      assert_nil two.right
      assert_equal %w[θεά goddess], [three.left.text, three.right.text]
    end

    def test_alignment_is_symmetric_from_the_translation_side
      load_default_pair

      result = run_parallel(ENG_URN, lang: "grc")
      assert_equal ENG_URN, result.left.urn
      assert_equal GRC_URN, result.right.urn
      # Left is now the eng edition; grc-only :2 interleaves between the pairs.
      assert_equal [":pref", ":1", ":2", ":3"], result.rows.map(&:suffix)
      assert_nil result.rows[2].left
      assert_equal "ἄειδε", result.rows[2].right.text
    end

    # -- passage scope ---------------------------------------------------------

    def test_passage_urn_scopes_to_its_single_suffix
      load_default_pair

      result = run_parallel("#{GRC_URN}:1")
      assert_equal ":1", result.scope
      assert_equal [":1"], result.rows.map(&:suffix)
      assert_equal %w[μῆνιν Wrath], [result.rows[0].left.text, result.rows[0].right.text]
    end

    def test_passage_without_a_counterpart_renders_one_sided
      load_default_pair

      result = run_parallel("#{GRC_URN}:2")
      assert_equal [":2"], result.rows.map(&:suffix)
      assert_equal "ἄειδε", result.rows[0].left.text
      assert_nil result.rows[0].right
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
      assert_empty result.rows
    end

    def test_no_sibling_in_the_requested_language_returns_result_without_right
      load_default_pair

      result = run_parallel(GRC_URN, lang: "lat")
      assert_equal GRC_URN, result.left.urn
      assert_nil result.right
      assert_empty result.rows
    end

    def test_non_cts_urn_has_no_siblings
      load_edition("urn:nabu:ddbdp:aegyptus:89:240", "grc", [%w[1 κτλ]])

      result = run_parallel("urn:nabu:ddbdp:aegyptus:89:240")
      refute_nil result
      assert_nil result.right
    end

    def test_unknown_urn_returns_nil
      load_default_pair
      assert_nil run_parallel("urn:cts:greekLit:tg1.w1.nope")
    end

    # -- visibility (show-family semantics) --------------------------------------

    def test_withdrawn_passages_are_included_and_flagged
      load_default_pair
      Nabu::Store::Passage.first(urn: "#{ENG_URN}:1").update(withdrawn: true)

      result = run_parallel(GRC_URN)
      pair = result.rows.find { |row| row.suffix == ":1" }
      assert pair.right.withdrawn, "parallel is a show-family inspector: withdrawn shown, flagged"
    end
  end
end
