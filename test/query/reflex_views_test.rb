# frozen_string_literal: true

require "test_helper"
require "json"

module Query
  # Nabu::Query::ReflexViews tier split (P26-0). The crosswalk read side keeps
  # +attested_count+ GOLD-ONLY — the number that has always meant "verified
  # annotation says this lemma is here" — and resolves a separate, labeled
  # +silver_count+ from the automatic-lemmatization rows beside it. A
  # silver-only reflex therefore reads (attested_count: nil, silver_count: n):
  # never a bare number a reader could take for gold. Shelf data is the real
  # wiktionary-recon fixture (the etym rig); the lemma index is the real
  # Indexer with a per-source tier map.
  class ReflexViewsTest < Minitest::Test
    include StoreTestDB

    BOG_URN = "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2"

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      @gold = Nabu::Store::Source.create(
        slug: "treebank", name: "Treebank", adapter_class: "TestAdapter", license_class: "open"
      )
      @silver = Nabu::Store::Source.create(
        slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def make_passages(source:, language:, lemma:, form:, count:)
      urn_stem = "urn:nabu:test:#{source.slug}:#{language}"
      document = Nabu::Store::Document.create(
        source_id: source.id, urn: urn_stem, title: "T", language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      count.times do |i|
        Nabu::Store::Passage.create(
          document_id: document.id, urn: "#{urn_stem}:#{i + 1}", sequence: i,
          language: language, text: form, text_normalized: form,
          annotations_json: JSON.generate({ "tokens" => [{ "lemma" => lemma, "form" => form }] }),
          content_sha256: "x", revision: 1
        )
      end
    end

    def rebuild!(lemma_tiers: { "auto" => "silver" })
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: lemma_tiers)
    end

    def bog_entry_id
      @catalog[:dictionary_entries].where(urn: BOG_URN).get(:id) || flunk("fixture entry missing")
    end

    def chu_bog_view
      views = Nabu::Query::ReflexViews.new(catalog: @catalog, fulltext: @fulltext)
                                      .for_entry(bog_entry_id)
      views.find { |v| v.language == "chu" && v.word == "богъ" } || flunk("chu богъ view missing")
    end

    def test_attested_count_stays_gold_only_with_silver_count_beside_it
      make_passages(source: @gold, language: "chu", lemma: "богъ", form: "ба", count: 2)
      make_passages(source: @silver, language: "chu", lemma: "богъ", form: "богъ", count: 3)
      rebuild!

      view = chu_bog_view
      assert_equal 2, view.attested_count, "attested_count keeps its gold-only meaning"
      assert_equal 3, view.silver_count, "the automatic rows count BESIDE it, labeled"
    end

    def test_silver_only_reflex_reads_nil_attested_and_a_labeled_silver_count
      make_passages(source: @silver, language: "chu", lemma: "богъ", form: "богъ", count: 3)
      rebuild!

      view = chu_bog_view
      assert_nil view.attested_count, "silver alone never claims gold attestation"
      assert_equal 3, view.silver_count
    end

    def test_unattested_reflex_reads_nil_on_both_tiers
      rebuild!

      view = chu_bog_view
      assert_nil view.attested_count
      assert_nil view.silver_count, "absence stays honest on the silver side too"
    end

    # A fulltext index built before the tier column existed: every row is a
    # gold row (only gold sources existed then), so the whole count stays
    # attested_count — the borrowed_column? pre-migration precedent.
    def test_pre_tier_lemma_index_counts_as_gold
      make_passages(source: @gold, language: "chu", lemma: "богъ", form: "ба", count: 2)
      rebuild!(lemma_tiers: nil)
      @fulltext.alter_table(Nabu::Store::Indexer::LEMMA_TABLE) { drop_column :tier }

      view = chu_bog_view
      assert_equal 2, view.attested_count
      assert_nil view.silver_count
    end
  end
end
