# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::SilverLemmaIndexer (P84-1): projects the local-lemmas
  # shelf (the silver-lemma enricher's non-derivable model output) into
  # passage_lemmas as tier-silver rows. Insert-if-absent — a urn with ANY
  # existing lemma rows is skipped, so gold (and upstream silver) is never
  # overwritten and re-applies are idempotent; the pass is a pure function
  # of shelf + catalog, so it survives `nabu rebuild` by construction.
  class SilverLemmaIndexerTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "edr", name: "EDR", adapter_class: "TestAdapter", license_class: "open"
      )
      @tmpdir = Dir.mktmpdir("nabu-silver-lemma")
      @shelf = Nabu::LemmaShelf.new(dir: File.join(@tmpdir, "local-lemmas"))
    end

    def teardown
      @fulltext.disconnect
      FileUtils.remove_entry(@tmpdir)
    end

    def make_document(urn: "urn:d:1", withdrawn: false, source: @source)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "t", language: "lat",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, sequence: 0, language: "lat", withdrawn: false,
                     text: "In fronte pedes", annotations: nil)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: text, content_sha256: "x", revision: 1,
        withdrawn: withdrawn, annotations_json: annotations ? JSON.generate(annotations) : "{}"
      )
    end

    def shelve(urn:, tokens:, language: "lat", source: "edr")
      @shelf.append_batch!(language: language, records: [
                             Nabu::LemmaShelf::Record.new(
                               urn: urn, language: language, source: source,
                               model: "stanza", model_version: "1.14.0", package: "la:ittb",
                               tokens: tokens, generated_at: "2026-08-27T00:00:00Z"
                             )
                           ])
    end

    def rebuild_gold! = Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    def apply!(**)
      Nabu::Store::SilverLemmaIndexer.apply!(
        catalog: @catalog, fulltext: @fulltext, shelf: @shelf, **
      )
    end

    def lemmas = @fulltext[:passage_lemmas]

    def test_applies_shelf_records_as_tier_silver_rows_grouped_by_folded_lemma
      doc = make_document
      passage = make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1",
             tokens: [%w[In in ADP], %w[Fronte frons NOUN], %w[fronte frons NOUN]])

      result = apply!
      assert_equal 1, result.passages_indexed
      rows = lemmas.where(urn: "urn:d:1:1").order(:lemma_folded).all
      assert_equal(%w[frons in], rows.map { |r| r[:lemma_folded] })
      frons = rows.first
      assert_equal "silver", frons[:tier]
      assert_equal "lat", frons[:language]
      assert_equal passage.id, frons[:passage_id]
      assert_equal "Fronte, fronte", frons[:surface_forms], "distinct surface forms, first-seen order"
    end

    def test_never_touches_a_passage_that_already_has_lemma_rows
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1",
                        annotations: { "tokens" => [{ "lemma" => "frons", "form" => "fronte" }] })
      rebuild_gold!
      assert_equal %w[gold], lemmas.where(urn: "urn:d:1:1").select_map(:tier)

      shelve(urn: "urn:d:1:1", tokens: [%w[fronte WRONG NOUN]])
      result = apply!
      assert_equal 0, result.passages_indexed
      assert_equal 1, result.skipped_covered
      assert_equal %w[gold], lemmas.where(urn: "urn:d:1:1").select_map(:tier),
                   "gold rows stand untouched; no silver row lands beside them"
    end

    def test_apply_is_idempotent
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[fronte frons NOUN]])

      apply!
      second = apply!
      assert_equal 0, second.passages_indexed
      assert_equal 1, second.skipped_covered
      assert_equal 1, lemmas.where(urn: "urn:d:1:1").count
    end

    def test_skips_missing_withdrawn_and_language_drifted_passages
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", withdrawn: true)
      make_passage(doc, urn: "urn:d:1:2", sequence: 1, language: "grc")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[a a X]])
      shelve(urn: "urn:d:1:2", tokens: [%w[b b X]])
      shelve(urn: "urn:d:1:gone", tokens: [%w[c c X]])

      result = apply!
      assert_equal 0, result.passages_indexed
      assert_equal 2, result.skipped_missing, "withdrawn and absent urns alike are not live"
      assert_equal 1, result.skipped_mismatch, "a language-drifted passage is skipped honestly"
      assert_equal 0, lemmas.count
    end

    def test_tokens_without_a_lemma_contribute_no_rows
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [["fronte", "frons", "NOUN"], ["·", "", "PUNCT"]])

      apply!
      assert_equal %w[frons], lemmas.where(urn: "urn:d:1:1").select_map(:lemma_folded)
    end

    def test_dictionary_filter_drops_unattested_non_identity_lemmas_for_flagged_sources
      dict = Nabu::Store::Dictionary.create(source_id: @source.id, slug: "lewis-short",
                                            title: "LS", language: "lat")
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict.id, urn: "urn:dict:ls:frons", entry_id: "frons", key_raw: "frons",
        headword: "frons", headword_folded: "frons", body: "b", content_sha256: "x"
      )
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [
               %w[fronte frons NOUN], # attested — kept
               %w[Aureliae Aurelius PROPN], # unattested, non-identity — dropped
               %w[ipsius ipsius X]          # identity — harmless, kept
             ])

      result = apply!(dictionary_filter_slugs: %w[edr])
      folded = lemmas.where(urn: "urn:d:1:1").select_map(:lemma_folded).sort
      assert_equal %w[frons ipsius], folded
      assert_equal 1, result.filtered_lemmas
    end

    def test_dictionary_filter_without_dictionary_rows_filters_nothing
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[Aureliae Aurelius PROPN]])

      apply!(dictionary_filter_slugs: %w[edr])
      assert_equal %w[aurelius], lemmas.where(urn: "urn:d:1:1").select_map(:lemma_folded),
                   "no dictionary to confirm against — dropping everything would be dishonest"
    end

    def test_update_frequencies_upserts_the_silver_counts
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      make_passage(doc, urn: "urn:d:1:2", sequence: 1)
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[fronte frons NOUN]])
      shelve(urn: "urn:d:1:2", tokens: [%w[frontibus frons NOUN]])

      apply!(update_frequencies: true)
      row = @fulltext[:lemma_frequencies].where(lemma_folded: "frons", tier: "silver").first
      assert_equal 2, row[:passage_count]
    end

    def test_urns_scope_restricts_the_pass
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      make_passage(doc, urn: "urn:d:1:2", sequence: 1)
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[a ab X]])
      shelve(urn: "urn:d:1:2", tokens: [%w[b bc X]])

      result = apply!(urns: Set.new(%w[urn:d:1:2]))
      assert_equal 1, result.passages_indexed
      assert_equal %w[urn:d:1:2], lemmas.select_map(:urn)
    end

    # №R-51-B (2026-08-29, flipping the P84-1 pin DELIBERATELY): a full
    # rebuild never projects the shelf — the projection is an owner-fired
    # act (`nabu lemma-enrich --index-only`), so the 99-minute replay tax
    # died with this test's old expectation.
    def test_full_rebuild_leaves_the_shelf_unprojected
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[fronte frons NOUN]])

      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, lemma_shelf: @shelf)
      assert_empty lemmas.where(urn: "urn:d:1:1", tier: "silver").all,
                   "the shelf stays unprojected until the owner fires the apply"
      assert_empty @fulltext[:lemma_frequencies].where(tier: "silver").all
    end

    # The arm-gate's other half: an index the owner never armed stays
    # silver-free through routine source refreshes — the projection can
    # never sneak back without an owner act.
    def test_refresh_source_stays_silver_free_when_unarmed
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[fronte frons NOUN]])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, lemma_shelf: @shelf)

      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "edr",
                                           lemma_shelf: @shelf)
      assert_empty lemmas.where(tier: "silver").all,
                   "unarmed → the sync-refresh must NOT re-introduce silver"
    end

    def test_refresh_source_reapplies_the_silver_slice
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1")
      rebuild_gold!
      shelve(urn: "urn:d:1:1", tokens: [%w[fronte frons NOUN]])
      apply!(update_frequencies: true)
      assert_equal %w[silver], lemmas.where(urn: "urn:d:1:1").select_map(:tier)

      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: "edr",
                                           lemma_shelf: @shelf)
      assert_equal %w[silver], lemmas.where(urn: "urn:d:1:1").select_map(:tier),
                   "a source re-sync must not silently strip its shelf-covered silver rows"
      assert_equal 1, @fulltext[:lemma_frequencies].where(lemma_folded: "frons", tier: "silver")
                                                   .get(:passage_count)
    end
  end
end
