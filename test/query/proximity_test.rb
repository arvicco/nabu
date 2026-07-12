# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Proximity (P14-8). Same rig as SearchTest/LemmaSearchTest:
  # fresh in-memory catalog, separate in-memory fulltext, index rebuilt with
  # the real Indexer — so the FTS5 NEAR runs over the true fold-both-sides
  # search forms, and the lemma-expansion path exercises the real
  # passage_lemmas index end to end.
  class ProximityTest < Minitest::Test
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

    def make_document(urn:, source: @open, title: "Corpus", language: "grc", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: [], withdrawn: false)
      tokens = lemmas.map { |lemma, form| { "lemma" => lemma, "form" => form } }
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: JSON.generate({ "tokens" => tokens }),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def prox(**)
      Nabu::Query::Proximity.new(catalog: @catalog, fulltext: @fulltext).run(**)
    end

    # -- text near text, Greek (John 1:1 shape) ------------------------------

    def test_greek_terms_within_window_hit_further_apart_miss
      doc = make_document(urn: "urn:d:grc")
      # λόγος and θεός two words apart (gap 1: "θεὸς ἦν ὁ λόγος").
      make_passage(doc, urn: "urn:d:grc:1", text: "καὶ θεὸς ἦν ὁ λόγος", sequence: 0)
      # far apart: seven words between them.
      make_passage(doc, urn: "urn:d:grc:2",
                        text: "λόγος μὲν οὖν ἐστιν ἀρχὴ πάντων καὶ τέλος ὁ θεός", sequence: 1)
      rebuild!

      near = prox(query: "λόγος", near: "θεός", window: 3)
      assert_equal %w[urn:d:grc:1], near.map(&:urn),
                   "only the passage where the terms sit within 3 tokens matches"
    end

    def test_window_widens_to_admit_the_far_passage
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:2",
                        text: "λόγος μὲν οὖν ἐστιν ἀρχὴ πάντων καὶ τέλος ὁ θεός", sequence: 0)
      rebuild!

      assert_empty prox(query: "λόγος", near: "θεός", window: 5)
      assert_equal %w[urn:d:grc:2], prox(query: "λόγος", near: "θεός", window: 9).map(&:urn)
    end

    # The fold-both-sides proof carried into NEAR: an UNACCENTED, final-sigma
    # -insensitive query finds the polytonic passage, and the SNIPPET brackets
    # BOTH terms (the "both terms highlighted" requirement).
    def test_unaccented_query_matches_and_both_terms_are_highlighted
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "θεὸς ἦν ὁ λόγος", sequence: 0)
      rebuild!

      results = prox(query: "λογοσ", near: "θεος", window: 5)
      assert_equal 1, results.size
      assert_equal "θεὸς ἦν ὁ λόγος", results.first.text, "pristine text for display"
      snippet = results.first.snippet
      assert_includes snippet, "[θεοσ]", "the near term is bracketed"
      assert_includes snippet, "[λογοσ]", "the anchor term is bracketed too"
    end

    def test_near_is_order_independent
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "θεὸς ὁ λόγος", sequence: 0) # θεός before λόγος
      rebuild!

      assert_equal %w[urn:d:grc:1], prox(query: "λόγος", near: "θεός", window: 2).map(&:urn),
                   "NEAR matches regardless of which term comes first"
    end

    # -- text near text, Latin (v/u, j/i fold) -------------------------------

    def test_latin_fold_applies_on_both_near_terms
      doc = make_document(urn: "urn:d:lat", language: "lat", title: "Ovid")
      # stored with u/i spelling; queried with v/j spelling — the lat fold must
      # apply inside NEAR on both sides.
      make_passage(doc, urn: "urn:d:lat:1", text: "pacis amor deus est", sequence: 0, language: "lat")
      make_passage(doc, urn: "urn:d:lat:2", text: "amor longe positus a deo manet", sequence: 1, language: "lat")
      rebuild!

      hits = prox(query: "amor", near: "deus", window: 2)
      assert_equal %w[urn:d:lat:1], hits.map(&:urn), "only the close pair, folded u/i-insensitively"
    end

    # -- lemma-expanded anchor (the required lemma case) ---------------------

    def test_lemma_anchor_expands_to_surface_forms_before_near
      doc = make_document(urn: "urn:d:grc")
      # λέγω attested by the SUPPLETIVE aorist εἶπε — no shared surface with the
      # dictionary form; proximity must still find it near κύριος.
      make_passage(doc, urn: "urn:d:grc:1", text: "τάδε λέγει κύριος ὁ θεός", sequence: 0,
                        lemmas: [%w[λέγω λέγει], %w[κύριος κύριος]])
      make_passage(doc, urn: "urn:d:grc:2", text: "καὶ εἶπε κύριος πρὸς Μωυσῆν", sequence: 1,
                        lemmas: [%w[λέγω εἶπε], %w[κύριος κύριος]])
      # a passage attesting κύριος but NOT λέγω anywhere near — must not hit.
      make_passage(doc, urn: "urn:d:grc:3", text: "κύριος ποιμαίνει με", sequence: 2,
                        lemmas: [%w[κύριος κύριος]])
      rebuild!

      hits = prox(lemma: "λέγω", near: "κύριος", window: 3)
      assert_equal %w[urn:d:grc:1 urn:d:grc:2], hits.map(&:urn).sort,
                   "both the present λέγει and the suppletive aorist εἶπε count as λέγω near κύριος"
    end

    def test_lemma_anchor_with_no_attestations_is_empty
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "θεὸς ὁ λόγος", sequence: 0,
                        lemmas: [%w[θεός θεὸς]])
      rebuild!

      assert_empty prox(lemma: "ἀνύπαρκτος", near: "θεός", window: 5),
                   "a lemma with no surface forms in the corpus yields no proximity anchor"
    end

    # -- filters compose (catalog side, shared with Search) ------------------

    def test_language_and_license_filter_compose
      grc = make_document(urn: "urn:d:grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "θεὸς ὁ λόγος", sequence: 0)
      lat = make_document(urn: "urn:d:lat", source: @nc, language: "lat")
      make_passage(lat, urn: "urn:d:lat:1", text: "deus est amor", sequence: 0, language: "lat")
      rebuild!

      assert_equal %w[urn:d:grc:1], prox(query: "λόγος", near: "θεός", window: 3, lang: "grc").map(&:urn)
      assert_empty prox(query: "λόγος", near: "θεός", window: 3, license: "nc"),
                   "the grc hit is open-licensed, so an nc filter excludes it"
    end

    # -- honest boundaries ---------------------------------------------------

    def test_cross_passage_adjacency_is_not_a_hit
      doc = make_document(urn: "urn:d:grc")
      make_passage(doc, urn: "urn:d:grc:1", text: "ὁ λόγος", sequence: 0)
      make_passage(doc, urn: "urn:d:grc:2", text: "ὁ θεός", sequence: 1)
      rebuild!

      assert_empty prox(query: "λόγος", near: "θεός", window: 10),
                   "the passage is the unit — terms in adjacent passages are not near"
    end

    def test_both_missing_or_both_given_anchors_raise
      assert_raises(ArgumentError) { prox(near: "θεός", window: 5) }
      assert_raises(ArgumentError) { prox(query: "λόγος", lemma: "λέγω", near: "θεός", window: 5) }
    end
  end
end
