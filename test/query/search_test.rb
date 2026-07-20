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

    def test_lang_filter_accepts_the_equivalent_iso_code_spelling
      # ger/deu are one language in two legit ISO 639-2 spellings (aes vs
      # tla-hf); the filter expands the equivalence set, fold-both-sides.
      doc = make_document(source: @open, urn: "urn:d:1", language: "deu")
      make_passage(doc, urn: "urn:d:1:1", text: "kein Mann und keine Frau", sequence: 0, language: "deu")
      rebuild!

      assert_equal 1, search("mann", lang: "ger").size, "ger must match deu passages"
      assert_equal 1, search("mann", lang: "de").size, "two-letter de too"
      assert_equal 1, search("mann", lang: "deu").size
    end

    # -- FTS5 syntax hardening (owner report 2026-07-18: `search --help`
    # crashed with a raw fts5 backtrace; any hyphen-leading token does) ----

    def test_query_with_leading_hyphen_falls_back_to_literal_matching
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "the --help flag itself", sequence: 0, language: "eng")
      rebuild!

      results = search("--help")
      assert_equal 1, results.size, "fts5-invalid syntax must retry literally, not crash"
      assert_equal "urn:d:1:1", results.first.urn
    end

    def test_hyphenated_query_finds_the_hyphenated_text_literally
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "a beer-jug of Praeneste", sequence: 0, language: "eng")
      rebuild!

      results = search("beer-jug")
      assert_equal 1, results.size, "hyphen is an fts5 operator — the literal retry must land"
    end

    def test_unbalanced_quote_query_never_raises_a_raw_database_error
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "an unclosed thought", sequence: 0, language: "eng")
      rebuild!

      results = search('"unclosed')
      assert_equal 1, results.size, "the doubled-quote literal retry must survive an unbalanced quote"
    end

    def test_deliberate_fts_syntax_still_works_untouched
      # The REAL power syntax the fold preserves: quoted phrases and prefix
      # stars. (Uppercase AND/OR/NOT never survived the fold — it lowercases
      # them into plain terms — so they are not protected behavior.)
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text: "ἄειδε μῆνιν πάλιν", sequence: 1)
      rebuild!

      phrase = search('"μηνιν αειδε"')
      assert_equal ["urn:d:1:1"], phrase.map(&:urn), "the quoted phrase must stay a phrase"
      prefix = search("μην*")
      assert_equal 2, prefix.size, "the prefix star must stay a prefix query"
    end

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

    # -- cross-script neutralization (P27-2) ---------------------------------

    # OWNER REPRO (2026-07-18b), pinned end to end: `search vъsta` returned
    # damaskini's Latin-diplomatic hits, `search въста` the Cyrillic shelves'
    # — disjoint sets for the same word. Either spelling must now return the
    # UNION of both shelves.
    def test_slavic_query_spellings_return_the_union_of_both_scripts
      latin = make_document(source: @open, urn: "urn:d:dam", title: "Damaskini", language: "bul")
      make_passage(latin, urn: "urn:d:dam:1", text: "i vъsta petka", sequence: 0, language: "bul")
      cyrillic = make_document(source: @open, urn: "urn:d:zogr", title: "Zographensis", language: "chu")
      make_passage(cyrillic, urn: "urn:d:zogr:1", text: "и въста мариꙗ", sequence: 0, language: "chu")
      rebuild!

      union = %w[urn:d:dam:1 urn:d:zogr:1]
      assert_equal union, search("vъsta").map(&:urn).sort, "Latin-diplomatic spelling reaches both shelves"
      assert_equal union, search("въста").map(&:urn).sort, "Cyrillic spelling reaches both shelves"
    end

    # OWNER REPRO (2026-07-18a), pinned end to end: the Devanagari spelling
    # (as nabu's own reflex render prints it) and the IAST spelling find the
    # same passages — SARIT-style Devanagari and DCS-style IAST alike.
    def test_devanagari_and_iast_query_spellings_find_both_script_shelves
      deva = make_document(source: @open, urn: "urn:d:sarit", title: "Sarit", language: "san-Deva")
      make_passage(deva, urn: "urn:d:sarit:1", text: "धर्मन् इति", sequence: 0, language: "san-Deva")
      iast = make_document(source: @open, urn: "urn:d:dcs", title: "DCS", language: "san")
      make_passage(iast, urn: "urn:d:dcs:1", text: "dharman iti", sequence: 0, language: "san")
      rebuild!

      union = %w[urn:d:dcs:1 urn:d:sarit:1]
      assert_equal union, search("धर्मन्").map(&:urn).sort, "the pasted reflex-render form finds its passages"
      assert_equal union, search("dharman").map(&:urn).sort, "the IAST spelling finds the same set"
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

    # --source SLUG (P22-1): scope hits to one source; composes with the
    # other catalog-side filters.
    def test_source_filter_scopes_to_one_source
      open_doc = make_document(source: @open, urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "libertas", sequence: 0)
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "libertas", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:nc:1], search("libertas", source: "nc").map(&:urn)
      assert_equal %w[urn:d:nc:1], search("libertas", source: "nc", license: "nc").map(&:urn)
      assert_empty search("libertas", source: "nc", license: "open"), "filters compose"
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

    # -- the date/place axis filter (P15-2) ----------------------------------

    def dated(urn, text, not_before, not_after, place: nil)
      doc = make_document(source: @open, urn: urn)
      make_passage(doc, urn: "#{urn}:1", text: text, sequence: 1, language: "grc")
      @catalog[:document_axes].insert(
        document_id: doc.id, not_before: not_before, not_after: not_after,
        precision: "x", place_name: place, axis_source: "hgv"
      )
    end

    def test_from_to_filter_uses_interval_overlap
      dated("urn:a", "στρατηγος", -113, -113)  # 113 BCE point
      dated("urn:b", "στρατηγος", 591, 602)    # 6th–7th c. CE
      dated("urn:c", "στρατηγος", -30, 14)     # 30 BCE – 14 CE
      rebuild!
      # -300..-30 overlaps a (-113) and c (starts -30); NOT b.
      assert_equal %w[urn:a:1 urn:c:1], search("στρατηγος", from: -300, to: -30).map(&:urn).sort
      # A window ending at 40 BCE misses c (starts 30 BCE) — the boundary case.
      assert_equal %w[urn:a:1], search("στρατηγος", from: -300, to: -40).map(&:urn).sort
      assert_equal %w[urn:b:1], search("στρατηγος", from: 500).map(&:urn).sort
    end

    def test_open_ended_axis_row_survives_a_from_filter
      dated("urn:a", "στρατηγος", nil, -257) # notAfter-only → not_before is −∞
      rebuild!
      # A NULL not_after would silently drop this row from a --to query; a NULL
      # not_before must NOT drop it from a --from query below its known bound.
      assert_equal %w[urn:a:1], search("στρατηγος", from: -400).map(&:urn)
      assert_empty search("στρατηγος", from: -100), "row is entirely before 100 BCE"
    end

    def test_place_filter_is_a_case_insensitive_like
      dated("urn:a", "στρατηγος", -113, -113, place: "Oxyrhynchus")
      dated("urn:b", "στρατηγος", -30, 14, place: "Arsinoites")
      rebuild!
      assert_equal %w[urn:a:1], search("στρατηγος", place: "oxyrhynch%").map(&:urn)
      assert_equal %w[urn:a:1], search("στρατηγος", place: "Oxyrhynchus").map(&:urn)
    end

    def test_undated_documents_fall_out_under_a_date_filter
      make_passage(make_document(source: @open, urn: "urn:undated"),
                   urn: "urn:undated:1", text: "στρατηγος", sequence: 1, language: "grc")
      dated("urn:a", "στρατηγος", -113, -113)
      rebuild!
      assert_equal %w[urn:a:1], search("στρατηγος", from: -400, to: 100).map(&:urn),
                   "no axis row → absent under an active date filter"
      assert_equal 2, search("στρατηγος").map(&:urn).size, "both visible without a date filter"
    end

    # -- the facet filter (P17-2, document_facets) -----------------------------

    def faceted(urn, text, facets, not_before: nil, not_after: nil)
      doc = make_document(source: @open, urn: urn, language: "lat")
      make_passage(doc, urn: "#{urn}:1", text: text, sequence: 1, language: "lat")
      facets.each do |facet, (value, raw)|
        @catalog[:document_facets].insert(document_id: doc.id, facet: facet, value: value, raw: raw)
      end
      if not_before || not_after
        @catalog[:document_axes].insert(document_id: doc.id, not_before: not_before,
                                        not_after: not_after, axis_source: "edh")
      end
      doc
    end

    def test_facet_filter_matches_value_case_insensitively
      faceted("urn:e:1", "dis manibus", { "genre" => %w[epitaph titsep] })
      faceted("urn:e:2", "dis manibus", { "genre" => ["votive inscription", "titsac"] })
      rebuild!
      assert_equal %w[urn:e:1:1], search("manibus", facets: { "genre" => "Epitaph" }).map(&:urn)
      assert_equal %w[urn:e:2:1], search("manibus", facets: { "genre" => "votive%" }).map(&:urn)
    end

    def test_facet_filter_matches_the_raw_code_too
      faceted("urn:e:1", "dis manibus", { "genre" => ["epitaph", "titsep?"] })
      rebuild!
      assert_equal %w[urn:e:1:1], search("manibus", facets: { "genre" => "titsep?" }).map(&:urn),
                   "the raw code (certainty rider included) is queryable"
    end

    def test_facet_filters_compose_with_each_other_and_the_date_axis
      faceted("urn:e:1", "dis manibus",
              { "genre" => %w[epitaph titsep], "province" => ["Pannonia inferior", "PaI"] },
              not_before: 101, not_after: 200)
      faceted("urn:e:2", "dis manibus",
              { "genre" => %w[epitaph titsep], "province" => %w[Britannia Bri] },
              not_before: 101, not_after: 200)
      faceted("urn:e:3", "dis manibus",
              { "genre" => %w[epitaph titsep], "province" => ["Pannonia inferior", "PaI"] },
              not_before: 301, not_after: 400)
      rebuild!
      hits = search("manibus", facets: { "genre" => "epitaph", "province" => "pannonia%" },
                               from: 101, to: 200)
      assert_equal %w[urn:e:1:1], hits.map(&:urn),
                   "genre AND province AND the date window must all hold"
    end

    def test_unfaceted_documents_fall_out_under_a_facet_filter
      make_passage(make_document(source: @open, urn: "urn:plain", language: "lat"),
                   urn: "urn:plain:1", text: "dis manibus", sequence: 1, language: "lat")
      faceted("urn:e:1", "dis manibus", { "genre" => %w[epitaph titsep] })
      rebuild!
      assert_equal %w[urn:e:1:1], search("manibus", facets: { "genre" => "epitaph" }).map(&:urn),
                   "no facet row → absent under an active facet filter"
      assert_equal 2, search("manibus").size, "both visible without a facet filter"
    end

    # -- the loans facet (P34-2 — the P17-1 promise: per-passage loan-code
    # counts already ride annotations["loans"]; the facet READS them, no
    # reparse, no extra table) ---------------------------------------------

    # A passage whose annotations carry the P17-1 loans shape, written with
    # the loader's own serializer (ContentHash.canonical_json), so the test
    # pins the read side of the stored contract.
    def loaned(urn, text, loans, language: "cop")
      doc = make_document(source: @open, urn: urn, language: language)
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{urn}:1", sequence: 1, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: Nabu::Store::ContentHash.canonical_json(
          { "tokens" => [], "loans" => loans }
        ),
        content_sha256: "x", revision: 1
      )
      doc
    end

    def test_loans_filter_keeps_only_passages_carrying_the_code
      loaned("urn:c:1", "ⲡⲛⲟⲩⲧⲉ ⲁⲅⲁⲑⲟⲥ", { "grc" => 2 })
      loaned("urn:c:2", "ⲡⲛⲟⲩⲧⲉ ⲥⲁⲃⲃⲁⲧⲟⲛ", { "hbo" => 1 })
      rebuild!
      assert_equal %w[urn:c:1:1], search("ⲡⲛⲟⲩⲧⲉ", loans: "grc").map(&:urn)
      assert_equal %w[urn:c:2:1], search("ⲡⲛⲟⲩⲧⲉ", loans: "hbo").map(&:urn)
      assert_equal 2, search("ⲡⲛⲟⲩⲧⲉ").size, "both visible without a loans filter"
    end

    def test_loans_filter_matches_verbatim_codes_case_insensitively
      # Unknown upstream language names pass through verbatim ("Akkadian");
      # the filter matches them case-insensitively, the house facet rule.
      loaned("urn:c:1", "ⲡⲛⲟⲩⲧⲉ", { "Akkadian" => 1 })
      rebuild!
      assert_equal %w[urn:c:1:1], search("ⲡⲛⲟⲩⲧⲉ", loans: "akkadian").map(&:urn)
      assert_equal %w[urn:c:1:1], search("ⲡⲛⲟⲩⲧⲉ", loans: "Akkadian").map(&:urn)
    end

    def test_loanless_passages_fall_out_under_a_loans_filter
      # No loans key at all (the parser omits the empty hash) AND a passage
      # whose text mentions "loans" but has no loans annotation — the JSON
      # probe must not be fooled by a substring.
      doc = make_document(source: @open, urn: "urn:plain", language: "eng")
      make_passage(doc, urn: "urn:plain:1", text: "loans of the temple", sequence: 1, language: "eng")
      loaned("urn:c:1", "loans of the temple", { "grc" => 1 }, language: "eng")
      rebuild!
      assert_equal %w[urn:c:1:1], search("loans temple", loans: "grc").map(&:urn),
                   "a loans-free passage falls out, even when its text says 'loans'"
    end

    def test_unknown_loan_code_is_an_honest_absence
      loaned("urn:c:1", "ⲡⲛⲟⲩⲧⲉ", { "grc" => 2 })
      rebuild!
      assert_empty search("ⲡⲛⲟⲩⲧⲉ", loans: "xyz"), "an unattested code finds nothing, never errors"
    end

    def test_loans_filter_composes_with_lang
      loaned("urn:c:1", "ⲡⲛⲟⲩⲧⲉ ⲁⲅⲁⲑⲟⲥ", { "grc" => 1 }, language: "cop")
      loaned("urn:c:2", "ⲡⲛⲟⲩⲧⲉ ⲁⲅⲁⲑⲟⲥ", { "grc" => 1 }, language: "eng")
      rebuild!
      assert_equal %w[urn:c:1:1], search("ⲡⲛⲟⲩⲧⲉ", loans: "grc", lang: "cop").map(&:urn)
    end
  end
end
