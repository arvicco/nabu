# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::LemmaFrequencies (P42-1): the corpus lemma-frequency table —
  # gold/silver/equivalence passage counts per (lemma_folded, language, tier),
  # derived from passage_lemmas and living beside it in fulltext.sqlite3. The
  # write-time census that vocab's log-odds denominator and etym's attestation
  # counts read instead of re-aggregating the whole lemma index per query.
  #
  # Same rig as IndexerTest: a fresh in-memory catalog, a separate in-memory
  # fulltext, the real Indexer building passage_lemmas so the derivation runs
  # the true fold → count path. The wholesale-vs-incremental equivalence is
  # the load-bearing test (the SourceStats precedent): a source re-synced
  # through refresh_source! must leave the freq table byte-identical to a full
  # rebuild of the same catalog.
  class LemmaFrequenciesTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "open"
      )
      @silver = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(urn:, source: @source, language: "lat", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "T", language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, sequence:, language: "lat", lemmas: [], withdrawn: false)
      tokens = lemmas.map { |lemma| { "lemma" => lemma, "form" => lemma } }
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: lemmas.join(" "), text_normalized: lemmas.join(" "),
        annotations_json: JSON.generate({ "tokens" => tokens }),
        content_sha256: "x#{urn}#{lemmas.join}", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!(lemma_tiers: { "auto" => "silver" })
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, lemma_tiers: lemma_tiers)
    end

    def freq_rows
      @fulltext[Nabu::Store::LemmaFrequencies::TABLE]
        .order(:lemma_folded, :language, :tier)
        .select(:lemma_folded, :language, :tier, :passage_count).all
    end

    def seed_two_docs
      d1 = make_document(urn: "urn:d1", language: "lat")
      make_passage(d1, urn: "urn:d1:1", sequence: 0, lemmas: %w[sum et sum])
      make_passage(d1, urn: "urn:d1:2", sequence: 1, lemmas: %w[hostis sum])
      d2 = make_document(urn: "urn:d2", source: @silver, language: "grc")
      make_passage(d2, urn: "urn:d2:1", sequence: 0, language: "grc", lemmas: %w[λογος])
    end

    # -- derivation ----------------------------------------------------------

    def test_rebuild_derives_one_row_per_lemma_language_tier
      seed_two_docs
      rebuild!

      # d1: sum in 2 passages (gold lat), et in 1, hostis in 1; d2: λογος silver grc.
      assert_equal(
        [{ lemma_folded: "et", language: "lat", tier: "gold", passage_count: 1 },
         { lemma_folded: "hostis", language: "lat", tier: "gold", passage_count: 1 },
         { lemma_folded: "sum", language: "lat", tier: "gold", passage_count: 2 },
         { lemma_folded: "λογοσ", language: "grc", tier: "silver", passage_count: 1 }],
        freq_rows
      )
    end

    def test_passage_frequency_not_token_frequency
      # "sum" appears 3 times as a TOKEN across 2 passages — the count is 2.
      d = make_document(urn: "urn:d")
      make_passage(d, urn: "urn:d:1", sequence: 0, lemmas: %w[sum sum])
      make_passage(d, urn: "urn:d:2", sequence: 1, lemmas: %w[sum])
      rebuild!

      row = freq_rows.find { |r| r[:lemma_folded] == "sum" }
      assert_equal 2, row[:passage_count]
    end

    def test_available_false_before_build_true_after
      refute Nabu::Store::LemmaFrequencies.available?(@fulltext)
      seed_two_docs
      rebuild!
      assert Nabu::Store::LemmaFrequencies.available?(@fulltext)
    end

    # -- readers -------------------------------------------------------------

    def test_gold_total_sums_only_gold_rows
      seed_two_docs
      rebuild!

      # gold passage-lemma rows: et(1) + hostis(1) + sum(2) = 4; silver excluded.
      assert_equal 4, Nabu::Store::LemmaFrequencies.gold_total(@fulltext)
    end

    def test_gold_frequencies_sum_across_languages
      d1 = make_document(urn: "urn:d1", language: "lat")
      make_passage(d1, urn: "urn:d1:1", sequence: 0, language: "lat", lemmas: %w[a])
      d2 = make_document(urn: "urn:d2", language: "grc")
      make_passage(d2, urn: "urn:d2:1", sequence: 0, language: "grc", lemmas: %w[a])
      rebuild!(lemma_tiers: {})

      # "a" occurs once in lat and once in grc — the vocab reader sums across
      # languages (its cross-language collapse), so corpus_freq[a] == 2.
      assert_equal({ "a" => 2 }, Nabu::Store::LemmaFrequencies.gold_frequencies(@fulltext, ["a"]))
    end

    def test_language_tier_counts_split_by_tier
      make_passage(make_document(urn: "urn:g", language: "chu"),
                   urn: "urn:g:1", sequence: 0, language: "chu", lemmas: %w[bog bog])
      make_passage(make_document(urn: "urn:s", source: @silver, language: "chu"),
                   urn: "urn:s:1", sequence: 0, language: "chu", lemmas: %w[bog])
      # "bog" appears in one gold passage and one silver passage of chu.
      rebuild!

      counts = Nabu::Store::LemmaFrequencies.language_tier_counts(@fulltext, language: "chu", folded: ["bog"])
      assert_equal({ "gold" => 1, "silver" => 1 }, counts["bog"])
    end

    # -- the sacred equivalence: incremental refresh == wholesale rebuild ----

    def test_refresh_source_leaves_freq_table_identical_to_wholesale
      seed_two_docs
      rebuild!
      wholesale = freq_rows

      # Mutate the gold source: drop "et", add "castra"; re-sync just that source
      # through the incremental index path, then compare.
      d1 = Nabu::Store::Document.first(urn: "urn:d1")
      Nabu::Store::Passage.where(document_id: d1.id).delete
      make_passage(d1, urn: "urn:d1:1", sequence: 0, lemmas: %w[sum castra])
      make_passage(d1, urn: "urn:d1:2", sequence: 1, lemmas: %w[hostis])
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext,
                                           slug: "proiel", lemma_tiers: { "auto" => "silver" })
      incremental = freq_rows

      # A fresh full rebuild of the same catalog is the reference.
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "auto" => "silver" })
      reference = freq_rows

      refute_equal wholesale, reference, "the mutation must actually change the table"
      assert_equal reference, incremental, "refresh_source! must match a full rebuild exactly"
    end

    def test_refresh_source_prunes_rows_that_reach_zero
      d = make_document(urn: "urn:only")
      make_passage(d, urn: "urn:only:1", sequence: 0, lemmas: %w[unicum])
      rebuild!(lemma_tiers: {})
      assert(freq_rows.any? { |r| r[:lemma_folded] == "unicum" })

      # Withdraw the sole passage attesting "unicum"; refresh removes the row.
      Nabu::Store::Passage.where(urn: "urn:only:1").update(withdrawn: true)
      Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext,
                                           slug: "proiel", lemma_tiers: {})
      refute(freq_rows.any? { |r| r[:lemma_folded] == "unicum" }, "a zeroed row is pruned")
    end
  end
end
