# frozen_string_literal: true

require "test_helper"
require "json"

module Query
  # Nabu::Query::LanguageInfo (P18-4): the live relevance behind
  # `nabu language` — corpus documents/passages, gold-lemma rows, dictionary
  # shelves, and reconstruction-crosswalk edges, computed at query time from
  # the handles. The reflex side loads from the real wiktionary-recon
  # fixtures; the corpus side is store-level rows with gold annotations
  # through the real Indexer (the etym-test rig).
  class LanguageInfoTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions",
        adapter_class: "Nabu::Adapters::WiktionaryRecon", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      @texts = Nabu::Store::Source.create(
        slug: "texts", name: "Texts", adapter_class: "TestAdapter", license_class: "open"
      )
      @more = Nabu::Store::Source.create(
        slug: "more-texts", name: "More", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def make_document(source:, language:, urn:, passages: 1, withdrawn: false, lemma: nil)
      document = Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "T", language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
      passages.times do |i|
        annotations = lemma ? JSON.generate({ "tokens" => [{ "lemma" => lemma, "form" => lemma }] }) : "{}"
        Nabu::Store::Passage.create(
          document_id: document.id, urn: "#{urn}:#{i + 1}", sequence: i,
          language: language, text: "t", text_normalized: "t",
          annotations_json: annotations, content_sha256: "x", revision: 1
        )
      end
    end

    # Rows here are seeded DIRECTLY (bypassing the loader), so the write-time
    # census must be re-derived before reading (P42-0: the corpus grain reads
    # source_stats when the table exists).
    def info
      Nabu::Store::SourceStats.derive!(@catalog, note: "test seed")
      Nabu::Query::LanguageInfo.new(catalog: @catalog, fulltext: @fulltext)
    end

    def test_relevance_counts_docs_passages_lemmas_shelves_and_edges
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:1", passages: 2, lemma: "богъ")
      make_document(source: @more, language: "chu", urn: "urn:nabu:test:chu:2")
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:w", withdrawn: true)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

      rel = info.relevance("chu")
      assert_equal 2, rel.documents, "withdrawn documents never count"
      assert_equal 3, rel.passages
      assert_equal 2, rel.lemma_rows
      assert_empty rel.shelves, "no chu dictionary on this fixture shelf"
      assert_operator rel.reflex_edges, :>, 0, "the cu-coded edges join through language=chu"
      assert_equal ["cu"], rel.edge_codes.keys, "chu's edges arrive as Wiktionary's cu"
      assert_equal({ "texts" => 1, "more-texts" => 1 }, rel.sources,
                   "per-source counts skip the withdrawn document too")
      refute rel.empty?
    end

    # P26-0: the language card's lemma_rows line SAYS gold — silver
    # (automatic) rows must not inflate it, in relevance or in --list.
    def test_lemma_rows_count_gold_tier_only
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:1",
                    passages: 2, lemma: "богъ")
      make_document(source: @more, language: "chu", urn: "urn:nabu:test:chu:2",
                    passages: 3, lemma: "богъ")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "more-texts" => "silver" })

      assert_equal 2, info.relevance("chu").lemma_rows,
                   "the card's gold label stays honest — silver rows excluded"
      held = info.held.find { |h| h.code == "chu" }
      assert_equal 2, held.lemma_rows
    end

    def test_relevance_for_a_shelf_language_counts_entries
      rel = info.relevance("sla-pro")
      shelf = rel.shelves.find { |s| s.slug == "wiktionary-sla-pro" } || flunk("sla-pro shelf missing")
      assert_operator shelf.entries, :>, 0
      assert_operator rel.reflex_edges, :>, 0, "PIE/PBS descendants name Proto-Slavic forms"
      assert_equal 0, rel.documents
    end

    def test_relevance_for_a_tail_code_counts_verbatim_edges_only
      rel = info.relevance("zle-ort")
      assert_operator rel.reflex_edges, :>, 0
      assert_equal ["zle-ort"], rel.edge_codes.keys
      assert_equal 0, rel.documents
      assert_equal 0, rel.lemma_rows
    end

    def test_unknown_code_relevance_is_empty
      assert info.relevance("qqq").empty?
    end

    def test_held_lists_corpus_lemma_and_shelf_languages_only
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:1", lemma: "богъ")
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

      held = info.held
      codes = held.map(&:code)
      assert_includes codes, "chu"
      assert_includes codes, "sla-pro", "shelf languages are held"
      refute_includes codes, "zle-ort", "the etymology tail is NOT the held list"
      chu = held.find { |h| h.code == "chu" }
      assert_equal 1, chu.documents
      assert_equal 1, chu.lemma_rows
    end

    def test_degrades_without_a_fulltext_handle
      rel = Nabu::Query::LanguageInfo.new(catalog: @catalog).relevance("chu")
      assert_equal 0, rel.lemma_rows
    end

    # P42-0: the corpus grain reads source_stats when present, live
    # aggregates when not — same Relevance/Held either way (pre-019 catalog
    # contract).
    def test_relevance_and_held_are_identical_with_and_without_source_stats
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:1", passages: 2)
      make_document(source: @more, language: "chu", urn: "urn:nabu:test:chu:2")
      make_document(source: @texts, language: "chu", urn: "urn:nabu:test:chu:w", withdrawn: true)

      with_stats = info
      results = [with_stats.relevance("chu"), with_stats.held]
      @catalog.drop_table(:source_stats_languages)
      @catalog.drop_table(:source_stats)
      fallback = Nabu::Query::LanguageInfo.new(catalog: @catalog, fulltext: @fulltext)
      assert_equal results, [fallback.relevance("chu"), fallback.held],
                   "the pre-019 fallback must produce identical relevance and held lists"
    end
  end
end
