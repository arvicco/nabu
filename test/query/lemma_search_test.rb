# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::LemmaSearch (P7-5). Same rig as SearchTest: fresh in-memory
  # catalog, separate in-memory fulltext connection, index rebuilt with the
  # real Indexer — so the lemma fold-both-sides contract is exercised end to
  # end (annotations_json → Indexer extraction/fold → query_forms lookup).
  # Lemma/form pairs are REAL fixture data (UD Ancient Greek PROIEL, PROIEL
  # Cicero) — see the attestations named per test.
  class LemmaSearchTest < Minitest::Test
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

    def make_document(urn:, source: @open, title: "Herodotus", language: "grc", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    # +lemmas+ is [[lemma, form], …] — stored in the annotation shape both
    # treebank parser families emit (tokens with "lemma"/"form"). +tokens+ (for
    # the P13-6 morph tests) passes FULL token hashes verbatim — the real
    # fixture shapes with UD `feats` or PROIEL `morphology` — and is merged
    # after the lemma pairs.
    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: [], tokens: [])
      token_hashes = lemmas.map { |lemma, form| { "lemma" => lemma, "form" => form } } + tokens
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: JSON.generate({ "tokens" => token_hashes }),
        content_sha256: "x", revision: 1
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def search(lemma, **)
      Nabu::Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext).run(lemma, **)
    end

    # The real λέγω attestations from the UD grc PROIEL fixture: sentence
    # 64498 attests the suppletive aorist εἶπας, 64531 both λέγειν and εἰπεῖν.
    def seed_lego_corpus
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:64498", text: "σὺ δὲ εἶπας.", sequence: 0,
                        lemmas: [%w[σύ σὺ], %w[δέ δὲ], %w[λέγω εἶπας]])
      make_passage(doc, urn: "urn:d:grc:64531", text: "λέγειν ἢ εἰπεῖν", sequence: 1,
                        lemmas: [%w[λέγω λέγειν], %w[ἤ ἢ], %w[λέγω εἰπεῖν]])
      make_passage(doc, urn: "urn:d:grc:64490", text: "Δελφῶν οἶδα ἐγὼ", sequence: 2,
                        lemmas: [%w[Δελφοί Δελφῶν], %w[οἶδα οἶδα], %w[ἐγώ ἐγὼ]])
      rebuild!
      doc
    end

    # -- exact lookup with inflected attestations -----------------------------

    def test_lemma_finds_every_inflected_attestation
      seed_lego_corpus

      results = search("λέγω")
      assert_equal %w[urn:d:grc:64498 urn:d:grc:64531], results.map(&:urn),
                   "the suppletive aorist and the presents are all attestations of λέγω"
      assert_equal "εἶπας", results[0].surface_forms
      assert_equal "λέγειν, εἰπεῖν", results[1].surface_forms, "one hit per passage, forms aggregated"
      assert_equal "λέγω", results[0].lemma
      assert_equal "σὺ δὲ εἶπας.", results[0].text, "the pristine text rides along for display"
    end

    def test_no_match_returns_empty
      seed_lego_corpus
      assert_empty search("τίθημι")
      assert_empty search(""), "an empty lemma matches nothing"
    end

    # -- the loans facet composes with lemma search (P34-2) --------------------

    # The loans corpus (Coptic Scriptorium) is gold-lemmatized (P17-1 language
    # #15), so unlike the document facets the loans filter DOES compose with
    # --lemma: both read the same stored passage row, no reparse.
    def test_lemma_search_composes_with_the_loans_filter
      doc = make_document(urn: "urn:d:cop", language: "cop", title: "Mark")
      [["urn:d:cop:1", { "grc" => 1 }], ["urn:d:cop:2", nil]].each_with_index do |(urn, loans), seq|
        annotations = { "tokens" => [{ "lemma" => "ⲛⲟⲩⲧⲉ", "form" => "ⲛⲟⲩⲧⲉ" }] }
        annotations["loans"] = loans if loans
        Nabu::Store::Passage.create(
          document_id: doc.id, urn: urn, sequence: seq, language: "cop",
          text: "ⲡⲛⲟⲩⲧⲉ #{seq}", text_normalized: Nabu::Normalize.search_form("ⲡⲛⲟⲩⲧⲉ", language: "cop"),
          annotations_json: Nabu::Store::ContentHash.canonical_json(annotations),
          content_sha256: "x", revision: 1
        )
      end
      rebuild!

      assert_equal %w[urn:d:cop:1 urn:d:cop:2], search("ⲛⲟⲩⲧⲉ").map(&:urn)
      assert_equal %w[urn:d:cop:1], search("ⲛⲟⲩⲧⲉ", loans: "grc").map(&:urn),
                   "the loans conjunct narrows the lemma hits to Greek-loan-bearing passages"
    end

    # -- dictionary gloss integration (P11-4) ----------------------------------

    # A lemma hit carries its dictionary shelf gloss when a dictionary of the
    # passage's language holds the folded headword (the real L&S officium /
    # PROIEL Cicero pair); hits without a shelf entry read nil.
    def test_lemma_hits_carry_their_dictionary_gloss
      doc = make_document(urn: "urn:d:lat", language: "lat", title: "De Officiis")
      make_passage(doc, urn: "urn:d:lat:1", text: "vacare officio", sequence: 0, language: "lat",
                        lemmas: [%w[vaco vacare], %w[officium officio]])
      rebuild!
      dictionary = Nabu::Store::Dictionary.create(
        source_id: @open.id, slug: "lewis-short", title: "A Latin Dictionary", language: "lat"
      )
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, urn: "urn:nabu:dict:lewis-short:n32391",
        entry_id: "n32391", key_raw: "officium", headword: "offĭcĭum",
        headword_folded: "officium", gloss: "a service", body: "a service …",
        content_sha256: "x", revision: 1, withdrawn: false
      )

      assert_equal ["a service"], search("officium").map(&:gloss)
      assert_equal [nil], search("vaco").map(&:gloss), "no shelf entry: nil gloss, honest absence"
    end

    def test_gloss_requires_the_dictionary_language_to_match_the_lemma
      seed_lego_corpus
      dictionary = Nabu::Store::Dictionary.create(
        source_id: @open.id, slug: "lewis-short", title: "A Latin Dictionary", language: "lat"
      )
      # A Latin homograph must not gloss a Greek lemma.
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dictionary.id, urn: "urn:nabu:dict:lewis-short:x1",
        entry_id: "x1", key_raw: "lego2", headword: "lēgo", headword_folded: "λεγω",
        gloss: "wrong", body: "…", content_sha256: "x", revision: 1, withdrawn: false
      )

      assert_equal [nil, nil], search("λέγω").map(&:gloss)
    end

    # -- fold both sides (P6-4 applied to lemmas) ------------------------------

    # A lemma is a dictionary form: Greek lemmas routinely END in ς (λόγος).
    # Index side stores search_form(λόγος, grc) = λογοσ; every query spelling —
    # accented, bare, internal-sigma — folds onto it via the query_forms union.
    def test_final_sigma_and_accent_query_spellings_all_hit
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:75552", text: "τὸν λόγον", sequence: 0,
                        lemmas: [%w[ὁ τὸν], %w[λόγος λόγον]])
      rebuild!

      %w[λόγος λογος λογοσ ΛΟΓΟΣ].each do |spelling|
        assert_equal %w[urn:d:grc:75552], search(spelling).map(&:urn),
                     "spelling #{spelling.inspect} must find the λόγος attestation"
      end
    end

    # PROIEL Cicero reality: sentence 86001 attests video as "videmur"; the
    # lat fold maps v→u on BOTH sides, so u- and v-spellings both hit.
    def test_latin_lemma_v_u_spellings_both_hit
      doc = make_document(urn: "urn:d:lat", language: "lat")
      make_passage(doc, urn: "urn:d:lat:86001", text: "abundare debemus, videmur", sequence: 0,
                        language: "lat", lemmas: [%w[abundo abundare], %w[video videmur]])
      rebuild!

      assert_equal %w[urn:d:lat:86001], search("video").map(&:urn), "v spelling"
      assert_equal %w[urn:d:lat:86001], search("uideo").map(&:urn), "u spelling"
    end

    # THE union invariant, asserted for lemmas: for every language rule, the
    # index side search_form(lemma, L) is always among the query-side
    # query_forms(lemma) variants — which is exactly why no per-language pick
    # is needed at query time (same argument as P6-4 for text).
    def test_query_forms_union_covers_every_language_fold_of_a_lemma
      { "λόγος" => "grc", "λέγω" => "grc", "video" => "lat", "jah" => "got",
        "крьстити" => "chu", "оуже" => "orv" }.each do |lemma, language|
        indexed = Nabu::Normalize.search_form(lemma, language: language)
        assert_includes Nabu::Normalize.query_forms(lemma), indexed,
                        "query_forms(#{lemma.inspect}) must contain the #{language} index form"
      end
    end

    # -- filters, limit, urn probe --------------------------------------------

    def test_lang_filter_excludes_other_languages
      grc = make_document(urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "ναι", sequence: 0, lemmas: [%w[ναι ναι]])
      got = make_document(urn: "urn:d:got", language: "got")
      make_passage(got, urn: "urn:d:got:1", text: "nai", sequence: 0,
                        language: "got", lemmas: [%w[ναι nai]])
      rebuild!

      assert_equal %w[urn:d:got:1 urn:d:grc:1], search("ναι").map(&:urn),
                   "unfiltered: both, in urn order"
      assert_equal %w[urn:d:got:1], search("ναι", lang: "got").map(&:urn)
    end

    def test_license_filter_is_exact_class
      open_doc = make_document(urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "x", sequence: 0, lemmas: [%w[λέγω λέγει]])
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "x", sequence: 0, lemmas: [%w[λέγω λέγει]])
      rebuild!

      assert_equal %w[urn:d:nc:1], search("λέγω", license: "nc").map(&:urn)
      assert_equal %w[urn:d:open:1], search("λέγω", license: "open").map(&:urn)
    end

    # The catalog-side re-check: a passage withdrawn AFTER the index was built
    # must not surface, even though its lemma rows are still in the index.
    def test_passage_withdrawn_after_index_build_is_excluded
      seed_lego_corpus
      Nabu::Store::Passage.first(urn: "urn:d:grc:64498").update(withdrawn: true)

      assert_equal %w[urn:d:grc:64531], search("λέγω").map(&:urn)
    end

    def test_limit_caps_the_result_count
      doc = make_document(urn: "urn:d:grc")
      5.times do |i|
        make_passage(doc, urn: "urn:d:grc:#{i}", text: "λέγει", sequence: i, lemmas: [%w[λέγω λέγει]])
      end
      rebuild!

      assert_equal 3, search("λέγω", limit: 3).size
    end

    # The health golden replay probe: urn-targeted, ranking-independent.
    def test_urn_filter_probes_one_passage
      seed_lego_corpus

      assert_equal %w[urn:d:grc:64498], search("λέγω", urn: "urn:d:grc:64498", limit: 1).map(&:urn)
      assert_empty search("οἶδα", urn: "urn:d:grc:64498"),
                   "the urn filter still requires the lemma to match"
    end

    # -- morph facets (P13-6) --------------------------------------------------

    # UD (CoNLL-U) grc: λόγος inflects; --morph case=dat,number=pl keeps only
    # the dative-plural attestation and shows it with the matching form + the
    # decoded morph evidence — a passage attesting λόγος in TWO cases must
    # surface only its dative-plural token, never the nominative one.
    def test_morph_dative_plural_filters_ud_greek
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "τοῖς λόγοις", sequence: 0, tokens: [
                     { "lemma" => "ὁ", "form" => "τοῖς", "feats" => "Case=Dat|Number=Plur", "upos" => "DET" },
                     { "lemma" => "λόγος", "form" => "λόγοις",
                       "feats" => "Case=Dat|Gender=Masc|Number=Plur", "upos" => "NOUN" }
                   ])
      make_passage(doc, urn: "urn:d:grc:2", text: "ὁ λόγος", sequence: 1, tokens: [
                     { "lemma" => "ὁ", "form" => "ὁ", "feats" => "Case=Nom|Number=Sing", "upos" => "DET" },
                     { "lemma" => "λόγος", "form" => "λόγος",
                       "feats" => "Case=Nom|Gender=Masc|Number=Sing", "upos" => "NOUN" }
                   ])
      rebuild!

      results = search("λόγος", morph: "case=dat,number=pl")
      assert_equal %w[urn:d:grc:1], results.map(&:urn), "only the dative-plural passage"
      assert_equal "λόγοις", results[0].surface_forms, "only the matching token's form"
      assert_equal "number=plur|gender=masc|case=dat", results[0].morph, "evidence shown per hit"
    end

    # PROIEL (positional morphology) Old Russian: the same façade over a
    # different tagset — "-p---mda--i" decodes to dative plural. Proves the
    # unified vocabulary spans conllu + proiel (the two families the spec names).
    def test_morph_dative_plural_filters_proiel
      doc = make_document(urn: "urn:d:orv", language: "orv", title: "PVL")
      make_passage(doc, urn: "urn:d:orv:1", text: "богомъ", sequence: 0, language: "orv", tokens: [
                     { "lemma" => "богъ", "form" => "богомъ", "morphology" => "-p---mda--i",
                       "part_of_speech" => "Nb" }
                   ])
      make_passage(doc, urn: "urn:d:orv:2", text: "богъ", sequence: 1, language: "orv", tokens: [
                     { "lemma" => "богъ", "form" => "богъ", "morphology" => "-s---mn---i",
                       "part_of_speech" => "Nb" }
                   ])
      rebuild!

      results = search("богъ", morph: "case=dat,number=pl")
      assert_equal %w[urn:d:orv:1], results.map(&:urn)
      assert_equal "богомъ", results[0].surface_forms
      assert_equal "number=plur|gender=masc|case=dat", results[0].morph
    end

    # A morph filter matching no token in any attesting passage is honest empty,
    # not an error — and ORACC-style pos-only tokens never satisfy an
    # inflectional facet (no case on a cuneiform pos tag).
    def test_morph_no_match_is_empty
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "λόγος", sequence: 0, tokens: [
                     { "lemma" => "λόγος", "form" => "λόγος", "feats" => "Case=Nom|Number=Sing" }
                   ])
      akk = make_document(urn: "urn:d:akk", language: "akk", title: "OB")
      make_passage(akk, urn: "urn:d:akk:1", text: "awilum", sequence: 0, language: "akk", tokens: [
                     { "lemma" => "awīlu", "form" => "LU₂", "pos" => "N", "norm" => "awīl" }
                   ])
      rebuild!

      assert_empty search("λόγος", morph: "case=dat"), "no dative attestation"
      assert_empty search("awīlu", morph: "case=dat"), "ORACC pos-only: no inflectional match"
    end

    # Morph composes with the lang filter and honours the limit over the
    # post-filtered hits (not the pre-filter candidate slice).
    def test_morph_composes_with_lang_and_limit
      doc = make_document(urn: "urn:d:grc")
      3.times do |i|
        make_passage(doc, urn: "urn:d:grc:#{i}", text: "λόγοις", sequence: i, tokens: [
                       { "lemma" => "λόγος", "form" => "λόγοις", "feats" => "Case=Dat|Number=Plur" }
                     ])
      end
      got = make_document(urn: "urn:d:got", language: "got")
      make_passage(got, urn: "urn:d:got:1", text: "waurdam", sequence: 0, language: "got", tokens: [
                     { "lemma" => "λόγος", "form" => "waurdam", "feats" => "Case=Dat|Number=Plur" }
                   ])
      rebuild!

      assert_equal 2, search("λόγος", morph: "case=dat,number=pl", limit: 2).size, "limit caps post-filter hits"
      assert_equal %w[urn:d:grc:0 urn:d:grc:1 urn:d:grc:2],
                   search("λόγος", morph: "case=dat", lang: "grc").map(&:urn), "lang filter composes"
    end

    def test_malformed_morph_raises
      seed_lego_corpus
      assert_raises(Nabu::Query::MorphFacets::Error) { search("λέγω", morph: "case") }
    end

    # -- the lemma tier (P26-0) ------------------------------------------------
    # Silver (automatic) lemmatization joins the index labeled per row; lemma
    # search INCLUDES silver hits, each carrying its tier, and --gold-only
    # restores the gold-treebank-only scope.

    def seed_tiered_corpus
      gold_doc = make_document(urn: "urn:d:gold")
      make_passage(gold_doc, urn: "urn:d:gold:1", text: "σὺ δὲ εἶπας.", sequence: 0,
                             lemmas: [%w[λέγω εἶπας]])
      silver_source = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
      )
      silver_doc = make_document(urn: "urn:d:silver", source: silver_source)
      make_passage(silver_doc, urn: "urn:d:silver:1", text: "λέγειν ἢ εἰπεῖν", sequence: 0,
                               lemmas: [%w[λέγω λέγειν]])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "auto" => "silver" })
    end

    def test_silver_hits_are_included_with_per_hit_tier
      seed_tiered_corpus

      results = search("λέγω")
      assert_equal %w[urn:d:gold:1 urn:d:silver:1], results.map(&:urn)
      assert_equal %w[gold silver], results.map(&:tier),
                   "every hit says which tier attests it — silver is never mistakable for gold"
    end

    def test_gold_only_excludes_silver_hits
      seed_tiered_corpus

      results = search("λέγω", gold_only: true)
      assert_equal %w[urn:d:gold:1], results.map(&:urn)
      assert_equal %w[gold], results.map(&:tier)
    end

    def test_morph_hits_carry_the_tier_and_respect_gold_only
      gold_doc = make_document(urn: "urn:d:gold")
      make_passage(gold_doc, urn: "urn:d:gold:1", text: "τοῖς λόγοις", sequence: 0,
                             lemmas: [],
                             tokens: [{ "lemma" => "λόγος", "form" => "λόγοις",
                                        "feats" => "Case=Dat|Number=Plur" }])
      silver_source = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
      )
      silver_doc = make_document(urn: "urn:d:silver", source: silver_source)
      make_passage(silver_doc, urn: "urn:d:silver:1", text: "λόγοις", sequence: 0,
                               lemmas: [],
                               tokens: [{ "lemma" => "λόγος", "form" => "λόγοις",
                                          "feats" => "Case=Dat|Number=Plur" }])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "auto" => "silver" })

      results = search("λόγος", morph: "case=dat,number=pl")
      assert_equal %w[gold silver], results.map(&:tier), "morph hits are tier-labeled too"
      gold = search("λόγος", morph: "case=dat,number=pl", gold_only: true)
      assert_equal %w[urn:d:gold:1], gold.map(&:urn)
    end

    # A pre-tier fulltext index (built before the column existed) still
    # serves: every row reads gold — the current, correct semantics of an
    # index that predates silver sources (the ReflexViews pre-migration
    # tolerance precedent).
    def test_pre_tier_lemma_index_reads_all_gold
      seed_lego_corpus
      @fulltext.alter_table(Nabu::Store::Indexer::LEMMA_TABLE) { drop_column :tier }

      results = search("λέγω", gold_only: true)
      assert_equal %w[urn:d:grc:64498 urn:d:grc:64531], results.map(&:urn),
                   "gold_only on a pre-tier index is a no-op, never a crash"
      assert_equal %w[gold gold], results.map(&:tier)
    end

    # -- cross-script lemma lookup (P27-2) -----------------------------------

    # OWNER REPRO (2026-07-18a), the --lemma half: nabu's reflex render
    # prints the Devanagari form beside a "nabu search --lemma" hint — the
    # pasted form must find the passages the DCS-style IAST lemma indexes
    # (the render/query round-trip contract).
    def test_devanagari_lemma_paste_finds_the_iast_indexed_attestations
      doc = make_document(urn: "urn:d:dcs", title: "DCS", language: "san")
      make_passage(doc, urn: "urn:d:dcs:1", text: "dharman iti", sequence: 0, language: "san",
                        lemmas: [%w[dharman dharman]])
      rebuild!

      assert_equal %w[urn:d:dcs:1], search("धर्मन्").map(&:urn),
                   "the reflex-render Devanagari form folds to the indexed lemma skeleton"
      assert_equal %w[urn:d:dcs:1], search("dharman").map(&:urn)
    end

    def test_cyrillic_and_diplomatic_lemma_spellings_meet
      doc = make_document(urn: "urn:d:zogr", title: "Zographensis", language: "chu")
      make_passage(doc, urn: "urn:d:zogr:1", text: "и въста мариꙗ", sequence: 0, language: "chu",
                        lemmas: [%w[въстати въста]])
      rebuild!

      assert_equal %w[urn:d:zogr:1], search("въстати").map(&:urn)
      assert_equal %w[urn:d:zogr:1], search("vъstati").map(&:urn),
                   "the damaskini-style Latin-diplomatic spelling reaches the Cyrillic gold lemma"
    end
    # -- the exhausted-inner-window honesty hint (P35-6, dev-loop §6b) --------
    # Ten open-licensed rows fill the urn-ordered inner window (limit 1 ×
    # factor 10); the one nc attestation sorts after them, so the license
    # filter empties the page while a match exists beyond the window.

    def seed_window_exhausting_lemmas(open_rows: 10)
      doc = make_document(urn: "urn:d:a")
      open_rows.times do |i|
        make_passage(doc, urn: "urn:d:a:#{i}", text: "λέγειν", sequence: i,
                          lemmas: [%w[λέγω λέγειν]])
      end
      nc_doc = make_document(urn: "urn:d:z", source: @nc)
      make_passage(nc_doc, urn: "urn:d:z:1", text: "εἶπας", sequence: 0,
                           lemmas: [%w[λέγω εἶπας]])
      rebuild!
    end

    def test_exhausted_inner_window_under_filters_reports_the_incomplete_page
      seed_window_exhausting_lemmas

      query = Nabu::Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext)
      results = query.run("λέγω", license: "nc", limit: 1)
      assert_empty results, "the inner window holds only filter-rejected rows (the P34 gate repro)"
      assert_equal Nabu::Query::CatalogJoin::INCOMPLETE_PAGE_HINT, query.incomplete_hint,
                   "an empty page with matches beyond the window must announce itself"
    end

    def test_unexhausted_window_or_full_page_carries_no_hint
      seed_window_exhausting_lemmas(open_rows: 3)

      query = Nabu::Query::LemmaSearch.new(catalog: @catalog, fulltext: @fulltext)
      assert_equal %w[urn:d:z:1], query.run("λέγω", license: "nc", limit: 1).map(&:urn)
      assert_nil query.incomplete_hint, "the window reached the nc row — the page is honest"

      refute_empty query.run("λέγω", limit: 1)
      assert_nil query.incomplete_hint, "no catalog-side filter was active"
    end
  end
end
