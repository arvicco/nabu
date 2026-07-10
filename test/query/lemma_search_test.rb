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
    # treebank parser families emit (tokens with "lemma"/"form").
    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: [])
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: JSON.generate(
          { "tokens" => lemmas.map { |lemma, form| { "lemma" => lemma, "form" => form } } }
        ),
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
  end
end
