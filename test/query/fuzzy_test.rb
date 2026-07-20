# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Fuzzy (P16-4). Catalog is a fresh in-memory SQLite (the house
  # store-test pattern); the fulltext db is a SEPARATE in-memory connection
  # rebuilt with the real Indexer and a documentary fuzzy scope — so trigram
  # extraction, candidate lookup, and the verify phase are exercised end to
  # end against the production folding.
  class FuzzyTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @papyri = Nabu::Store::Source.create(
        slug: "pap", name: "Papyri", adapter_class: "TestAdapter", license_class: "open"
      )
      @literary = Nabu::Store::Source.create(
        slug: "lit", name: "Literary", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(source: @papyri, urn: "urn:d:#{source.slug}", language: "grc")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "t", language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    # text_normalized minted the way the adapter boundary mints it, so the
    # verify phase runs against the real per-language document form.
    def make_passage(document, urn:, text:, sequence:, language: "grc", withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!(fuzzy_slugs: ["pap"])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, fuzzy_slugs: fuzzy_slugs)
    end

    def fuzzy
      Nabu::Query::Fuzzy.new(catalog: @catalog, fulltext: @fulltext)
    end

    def fuzzy_run(fragment, **) = fuzzy.run(fragment, **)

    # -- infix matching + folding --------------------------------------------

    def test_mid_word_fragment_matches
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "τῶι στρατηγῶι χαίρειν", sequence: 0)
      rebuild!

      results = fuzzy_run("ρατηγ")
      assert_equal %w[urn:d:pap:1], results.map(&:urn), "an infix fragment must hit — the FTS gap this fills"
      assert_equal "τῶι στρατηγῶι χαίρειν", results.first.text, "pristine text rides along for display"
    end

    # The papyrological use case, typed straight off the edition: brackets
    # stripped from the QUERY, diacritics folded on both sides.
    def test_real_greek_fragment_with_editorial_brackets
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "μῆνιν ἄειδε θεὰ Πηληϊάδεω", sequence: 0)
      rebuild!

      results = fuzzy_run("]μηνιν αει[")
      assert_equal %w[urn:d:pap:1], results.map(&:urn)
      assert_match(/\[μηνιν αει\]/, results.first.snippet, "the fragment is bracketed in the folded snippet")
    end

    # Determinative-stripped Akkadian: the stored akk fold opens {d} and the
    # sign-join dashes to spaces ({d}en-lil2 → " d en lil2"); the query's akk
    # variant folds the same way, so the transliterated fragment still lands.
    def test_akkadian_fragment_crosses_determinative_and_sign_joins
      doc = make_document(language: "akk")
      make_passage(doc, urn: "urn:d:pap:1", text: "{d}en-lil₂-la₂ lugal", sequence: 0, language: "akk")
      rebuild!

      results = fuzzy_run("en-lil₂")
      assert_equal %w[urn:d:pap:1], results.map(&:urn),
                   "the akk query variant must fold sign-joins exactly as the stored form did"
    end

    def test_final_sigma_fragment_matches_via_the_grc_variant
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "στρατηγὸς ἀγαθός", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:pap:1], fuzzy_run("γός").map(&:urn), "ς folds to σ on the query side too"
    end

    # -- candidate-then-verify -----------------------------------------------

    # Trigram co-occurrence is not contiguity: this passage carries every
    # trigram of "abcd" (abc, bcd) without containing it, so it becomes a
    # phase-1 candidate that phase 2 must reject.
    def test_trigram_collision_false_candidate_rejected_by_verify
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "abc xyz bcd", sequence: 0)
      make_passage(doc, urn: "urn:d:pap:2", text: "zz abcd zz", sequence: 1)
      rebuild!

      candidates = @fulltext[Nabu::Store::Indexer::TRIGRAM_TABLE]
                   .where(Sequel.lit("passages_trigram MATCH ?", '"abc" "bcd"')).count
      assert_equal 2, candidates, "precondition: the collision text IS a trigram candidate"
      assert_equal %w[urn:d:pap:2], fuzzy_run("abcd").map(&:urn), "verify must reject the non-substring candidate"
    end

    # -- scope gating ----------------------------------------------------------

    def test_literary_source_not_indexed_documentary_still_hit
      make_passage(make_document, urn: "urn:d:pap:1", text: "στρατηγος", sequence: 0)
      make_passage(make_document(source: @literary), urn: "urn:d:lit:1", text: "στρατηγος", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:pap:1], fuzzy_run("ρατηγ").map(&:urn),
                   "the same fragment in a literary passage stays invisible to --fuzzy"
    end

    # -- the facet filter composes (P17-2) --------------------------------------

    def test_facet_filter_composes_with_fuzzy
      epitaph = make_document(urn: "urn:d:epitaph", language: "lat")
      make_passage(epitaph, urn: "urn:d:epitaph:1", text: "dis manibus sacrum", sequence: 0, language: "lat")
      votive = make_document(urn: "urn:d:votive", language: "lat")
      make_passage(votive, urn: "urn:d:votive:1", text: "dis manibus votum", sequence: 0, language: "lat")
      @catalog[:document_facets].insert(document_id: epitaph.id, facet: "genre",
                                        value: "epitaph", raw: "titsep")
      @catalog[:document_facets].insert(document_id: votive.id, facet: "genre",
                                        value: "votive inscription", raw: "titsac")
      rebuild!

      assert_equal %w[urn:d:epitaph:1 urn:d:votive:1], fuzzy_run("s manibus").map(&:urn).sort
      assert_equal %w[urn:d:epitaph:1],
                   fuzzy_run("s manibus", facets: { "genre" => "epitaph" }).map(&:urn),
                   "the mid-word fragment scoped to one genre facet"
    end

    def test_scope_reports_the_built_slugs
      rebuild!
      assert_equal %w[pap], fuzzy.scope
    end

    def test_scope_nil_when_the_fulltext_predates_the_trigram_index
      rebuild!
      @fulltext.drop_table?(Nabu::Store::Indexer::TRIGRAM_SCOPE_TABLE)
      assert_nil fuzzy.scope
    end

    # -- the trigram floor -----------------------------------------------------

    def test_short_fragment_raises_query_too_short
      rebuild!
      error = assert_raises(Nabu::Query::Fuzzy::QueryTooShort) { fuzzy_run("αε") }
      assert_equal "αε", error.folded
    end

    def test_fragment_that_folds_away_raises_query_too_short
      rebuild!
      # Brackets stripped, then folding leaves two characters.
      assert_raises(Nabu::Query::Fuzzy::QueryTooShort) { fuzzy_run("]ἄε[") }
    end

    # -- filters ---------------------------------------------------------------

    def test_lang_filter_composes
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "στρατηγος", sequence: 0)
      make_passage(doc, urn: "urn:d:pap:2", text: "στρατηγος praefectus", sequence: 1, language: "lat")
      rebuild!

      assert_equal %w[urn:d:pap:2], fuzzy_run("ρατηγ", lang: "lat").map(&:urn)
    end

    def test_limit_caps_the_page
      doc = make_document
      3.times { |i| make_passage(doc, urn: "urn:d:pap:#{i}", text: "στρατηγος #{i}", sequence: i) }
      rebuild!

      assert_equal 2, fuzzy_run("ρατηγ", limit: 2).size
    end

    def test_withdrawn_passage_never_returned
      doc = make_document
      make_passage(doc, urn: "urn:d:pap:1", text: "στρατηγος", sequence: 0, withdrawn: true)
      rebuild!

      assert_empty fuzzy_run("ρατηγ")
    end

    # -- snippets ---------------------------------------------------------------

    def test_snippet_windows_long_text_and_folded_marked_does_not
      doc = make_document
      long_text = "#{'α' * 60} στρατηγος #{'ω' * 60}"
      make_passage(doc, urn: "urn:d:pap:1", text: long_text, sequence: 0)
      rebuild!

      result = fuzzy_run("ρατηγ").first
      assert_match(/…/, result.snippet, "clipped context is marked")
      assert_operator result.snippet.length, :<, result.folded_marked.length
      assert_match(/\A#{'α' * 60} στ\[ρατηγ\]οσ #{'ω' * 60}\z/, result.folded_marked,
                   "--long form is the whole folded passage, match bracketed")
    end
    # -- the exhausted-inner-window honesty hint (P35-6, dev-loop §6b) --------
    # Ten short candidates outrank (bm25) the one lat-labeled longer row;
    # limit 1 makes the trigram candidate window exactly 10, so the lang
    # filter empties the page while a verified match exists beyond it.

    def seed_window_exhausting_fragments(grc_rows: 10)
      doc = make_document
      grc_rows.times do |i|
        make_passage(doc, urn: "urn:d:pap:#{i}", text: "τῶι στρατηγῶι", sequence: i)
      end
      lat_doc = make_document(source: @papyri, urn: "urn:d:pap-lat", language: "lat")
      make_passage(lat_doc, urn: "urn:d:pap-lat:1", sequence: 0, language: "lat",
                            text: "στρατηγ down the rank because this passage carries many more words than the rest")
      rebuild!
    end

    def test_exhausted_inner_window_under_filters_reports_the_incomplete_page
      seed_window_exhausting_fragments

      query = fuzzy
      results = query.run("ρατηγ", lang: "lat", limit: 1)
      assert_empty results, "the candidate window holds only filter-rejected rows (the P34 gate repro)"
      assert_equal Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT, query.incomplete_hint,
                   "an empty page with matches beyond the window must announce itself"
    end

    def test_unexhausted_window_or_full_page_carries_no_hint
      seed_window_exhausting_fragments(grc_rows: 3)

      query = fuzzy
      assert_equal %w[urn:d:pap-lat:1], query.run("ρατηγ", lang: "lat", limit: 1).map(&:urn)
      assert_nil query.incomplete_hint, "the window reached the lat row — the page is honest"

      refute_empty query.run("ρατηγ", limit: 1)
      assert_nil query.incomplete_hint, "no catalog-side filter was active"
    end
  end
end
