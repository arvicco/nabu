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

    # P43-2: a hit from a credited source carries the credit line (the CLI
    # search footer and the MCP match payload render from it); an ordinary hit
    # carries nil.
    def test_search_hit_carries_the_source_credit_when_present
      credit = "TITUS (J. Gippert, Frankfurt) — Avesta ed. Geldner/Westergaard"
      titus = Nabu::Store::Source.create(
        slug: "titus", name: "TITUS", adapter_class: "TestAdapter",
        license_class: "nc", credit: credit
      )
      doc = make_document(source: titus, urn: "urn:t:1", language: "ave")
      make_passage(doc, urn: "urn:t:1:a", text: "frauuarāne mazdaiiasnō", sequence: 0, language: "ave")
      plain = make_document(source: @open, urn: "urn:d:1", language: "eng")
      make_passage(plain, urn: "urn:d:1:1", text: "frauuarāne the plain one", sequence: 0, language: "eng")
      rebuild!

      credited = search("frauuarāne").find { |r| r.urn == "urn:t:1:a" }
      assert_equal credit, credited.credit
      uncredited = search("frauuarāne").find { |r| r.urn == "urn:d:1:1" }
      assert_nil uncredited.credit
    end

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

    # P37-2, the §9 symmetry proof end to end: kanripo/cbeta store traditional
    # 說, Japanese-transmitted editions write the z-variant 説, a modern typist
    # types simplified 说 — all three query spellings must find the one stored
    # passage, because document AND query fold to the same traditional
    # skeleton (Nabu::Hani, derived from held Unihan variant data).
    def test_han_variant_query_spellings_find_the_traditional_lzh_passage
      doc = make_document(source: @open, urn: "urn:d:kr", title: "Lunyu", language: "lzh")
      make_passage(doc, urn: "urn:d:kr:1", text: "不亦說乎，不亦樂乎", sequence: 0, language: "lzh")
      rebuild!

      %w[不亦說乎 不亦説乎 不亦说乎].each do |spelling|
        assert_equal ["urn:d:kr:1"], search(spelling).map(&:urn),
                     "#{spelling} must fold to the stored traditional skeleton"
      end
    end

    # P38-r1: --exact is the glyph-literal escape hatch. The default fold makes
    # 說/説/说 one skeleton (above); --exact keeps only passages whose STORED
    # text carries the query glyph-for-glyph. The lzh passage stores 說, so
    # --exact 說 finds it while --exact 説 (a candidate under the fold) does not.
    def test_exact_keeps_only_the_glyph_literal_hit_among_folded_candidates
      doc = make_document(source: @open, urn: "urn:d:kr", title: "Lunyu", language: "lzh")
      make_passage(doc, urn: "urn:d:kr:1", text: "不亦說乎，不亦樂乎", sequence: 0, language: "lzh")
      rebuild!

      assert_equal ["urn:d:kr:1"], search("不亦說乎", exact: true).map(&:urn),
                   "the stored glyph 說 matches --exact"
      assert_empty search("不亦説乎", exact: true),
                   "説 is a fold candidate but not the stored glyph — --exact drops it"
      assert_equal ["urn:d:kr:1"], search("不亦説乎").map(&:urn),
                   "without --exact the z-variant still finds the passage"
    end

    # The Japanese reform-merge escape hatch: the default finds 弁 by a 辨 query
    # (the admitted merge); --exact tells them apart.
    def test_exact_distinguishes_an_admitted_japanese_merge
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Ben", language: "jpn")
      make_passage(doc, urn: "urn:d:jp:1", text: "弁論", sequence: 0, language: "jpn")
      rebuild!

      assert_equal ["urn:d:jp:1"], search("辨論").map(&:urn),
                   "the default fold reaches the shinjitai 弁 from a kyūjitai 辨 query"
      assert_equal ["urn:d:jp:1"], search("弁論", exact: true).map(&:urn),
                   "--exact matches the stored shinjitai glyph"
      assert_empty search("辨論", exact: true),
                   "辨 is a merged old form, not the stored glyph — --exact drops it"
    end

    # -- --exact --limit semantics (P39-r3, Defect 1) -------------------------
    # Owner ruling 2026-07-22: "he will understand --limit as the number of
    # ultimate hits to display." The old code fetched limit×10 FOLDED candidates
    # then post-filtered, so --limit was an internal pool size — a literal hit
    # ranked past the first pool was invisible. The scan now paginates until
    # +limit+ VERIFIED hits accumulate.

    # 11 single-glyph 學 passages (fold candidates for 学, but NOT literal 学)
    # each rank as a 1-token document; one longer passage DOES store a
    # space-delimited literal 学 and, being many tokens, ranks last (bm25 favors
    # short docs). With limit 1 the literal hit sits at candidate rank 12, past
    # the first page-of-10. The old code returned empty; the scan paginates to it.
    def test_exact_limit_paginates_past_a_full_page_of_rejected_candidates
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Ben", language: "jpn")
      11.times do |i|
        make_passage(doc, urn: "urn:d:jp:trad:#{i}", text: "學", sequence: i, language: "jpn")
      end
      # 学 is its own token (space-delimited); the extra tokens lengthen the doc
      # so bm25 ranks it last, beyond the first candidate page.
      make_passage(doc, urn: "urn:d:jp:lit", text: "学 天 地 人 山 川 海 空 雨 風 火",
                        sequence: 99, language: "jpn")
      rebuild!

      assert_equal ["urn:d:jp:lit"], search("学", lang: "jpn", exact: true, limit: 1).map(&:urn),
                   "the literal hit past the first candidate page is found (was empty pre-P39-r3)"
    end

    # --limit is a true display cap: more literal matches exist than the limit,
    # so exactly +limit+ come back.
    def test_exact_limit_caps_the_displayed_hits
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Ben", language: "jpn")
      3.times do |i|
        make_passage(doc, urn: "urn:d:jp:#{i}", text: "学", sequence: i, language: "jpn")
      end
      rebuild!

      assert_equal 2, search("学", lang: "jpn", exact: true, limit: 2).size,
                   "--limit N means up to N displayed hits, not an internal pool size"
    end

    # The scan-ceiling honesty guard (P35): a fold-heavy query with no literal
    # hit must terminate AND announce that the scan was truncated.
    def test_exact_scan_ceiling_truncation_announces_itself
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Ben", language: "jpn")
      12.times do |i|
        make_passage(doc, urn: "urn:d:jp:#{i}", text: "學", sequence: i, language: "jpn")
      end
      rebuild!

      # ceiling 10 == one page-of-10 for limit 1; page 1 verifies nothing and
      # the scan stops at the ceiling with candidates still unscanned.
      results = searcher.run("学", lang: "jpn", exact: true, limit: 1, scan_ceiling: 10)
      assert_empty results, "no passage stores the literal 学"
      assert_match(/scanned the first 10 fold candidates/, searcher.incomplete_hint,
                   "a ceiling-truncated scan announces what it did not check")
      refute_match(/raise --limit/, searcher.incomplete_hint.to_s,
                   "the old 'raise --limit to search deeper' note is wrong under the new semantics")
    end

    # An exact scan that reaches stream exhaustion before the ceiling is an
    # honest complete answer — no truncation hint.
    def test_exact_exhausted_scan_carries_no_truncation_hint
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Ben", language: "jpn")
      make_passage(doc, urn: "urn:d:jp:1", text: "学", sequence: 0, language: "jpn")
      make_passage(doc, urn: "urn:d:jp:2", text: "學", sequence: 1, language: "jpn")
      rebuild!

      results = searcher.run("学", lang: "jpn", exact: true, limit: 20, scan_ceiling: 10)
      assert_equal ["urn:d:jp:1"], results.map(&:urn), "the one literal hit is found"
      assert_nil searcher.incomplete_hint, "the whole stream was scanned — this page is complete"
    end

    # P39-r3: the snippet is a window of the STORED text, not the folded index
    # form. An unaccented query still marks the accented stored spelling — the
    # fold LOCATES the match (μηνιν → μῆνιν) but never REPLACES the glyphs.
    def test_snippet_marks_the_match_in_the_stored_text
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε θεά", sequence: 0)
      rebuild!

      snippet = search("μηνιν").first.snippet
      assert_includes snippet, "[μῆνιν]", "the stored (accented) spelling is marked, not the fold"
      refute_includes snippet, "μηνιν", "the accent-stripped fold form is never shown"
    end

    # The Japanese defect (P39-r3): the fold's canonical is a traditional or even
    # archaic skeleton (学→學, だ→た, 一→弌), so the FTS snippet() showed glyphs the
    # passage never held. The stored-text snippet shows what the source actually
    # stored, whether the query was folded or --exact.
    # (Whole-token queries: FTS tokenizes a spaceless CJK/kana run as ONE token,
    # so the fixtures make the queried glyph its own token — punctuation- or
    # space-delimited — rather than relying on sub-token matching.)
    def test_snippet_shows_the_stored_cjk_glyph_not_the_fold_skeleton
      doc = make_document(source: @open, urn: "urn:d:jp", title: "Rongo", language: "jpn")
      make_passage(doc, urn: "urn:d:jp:1", text: "学問。天下", sequence: 0, language: "jpn")
      rebuild!

      folded = search("学問", lang: "jpn").first.snippet
      assert_includes folded, "[学問]", "the stored shinjitai glyphs are shown"
      refute_includes folded, "學", "the traditional fold skeleton is never shown"

      exact = search("学問", lang: "jpn", exact: true).first.snippet
      assert_includes exact, "[学問]", "--exact marks the stored glyphs literally"
      refute_includes exact, "學"
    end

    # Kana voicing marks are stripped by the diacritic fold (だ→た, で→て); the
    # snippet must restore the voiced stored kana.
    def test_snippet_restores_voiced_kana
      doc = make_document(source: @open, urn: "urn:d:kana", language: "jpn")
      make_passage(doc, urn: "urn:d:kana:1", text: "これは だめ", sequence: 0, language: "jpn")
      rebuild!

      snippet = search("だめ", lang: "jpn").first.snippet
      assert_includes snippet, "[だめ]", "the voiced kana is shown as stored"
      refute_includes snippet, "た", "the devoiced fold form is never shown"
    end

    # The fold's canonical for some CJK is an ARCHAIC z-variant (一→弌); the
    # stored snippet shows the ordinary stored glyph.
    def test_snippet_shows_the_stored_glyph_not_the_archaic_canonical
      doc = make_document(source: @open, urn: "urn:d:ichi", language: "jpn")
      make_passage(doc, urn: "urn:d:ichi:1", text: "一 二 三", sequence: 0, language: "jpn")
      rebuild!

      snippet = search("一", lang: "jpn").first.snippet
      assert_includes snippet, "[一]", "the stored glyph is shown"
      refute_includes snippet, "弌", "the archaic fold canonical is never shown"
    end

    # -- --word: whole-word matching (P40-w) ---------------------------------

    # The headline case: --exact is a glyph-literal SUBSTRING, so ἦ finds the ἦ
    # buried in ἦμαρ; --word bounds it to a whole word. Both passages carry the
    # glyph ἦ (one standalone, one only inside ἦμαρ — the standalone word there
    # is ἤ, a DIFFERENT glyph, so it is what pulls the passage into the folded
    # candidate set), so --exact returns both; --exact --word keeps only the one
    # where ἦ stands as its own word.
    def test_word_with_exact_keeps_only_the_whole_word_not_a_fragment
      doc = make_document(source: @open, urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:whole", text: "ἦ μὲν οὖν", sequence: 0)
      make_passage(doc, urn: "urn:d:grc:frag", text: "ἦμαρ ἤ", sequence: 1)
      rebuild!

      assert_equal %w[urn:d:grc:frag urn:d:grc:whole],
                   search("ἦ", exact: true).map(&:urn).sort,
                   "--exact is a substring: the glyph ἦ is present in both passages"
      assert_equal %w[urn:d:grc:whole], search("ἦ", exact: true, word: true).map(&:urn),
                   "--word drops the passage where ἦ only sits inside ἦμαρ"
    end

    # Word boundaries are start/end of text and non-letters (whitespace AND
    # punctuation), by Unicode property — not an ASCII assumption.
    def test_word_boundary_is_punctuation_or_edge
      doc = make_document(source: @open, urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:comma", text: "τόδε, ἦ.", sequence: 0) # flanked by space + period
      make_passage(doc, urn: "urn:d:grc:end", text: "ὅς ἐστιν ἦ", sequence: 1) # at end of text
      rebuild!

      assert_equal %w[urn:d:grc:comma urn:d:grc:end],
                   search("ἦ", exact: true, word: true).map(&:urn).sort,
                   "a whole word ends at punctuation or the edge, not only at whitespace"
    end

    # --word composes with the plain fold, and a combining mark is word-INTERNAL:
    # μᾱ́τηρ carries a combining acute (U+0301 on ᾱ that NFC cannot precompose),
    # yet the unaccented query still lands on it as one whole word, and the
    # snippet brackets the pristine spelling.
    def test_word_composes_with_the_fold_over_a_combining_mark_word
      doc = make_document(source: @open, urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "μᾱ́τηρ ἐστίν", sequence: 0)
      rebuild!

      result = search("ματηρ", word: true).first
      refute_nil result, "the accent-stripped query finds the combining-mark-bearing word"
      assert_includes result.snippet, "[μᾱ́τηρ]", "the whole word is bracketed in its stored spelling"
    end

    # Spaceless scripts have no word boundaries: --word on a Han or kana query is
    # REFUSED loudly (never silently degraded) — the refusal points at --exact.
    def test_word_refuses_spaceless_cjk_and_kana
      msg = "word boundaries are not defined for spaceless CJK text — use --exact for glyph-literal matching"
      assert_equal msg, Nabu::Query::Search.word_refusal_for("学問"), "Han is refused"
      assert_equal msg, Nabu::Query::Search.word_refusal_for("だめ"), "kana is refused"
      assert_nil Nabu::Query::Search.word_refusal_for("λόγος"), "alphabetic Greek is fine"
      assert_nil Nabu::Query::Search.word_refusal_for("한국어"), "Hangul is space-delimited — allowed"

      error = assert_raises(Nabu::Error) { search("学", word: true) }
      assert_equal msg, error.message, "run refuses a spaceless --word query at the library boundary"
    end

    # -- NFC-exempt (hbo/arc) --exact matching, AT MATCH TIME (P40-w item 3) ---

    # Real WLC bytes (Ruth 1:1 בִּימֵי): the dagesh U+05BC precedes the hiriq
    # U+05B4, which is NOT NFC — canonical order swaps them (Normalize's own
    # exemption test pins refute unicode_normalized?). hbo is stored byte-
    # verbatim, so a query typed in canonical order would miss the raw stored
    # bytes if only the query were NFC-folded. --exact NFCs BOTH sides at match
    # time, so it finds the passage; storage and the stored-byte snippet are
    # untouched.
    def test_exact_matches_nfc_divergent_hbo_mark_order
      wlc = "בִּימֵי֙" # בִּימֵי, dagesh-before-hiriq (non-NFC)
      refute wlc.unicode_normalized?(:nfc), "the fixture really is a divergent Masoretic order"
      doc = make_document(source: @open, urn: "urn:d:hbo", language: "hbo")
      make_passage(doc, urn: "urn:d:hbo:1", text: wlc, sequence: 0, language: "hbo")
      rebuild!

      canonical = Nabu::Normalize.nfc(wlc) # a modern query typed in canonical order
      result = search(canonical, exact: true).first
      refute_nil result, "NFC-both matching reconciles the divergent mark order at match time"
      assert_equal "urn:d:hbo:1", result.urn
      assert_equal wlc, result.text, "storage is untouched — the pristine Masoretic bytes"
      assert_includes result.snippet, "[#{wlc}]", "the snippet shows the STORED (non-NFC) byte order"
      refute result.snippet.unicode_normalized?(:nfc), "display is untouched — never NFC-reordered"
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

    # --axis (P37-8): the membership filter is the multi-source generalization
    # of --source — an axis expands to member slugs and hits are scoped to
    # `slug IN (...)`. An empty list is no filter; it AND-composes with every
    # other catalog-side filter.
    def test_sources_membership_filter_scopes_hits
      open_doc = make_document(source: @open, urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "libertas", sequence: 0)
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "libertas", sequence: 0)
      rebuild!

      assert_equal %w[urn:d:nc:1 urn:d:open:1], search("libertas", sources: %w[open nc]).map(&:urn).sort
      assert_equal %w[urn:d:nc:1], search("libertas", sources: %w[nc]).map(&:urn)
      assert_equal %w[urn:d:nc:1 urn:d:open:1], search("libertas", sources: []).map(&:urn).sort,
                   "an empty membership list is no filter"
      assert_empty search("libertas", sources: %w[nc], source: "open"),
                   "the axis filter AND-composes with the single --source"
    end

    # The membership filter is catalog-side, so it arms the P35-6 inner-window
    # honesty hint exactly like --source: a full inner window thinned to a
    # short page under an active axis filter announces itself.
    def test_sources_membership_filter_arms_the_incomplete_hint
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      open_doc = make_document(source: @open, urn: "urn:d:open")
      # Ten open rows fill the limit×10 inner window; the one nc row the axis
      # filter wants sits beyond it.
      10.times { |i| make_passage(open_doc, urn: "urn:d:open:#{i}", text: "aurora", sequence: i) }
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "aurora", sequence: 0)
      rebuild!

      page = searcher.run("aurora", sources: %w[nc], limit: 1)
      assert_operator page.size, :<, 1 + 1
      assert_equal Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT, searcher.incomplete_hint,
                   "the axis membership filter arms the exhausted-window hint"
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

    # -- the timeline filter (P15-2) ----------------------------------

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

    def test_open_ended_timeline_row_survives_a_from_filter
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
                   "no timeline row → absent under an active date filter"
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

    def test_facet_filters_compose_with_each_other_and_the_timeline
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

    # -- the exhausted-inner-window honesty hint (P35-6, dev-loop §6b) --------
    # The P34 gate repro: the limit×INNER_LIMIT_FACTOR FTS window fills with
    # rows a catalog-side filter then rejects, so the page comes back short
    # (or empty) while matches exist beyond the window. The result semantics
    # stay as they are — but the surface must SAY the page may be incomplete.
    # (P42-3: --lang left this class — it rides in the MATCH on the current
    # index shape, so these pins exercise the still-catalog-side filters;
    # the historical lang starvation pin lives on in the downgraded-index
    # test below.)

    # Ten short Latin rows outrank (bm25 penalizes length) one longer Greek
    # row on the nc source; limit 1 makes the inner window exactly 10, so
    # the Greek match sits beyond it and a catalog-side filter (license,
    # source — or lang on a pre-P42-3 index) empties the page.
    def seed_window_exhausting_corpus(lat_rows: 10)
      lat = make_document(source: @open, urn: "urn:d:lat", language: "lat")
      lat_rows.times do |i|
        make_passage(lat, urn: "urn:d:lat:#{i}", text: "arma virumque cano", sequence: i, language: "lat")
      end
      grc = make_document(source: @nc, urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", sequence: 0, language: "grc",
                        text: "arma sits far down the rank because this passage carries many more words than the rest")
      rebuild!
    end

    def test_exhausted_inner_window_under_filters_reports_the_incomplete_page
      seed_window_exhausting_corpus

      query = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      results = query.run("arma", license: "nc", limit: 1)
      assert_empty results, "the inner window holds only filter-rejected rows (the P34 gate repro)"
      assert_equal Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT, query.incomplete_hint,
                   "an empty page with matches beyond the window must announce itself"
    end

    def test_unexhausted_window_under_filters_is_an_honest_empty
      seed_window_exhausting_corpus(lat_rows: 3)

      query = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      results = query.run("arma", place: "nowhere%", limit: 1)
      assert_empty results
      assert_nil query.incomplete_hint, "the window held every match — this empty is the truth"
    end

    def test_full_page_or_no_filters_carries_no_hint
      seed_window_exhausting_corpus

      query = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      refute_empty query.run("arma", limit: 1)
      assert_nil query.incomplete_hint, "no catalog-side filter was active — the page is honest"

      refute_empty query.run("arma", lang: "lat", limit: 1)
      assert_nil query.incomplete_hint, "a full page under filters needs no hint"
    end

    # -- the ubiquitous-term guard (P42-2) ------------------------------------
    # MEASURED (P41 scale review, 62.8M passages): `ORDER BY rank` scores
    # EVERY matching row before LIMIT, so a term in a large fraction of the
    # corpus (الله) took ~10s while rare terms took 0.27s. Above a df
    # threshold the ranked path is skipped and the page comes in CORPUS
    # (rowid) order, announced via #rank_note. Below the threshold the
    # behavior is byte-identical to before the guard.

    # Four sparse rows, then one DENSE row (bm25 would rank it first). df=5
    # crosses a threshold of 2: the page must come back in corpus order —
    # dense row LAST — with the honest note armed.
    def seed_ubiquity_corpus
      doc = make_document(source: @open, urn: "urn:d:1", language: "lat")
      4.times do |i|
        make_passage(doc, urn: "urn:d:1:#{i}", text: "aurora nox #{i}", sequence: i, language: "lat")
      end
      make_passage(doc, urn: "urn:d:1:dense", text: "aurora aurora aurora", sequence: 4, language: "lat")
      rebuild!
    end

    def test_ubiquitous_term_serves_a_sampled_page_in_corpus_order_and_announces_it
      seed_ubiquity_corpus
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      # A fixture-scale posting list is sampled exhaustively (the attempt
      # budget dwarfs it), so the full match set comes back — presented in
      # corpus (passage-id) order, dense row last, never bm25-led.
      results = searcher.run("aurora", ubiquity_threshold: 2)
      assert_equal %w[urn:d:1:0 urn:d:1:1 urn:d:1:2 urn:d:1:3 urn:d:1:dense],
                   results.map(&:urn),
                   "above the df threshold the page is a corpus-order-presented sample — the dense row no longer leads"
      assert_equal Nabu::Query::Search::RANK_SKIP_NOTE, searcher.rank_note,
                   "skipping the rank must be announced, never silent"
      assert_includes results.first.snippet, "[aurora]",
                      "the guarded path still builds the stored-text snippet"
    end

    # The P42-r3 regression pin (owner gate review): the pre-sample guard
    # served the HEAD of the posting list — twenty hits, all the first
    # matching document in id space, the same degenerate page for every
    # guarded term. The sampled page must draw across the corpus: with two
    # documents' postings and a page smaller than either, both documents
    # appear (seeded rng — the draw is deterministic under the seam).
    def test_guarded_page_samples_across_documents_not_the_first_document_head
      first = make_document(source: @open, urn: "urn:d:head", language: "lat")
      30.times { |i| make_passage(first, urn: "urn:d:head:#{i}", text: "aurora #{i}", sequence: i, language: "lat") }
      second = make_document(source: @open, urn: "urn:d:tail", language: "lat")
      30.times { |i| make_passage(second, urn: "urn:d:tail:#{i}", text: "aurora #{i}", sequence: i, language: "lat") }
      rebuild!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext, rng: ::Random.new(7))

      results = searcher.run("aurora", limit: 5, ubiquity_threshold: 2)
      assert_equal 5, results.size
      documents = results.map { |result| result.urn.rpartition(":").first }.uniq
      assert_operator documents.size, :>, 1,
                      "a sampled guarded page spans documents — the head-window page never did"
      insertion_order = results.map(&:urn).sort_by do |urn|
        [urn.start_with?("urn:d:head") ? 0 : 1, urn.split(":").last.to_i]
      end
      assert_equal insertion_order, results.map(&:urn),
                   "the sampled page presents in corpus (insertion) order"
    end

    def test_a_seeded_rng_makes_the_sampled_page_deterministic
      seed_ubiquity_corpus
      first = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext, rng: ::Random.new(11))
                                 .run("aurora", limit: 3, ubiquity_threshold: 2).map(&:urn)
      second = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext, rng: ::Random.new(11))
                                  .run("aurora", limit: 3, ubiquity_threshold: 2).map(&:urn)
      assert_equal first, second
    end

    def test_below_threshold_ranking_is_byte_identical_and_unannounced
      seed_ubiquity_corpus
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("aurora", ubiquity_threshold: 10)
      assert_equal "urn:d:1:dense", results.first.urn, "bm25 order exactly as before the guard"
      assert_nil searcher.rank_note, "no note when the rank was honestly computed"

      default = searcher.run("aurora")
      assert_equal "urn:d:1:dense", default.first.urn,
                   "the default threshold (~1M postings) never fires on a test-sized corpus"
      assert_nil searcher.rank_note
    end

    # The multi-term rule: the candidate set is rows matching the WHOLE query
    # (implicit AND), bounded by the RAREST term's df — a rare term ANDed with
    # a ubiquitous one keeps the candidate set small and ranking cheap, so the
    # guard must stay off even though one term alone would cross the threshold.
    def test_rare_term_anded_with_ubiquitous_term_keeps_the_ranked_path
      seed_ubiquity_corpus
      doc = make_document(source: @open, urn: "urn:d:2", language: "lat")
      make_passage(doc, urn: "urn:d:2:rara", text: "aurora rara", sequence: 0, language: "lat")
      rebuild!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("aurora rara", ubiquity_threshold: 2)
      assert_equal %w[urn:d:2:rara], results.map(&:urn), "only one row carries both terms"
      assert_nil searcher.rank_note,
                 "df(aurora)=6 crosses the threshold alone, but min-df is df(rara)=1 — ranking is cheap"
    end

    # The urn probe (the health golden replay) is ranking-independent by
    # design — the guard never rewrites it.
    def test_urn_probe_is_exempt_from_the_guard
      seed_ubiquity_corpus
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("aurora", urn: "urn:d:1:dense", ubiquity_threshold: 2)
      assert_equal %w[urn:d:1:dense], results.map(&:urn)
      assert_nil searcher.rank_note, "the urn probe serves one known row — nothing to guard"
    end

    def test_guard_composes_with_the_lang_filter
      seed_ubiquity_corpus
      grc = make_document(source: @open, urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "aurora", sequence: 0, language: "grc")
      rebuild!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("aurora", lang: "grc", ubiquity_threshold: 2)
      assert_equal %w[urn:d:grc:1], results.map(&:urn),
                   "the corpus-order path applies the same filters (lang in-MATCH since P42-3)"
      assert_equal Nabu::Query::Search::RANK_SKIP_NOTE, searcher.rank_note
    end

    # Feature-detect fallback: when the vocabulary probe is unavailable
    # (pre-index db, an engine quirk — TermFrequency returns nil), the guard
    # is skipped and behavior is exactly today's, even above the threshold.
    def test_unavailable_probe_fails_open_to_the_ranked_path
      seed_ubiquity_corpus
      no_probe = Object.new
      def no_probe.candidate_ceiling(_variants) = nil
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext, term_frequency: no_probe)

      results = searcher.run("aurora", ubiquity_threshold: 2)
      assert_equal "urn:d:1:dense", results.first.urn, "no probe → ranked, exactly as before P42-2"
      assert_nil searcher.rank_note
    end

    # --exact/--word run the verified-candidate path, not the plain ranked
    # page; the guard is scoped to the plain path only.
    def test_exact_path_is_outside_the_guard
      seed_ubiquity_corpus
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("aurora", exact: true, ubiquity_threshold: 2)
      refute_empty results
      assert_nil searcher.rank_note
    end

    # -- index-side --lang (P42-3) --------------------------------------------
    # The P40-r2 starvation genus, fixed at the index: passages_fts now
    # carries a language sentinel token, so plain-search --lang rides INSIDE
    # the MATCH and the inner window can no longer fill with wrong-language
    # rows. Against a pre-rebuild index (no column) the catalog-side path
    # runs byte-identically, honesty hint included — pinned via the
    # downgrade helper below.

    # The pre-P42-3 passages_fts shape — what the owner's live fulltext file
    # holds until the next full rebuild.
    OLD_FTS_DDL = <<~SQL
      CREATE VIRTUAL TABLE passages_fts USING fts5(
        text_normalized,
        urn UNINDEXED,
        passage_id UNINDEXED,
        tokenize = 'unicode61 remove_diacritics 2'
      )
    SQL

    # Rebuild passages_fts in its pre-P42-3 shape from the freshly built
    # rows, preserving rowid (corpus) order.
    def downgrade_index!
      rows = @fulltext[:passages_fts]
             .order(:rowid)
             .select_map(%i[text_normalized urn passage_id])
             .map { |text, urn, id| { text_normalized: text, urn: urn, passage_id: id } }
      @fulltext.drop_table(:passages_fts)
      @fulltext.run(OLD_FTS_DDL)
      @fulltext[:passages_fts].multi_insert(rows)
    end

    def test_lang_no_longer_starves_the_window_on_the_new_index
      seed_window_exhausting_corpus
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("arma", lang: "grc", limit: 1)
      assert_equal %w[urn:d:grc:1], results.map(&:urn),
                   "the in-MATCH lang filter reaches past the homograph wall (the P34/P40-r2 repro, fixed)"
      assert_nil searcher.incomplete_hint,
                 "lang rides in the MATCH — it cannot starve the window, so it no longer arms the hint"
    end

    def test_pre_rebuild_index_keeps_the_catalog_side_lang_path_byte_identical
      seed_window_exhausting_corpus
      downgrade_index!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("arma", lang: "grc", limit: 1)
      assert_empty results, "the pre-P42-3 window starves exactly as before (the historical P34 pin)"
      assert_equal Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT, searcher.incomplete_hint,
                   "…and announces itself exactly as before"
      page = searcher.run("arma", lang: "lat", limit: 1)
      assert_equal %w[lat], page.map(&:language), "a filling lang filter serves the same page as today"
      assert_nil searcher.incomplete_hint
    end

    def test_lang_filter_matches_the_typed_modern_code_index_side
      doc = make_document(source: @open, urn: "urn:d:is", language: "is")
      make_passage(doc, urn: "urn:d:is:1", text: "láta hann fara", sequence: 0, language: "is")
      rebuild!

      assert_equal %w[urn:d:is:1], search("láta", lang: "is").map(&:urn),
                   "P40-r2 honored in the MATCH too: the typed code is a member of its own equivalence set"

      downgrade_index!
      assert_equal %w[urn:d:is:1], search("láta", lang: "is").map(&:urn),
                   "the catalog-side fallback answers identically"
    end

    # The guard-composition pin: the language sentinel tokens live in the
    # fts vocabulary, but a plain query term that HAPPENS to be a language
    # code ("is" — English verb, Icelandic code) neither matches them nor
    # inherits their document frequency in the ubiquity probe.
    def test_language_tokens_neither_match_nor_trip_the_guard_for_code_shaped_words
      eng = make_document(source: @open, urn: "urn:d:eng", language: "eng")
      make_passage(eng, urn: "urn:d:eng:1", text: "this is the way", sequence: 0, language: "eng")
      ice = make_document(source: @open, urn: "urn:d:is", language: "is")
      5.times do |i|
        make_passage(ice, urn: "urn:d:is:#{i}", text: "aurora #{i}", sequence: i, language: "is")
      end
      rebuild!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)

      results = searcher.run("is", ubiquity_threshold: 3)
      assert_equal %w[urn:d:eng:1], results.map(&:urn),
                   "the Icelandic rows' language tokens are sentinel-prefixed — a plain 'is' cannot match them"
      assert_nil searcher.rank_note,
                 "df('is') counts the ONE text occurrence, not the 5 language tokens — the guard stays off"
    end

    # -- term-less filtered browse (P42-6) -----------------------------------
    # The mode the shipped recipes always promised: no query, a content filter
    # narrows WHICH passages, and the catalog is listed in corpus order with no
    # ranking. The library method lists whatever the filters select (the
    # legality rule is a CLI seam, exercised in cli_test).

    def browse(**)
      Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext).browse(**)
    end

    def test_browse_returns_the_filtered_page_in_corpus_insertion_order
      # Insert z, then a, then m — corpus order is passage-id (insertion) order,
      # NOT urn/alphabetical and NOT rank (a browse does not rank).
      dated("urn:z", "zeta", 100, 100)
      dated("urn:a", "alpha", 100, 100)
      dated("urn:m", "mu", 100, 100)
      rebuild!
      assert_equal %w[urn:z:1 urn:a:1 urn:m:1], browse(from: 1, to: 200).map(&:urn),
                   "corpus order is insertion (passage id) order, consistent with the ubiquity guard"
    end

    def test_browse_honors_the_limit
      5.times { |i| dated("urn:d#{i}", "text#{i}", 100, 100) }
      rebuild!
      assert_equal 2, browse(from: 1, to: 200, limit: 2).size, "--limit caps a browse page exactly"
    end

    def test_browse_never_arms_the_incomplete_hint_even_on_a_short_page
      # One dated doc, a generous limit: the page comes back SHORT under an
      # active content filter — the exact shape that arms the ranked-search
      # honesty hint. A browse has no inner window, so the hint must NOT arm.
      dated("urn:a", "alpha", 100, 100)
      rebuild!
      searcher = Nabu::Query::Search.new(catalog: @catalog, fulltext: @fulltext)
      page = searcher.browse(from: 1, to: 200, limit: 20)
      assert_equal 1, page.size, "one match, well under the limit"
      assert_nil searcher.incomplete_hint, "page-fill is exact for a browse — no incomplete-page hint"
      assert_nil searcher.rank_note, "a browse does not rank — no rank-skip note"
    end

    def test_browse_snippet_is_a_leading_stored_window_with_no_brackets
      dated("urn:a", "μῆνιν ἄειδε θεά", 100, 100)
      rebuild!
      hit = browse(from: 1, to: 200).first
      assert_equal "μῆνιν ἄειδε θεά", hit.snippet,
                   "no term to bracket — the pristine STORED text (accents intact), not the folded form"
      refute_includes hit.snippet, "[", "a browse snippet carries no highlight"
    end

    def test_browse_lists_by_genre_facet_alone
      faceted("urn:e:1", "dis manibus", { "genre" => %w[epitaph titsep] })
      faceted("urn:e:2", "dis manibus", { "genre" => ["votive inscription", "titsac"] })
      rebuild!
      assert_equal %w[urn:e:1:1], browse(facets: { "genre" => "epitaph" }).map(&:urn),
                   "a genre facet is a content filter — legal and selective, term-less"
    end

    def test_browse_lists_by_loans_facet_alone
      loaned("urn:c:1", "ⲡⲛⲟⲩⲧⲉ ⲁⲅⲁⲑⲟⲥ", { "grc" => 2 })
      loaned("urn:c:2", "ⲡⲛⲟⲩⲧⲉ", { "hbo" => 1 })
      rebuild!
      assert_equal %w[urn:c:1:1], browse(loans: "grc").map(&:urn),
                   "the loans facet alone narrows content — a legal term-less browse"
    end

    # Composition with the shelf-selectors (--lang/--license/--axis) WHEN a
    # content filter is present — the legal combined form.
    def dated_in(urn, language:, source:, year: 100)
      doc = make_document(source: source, urn: urn, language: language)
      make_passage(doc, urn: "#{urn}:1", text: "verbum", sequence: 1, language: language)
      @catalog[:document_axes].insert(document_id: doc.id, not_before: year, not_after: year,
                                      precision: "x", axis_source: "x")
    end

    def test_browse_composes_with_lang_under_a_content_filter
      dated_in("urn:g", language: "grc", source: @open)
      dated_in("urn:l", language: "lat", source: @open)
      rebuild!
      assert_equal %w[urn:g:1], browse(from: 1, to: 200, lang: "grc").map(&:urn),
                   "--lang scopes the browse the date filter made legal"
    end

    def test_browse_composes_with_license_under_a_content_filter
      dated_in("urn:o", language: "grc", source: @open) # open
      dated_in("urn:n", language: "grc", source: @nc)   # nc
      rebuild!
      assert_equal %w[urn:o:1], browse(from: 1, to: 200, license: "open").map(&:urn)
    end

    def test_browse_composes_with_a_source_membership_axis_under_a_content_filter
      dated_in("urn:o", language: "grc", source: @open)
      dated_in("urn:n", language: "grc", source: @nc)
      rebuild!
      assert_equal %w[urn:o:1], browse(from: 1, to: 200, sources: ["open"]).map(&:urn),
                   "the --axis membership list scopes the browse, the date filter making it legal"
    end
  end
end
