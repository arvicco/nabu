# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Search (P4-2). Catalog is a fresh in-memory SQLite (the house
  # store-test pattern); the fulltext index is a SEPARATE in-memory connection
  # held open for the whole test and rebuilt from the seeded catalog with the
  # real Indexer — so the fold-both-sides contract is exercised end to end.
  class SearchTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @open = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
      @nc = Nabu::Store::Source.create(
        slug: "nc", name: "NC", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(source:, urn:, title: "Iliad", language: "grc",
                      license_override: nil, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        license_override: license_override, content_sha256: "x",
        revision: 1, withdrawn: withdrawn
      )
    end

    # text_normalized is minted the way the adapter boundary mints it
    # (Passage.new → Normalize.search_form), so every search test exercises
    # the real per-language document form (P6-4).
    def make_passage(document, urn:, text:, sequence:, language: "grc", withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def search(query, **)
      Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext).run(query, **)
    end

    # -- tests ---------------------------------------------------------------

    def test_accented_query_matches_the_accented_passage
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      rebuild!

      results = search("μῆνιν")
      assert_equal 1, results.size
      assert_equal "urn:d:1:1", results.first.urn
      # The pristine (accented) text is returned for display, not the folded form.
      assert_equal "μῆνιν ἄειδε θεά", results.first.text
    end

    # The fold-both-sides proof: a passage stored WITH polytonic accents is found
    # by an UNACCENTED query, because index and query pass the same fold.
    def test_unaccented_query_matches_the_accented_passage
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      rebuild!

      results = search("μηνιν")
      assert_equal 1, results.size
      assert_equal "urn:d:1:1", results.first.urn
    end

    # -- per-language fold-both-sides (P6-4) ---------------------------------

    # Greek final sigma: the passage ends the word in ς, the doc-side fold
    # stores σ, and BOTH query spellings find it (the grc query variant folds
    # ς→σ; the accented spelling additionally proves marks + sigma compose).
    def test_final_sigma_query_spellings_both_match
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "ἄρχε δ’ ἀοιδῆς", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:1:1], search("αοιδησ").map(&:urn), "internal-sigma spelling"
      assert_equal %w[urn:d:1:1], search("ἀοιδῆς").map(&:urn), "accented final-sigma spelling"
    end

    # Latin v/u and j/i: the document keeps the editor's spelling in text,
    # folds to u/i in the search form, and both query spellings find it.
    def test_latin_v_u_and_j_i_query_spellings_both_match
      doc = make_document(source: @open, urn: "urn:d:1", language: "lat")
      make_passage(doc, urn: "urn:d:1:1", sequence: 0, language: "lat", text: "Arma virumque iustitiamque")
      rebuild!

      assert_equal %w[urn:d:1:1], search("virumque").map(&:urn), "v spelling"
      assert_equal %w[urn:d:1:1], search("uirumque").map(&:urn), "u spelling"
      assert_equal %w[urn:d:1:1], search("justitiamque").map(&:urn), "j spelling"
      assert_equal %w[urn:d:1:1], search("iustitiamque").map(&:urn), "i spelling"
    end

    # THE union regression: Gothic (generic fold, j is a real letter) must not
    # be broken by the lat j→i query variant — the generic variant still
    # matches because the variants are ORed.
    def test_gothic_j_words_stay_findable_despite_the_latin_query_variant
      doc = make_document(source: @open, urn: "urn:d:1", language: "got")
      make_passage(doc, urn: "urn:d:1:1", text: "jah qiþands", sequence: 0, language: "got")
      rebuild!

      assert_equal %w[urn:d:1:1], search("jah").map(&:urn)
      assert_equal %w[urn:d:1:1], search("Jah").map(&:urn)
    end

    # OCS: real TOROT titlo (U+0483) strips at the boundary; the bare query
    # and the titlo-carrying query both find the passage.
    def test_ocs_titlo_query_spellings_both_match
      doc = make_document(source: @open, urn: "urn:d:1", language: "chu")
      make_passage(doc, urn: "urn:d:1:1", text: "дх҃омь ст҃ъꙇмь", sequence: 0, language: "chu")
      rebuild!

      assert_equal %w[urn:d:1:1], search("дхомь").map(&:urn), "bare spelling"
      assert_equal %w[urn:d:1:1], search("дх҃омь").map(&:urn), "titlo spelling"
    end

    def test_snippet_marks_the_match_in_the_folded_form
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      rebuild!

      snippet = search("μηνιν").first.snippet
      assert_includes snippet, "[μηνιν]", "the matched (folded) token is marked"
    end

    def test_language_filter_excludes_other_languages
      grc = make_document(source: @open, urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "aurora", sequence: 0, language: "grc")
      lat = make_document(source: @open, urn: "urn:d:lat", language: "lat")
      make_passage(lat, urn: "urn:d:lat:1", text: "aurora", sequence: 0, language: "lat")
      rebuild!

      results = search("aurora", lang: "lat")
      assert_equal %w[urn:d:lat:1], results.map(&:urn)
    end

    def test_license_filter_is_exact_class
      open_doc = make_document(source: @open, urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "libertas", sequence: 0)
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "libertas", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:open:1], search("libertas", license: "open").map(&:urn)
      assert_equal %w[urn:d:nc:1], search("libertas", license: "nc").map(&:urn)
    end

    # A document on an "open" source with an "nc" override must filter as nc and
    # report license_class "nc" (P1-3 override wins over source class).
    def test_license_override_wins_over_source_class
      doc = make_document(source: @open, urn: "urn:d:1", license_override: "nc")
      make_passage(doc, urn: "urn:d:1:1", text: "libertas", sequence: 0)
      rebuild!

      assert_empty search("libertas", license: "open"), "override demotes it out of open"
      results = search("libertas", license: "nc")
      assert_equal %w[urn:d:1:1], results.map(&:urn)
      assert_equal "nc", results.first.license_class
    end

    def test_withdrawn_passage_is_excluded
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "libertas", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text: "libertas", sequence: 1, withdrawn: true)
      rebuild!

      assert_equal %w[urn:d:1:1], search("libertas").map(&:urn)
    end

    def test_limit_caps_the_result_count
      doc = make_document(source: @open, urn: "urn:d:1")
      5.times { |i| make_passage(doc, urn: "urn:d:1:#{i}", text: "aurora", sequence: i) }
      rebuild!

      assert_equal 3, search("aurora", limit: 3).size
    end

    # bm25 ranks a passage matching the term more times above one matching it
    # once. Asserted by rank position, not an exact score.
    def test_ranks_denser_matches_first
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:one", text: "aurora nox dies", sequence: 0)
      make_passage(doc, urn: "urn:d:1:many", text: "aurora aurora aurora", sequence: 1)
      rebuild!

      assert_equal "urn:d:1:many", search("aurora").first.urn
    end

    def test_no_match_returns_empty
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "aurora", sequence: 0)
      rebuild!

      assert_empty search("nonexistentword")
    end

    # Regression (found live, P5-5): the health golden replay must be
    # ranking-independent. With a urn: filter the expected passage is found
    # even when it would rank below the limit among many denser matches.
    def test_urn_filter_finds_a_passage_regardless_of_rank
      doc = make_document(source: @open, urn: "urn:d:1")
      25.times { |i| make_passage(doc, urn: "urn:d:1:noise#{i}", text: "aurora aurora aurora", sequence: i) }
      make_passage(doc, urn: "urn:d:1:target", text: "sola aurora inter multa", sequence: 25)
      rebuild!

      refute_includes search("aurora", limit: 10).map(&:urn), "urn:d:1:target",
                      "precondition: the target ranks below the page without the filter"
      assert_equal %w[urn:d:1:target], search("aurora", limit: 1, urn: "urn:d:1:target").map(&:urn)
      assert_empty search("nonexistentword", urn: "urn:d:1:target"),
                   "the urn filter still requires the query to match"
    end
  end
end
