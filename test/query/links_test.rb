# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Links (P16-1): the links-journal reader — edges both
  # directions, grouped by kind, counterparts resolved through the catalog by
  # urn (the rebuild-proof join).
  class LinksTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      @source = Nabu::Store::Source.create(
        slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @journal.disconnect
    end

    def make_passage(doc_urn:, urn:, title:, language: "grc")
      document = Nabu::Store::Document.find(urn: doc_urn) || Nabu::Store::Document.create(
        source_id: @source.id, urn: doc_urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: 0, language: language,
        text: "t", text_normalized: "t", annotations_json: "{}",
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def seed_run(scope: "urn:a", params: { min_score: 0.05 })
      Nabu::Store::LinksJournal.record_run!(
        @journal, producer: "parallels", scope: scope, params: params, code_version: "test/1"
      )
    end

    def seed_edge(from:, to:, run_id:, kind: "parallel", score: 1.0)
      Nabu::Store::LinksJournal.write_edge!(
        @journal, from_urn: from, to_urn: to, kind: kind, score: score, run_id: run_id
      )
    end

    def reader
      Nabu::Query::Links.new(catalog: @catalog, journal: @journal)
    end

    # -- both directions, grouped, resolved ------------------------------------

    def test_reads_both_directions_grouped_by_kind_with_resolution
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      make_passage(doc_urn: "urn:b", urn: "urn:b:1", title: "Beta")
      make_passage(doc_urn: "urn:c", urn: "urn:c:1", title: "Gamma", language: "lat")
      run_id = seed_run
      seed_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, score: 2.0)
      seed_edge(from: "urn:c:1", to: "urn:a:1", run_id: run_id, score: 0.5)
      seed_edge(from: "urn:a:1", to: "urn:c:1", run_id: run_id, kind: "formula", score: 1.0)

      result = reader.run("urn:a:1")
      assert_equal "Alpha", result.title
      assert_equal 3, result.total
      assert_equal %w[formula parallel], result.groups.keys.sort

      parallels = result.groups.fetch("parallel")
      assert_equal [%i[out in], %w[urn:b:1 urn:c:1]],
                   [parallels.map(&:direction), parallels.map(&:urn)],
                   "score-desc within the kind; direction as stored"
      out_edge = parallels.first
      assert_equal %w[Beta grc open], [out_edge.title, out_edge.language, out_edge.license_class]
      assert_predicate out_edge, :resolved?
      assert_equal [run_id], result.runs.map(&:id)
      assert_equal "parallels", result.runs.first.producer
      assert_equal({ "min_score" => 0.05 }, result.runs.first.params)
    end

    def test_detail_rides_the_edge_through_the_result
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      make_passage(doc_urn: "urn:b", urn: "urn:b:1", title: "Beta")
      run_id = seed_run
      Nabu::Store::LinksJournal.write_edge!(
        @journal, from_urn: "urn:a:1", to_urn: "urn:b:1", kind: "cognate",
                  score: 1.0, detail: "MARK 1.1 · *bʰeh₂g- [ine-pro]", run_id: run_id
      )
      seed_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id, kind: "parallel")

      groups = reader.run("urn:a:1").groups
      assert_equal "MARK 1.1 · *bʰeh₂g- [ine-pro]", groups.fetch("cognate").first.detail
      assert_nil groups.fetch("parallel").first.detail, "parallel edges carry no detail"
    end

    def test_counterpart_missing_from_catalog_is_honestly_unresolved
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      run_id = seed_run
      seed_edge(from: "urn:a:1", to: "urn:gone:9", run_id: run_id)

      edge = reader.run("urn:a:1").groups.fetch("parallel").first
      assert_equal "urn:gone:9", edge.urn
      refute_predicate edge, :resolved?
    end

    # P19-4: reference edges point at whole DOCUMENTS (a local-library
    # article beside the passages it discusses) — a counterpart no passage
    # answers for resolves at document grain, with the document's effective
    # license (source class or override), before falling to "(not in
    # catalog)".
    def test_document_urn_counterparts_resolve_at_document_grain
      make_passage(doc_urn: "urn:b", urn: "urn:b:1", title: "Discussed edition")
      shelf = Nabu::Store::Source.create(
        slug: "local-library", name: "Local library", adapter_class: "X",
        license_class: "research_private"
      )
      Nabu::Store::Document.create(
        source_id: shelf.id, urn: "urn:nabu:local-library:c:article", title: "The article",
        language: "deu", content_sha256: "x", revision: 1, withdrawn: false
      )
      run_id = seed_run
      Nabu::Store::LinksJournal.write_edge!(
        @journal, from_urn: "urn:nabu:local-library:c:article", to_urn: "urn:b:1",
                  kind: "reference", score: nil, detail: "manifest local-library/c/manifest.yml", run_id: run_id
      )

      edge = reader.run("urn:b:1").groups.fetch("reference").first
      assert_equal "urn:nabu:local-library:c:article", edge.urn
      assert_predicate edge, :resolved?
      assert_equal ["The article", "deu", "research_private"],
                   [edge.title, edge.language, edge.license_class],
                   "document-grain resolution carries the shelf's license label"
      assert_equal "manifest local-library/c/manifest.yml", edge.detail

      # And from the article's side the passage resolves as before.
      back = reader.run("urn:nabu:local-library:c:article")
      assert_equal "The article", back.title
      assert_equal "Discussed edition", back.groups.fetch("reference").first.title
    end

    # P28-3, the third resolution grain: an INGESTED dictionary shelf's
    # entry urns resolve to headword — dictionary title (with the shelf's
    # language + source license class); dict urns of shelves NOT ingested
    # (the eDIL/AED forward edges) still read "(not in catalog)".
    def test_dictionary_entry_counterparts_resolve_at_entry_grain
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      shelf = Nabu::Store::Source.create(
        slug: "ccl", name: "CCL", adapter_class: "X", license_class: "attribution"
      )
      dict = Nabu::Store::Dictionary.create(
        source_id: shelf.id, slug: "ccl", title: "Comprehensive Coptic Lexicon", language: "cop"
      )
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: dict.id, urn: "urn:nabu:dict:ccl:C1494", entry_id: "C1494",
        key_raw: "C1494", headword: "ⲕⲁϩ", headword_folded: "ⲕⲁϩ", body: "earth",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      run_id = seed_run
      Nabu::Store::LinksJournal.write_edge!(
        @journal, from_urn: "urn:nabu:dict:ccl:C1494", to_urn: "urn:nabu:dict:aed:159410",
                  kind: "etymology", score: nil, detail: "ⲕⲁϩ ← TLA 159410", run_id: run_id
      )
      Nabu::Store::LinksJournal.write_edge!(
        @journal, from_urn: "urn:a:1", to_urn: "urn:nabu:dict:ccl:C1494",
                  kind: "reference", score: nil, run_id: run_id
      )

      entry_edge = reader.run("urn:a:1").groups.fetch("reference").first
      assert_predicate entry_edge, :resolved?
      assert_equal ["ⲕⲁϩ — Comprehensive Coptic Lexicon", "cop", "attribution"],
                   [entry_edge.title, entry_edge.language, entry_edge.license_class]

      own = reader.run("urn:nabu:dict:ccl:C1494")
      assert_equal "ⲕⲁϩ — Comprehensive Coptic Lexicon", own.title,
                   "the entry urn resolves its own title too"
      aed = own.groups.fetch("etymology").first
      refute_predicate aed, :resolved?, "a not-yet-ingested shelf's urn stays honestly unresolved"
    end

    def test_edges_survive_catalog_absence_of_the_queried_urn
      # The journal outlives catalog rows: urn:a:1 is gone from the catalog
      # (a rebuild off slimmer canonical) but its edges still read by urn.
      make_passage(doc_urn: "urn:b", urn: "urn:b:1", title: "Beta")
      run_id = seed_run
      seed_edge(from: "urn:a:1", to: "urn:b:1", run_id: run_id)

      result = reader.run("urn:a:1")
      assert_nil result.title
      assert_equal 1, result.total
    end

    # -- states -----------------------------------------------------------------

    def test_known_urn_with_no_edges_is_an_empty_result_not_nil
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      result = reader.run("urn:a:1")
      assert_equal 0, result.total
      assert_empty result.groups
    end

    def test_document_urn_resolves_its_own_title_too
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      result = reader.run("urn:a")
      assert_equal "Alpha", result.title
    end

    def test_unknown_urn_with_no_edges_returns_nil
      assert_nil reader.run("urn:no:such")
    end
  end
end
