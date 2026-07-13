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

    def test_counterpart_missing_from_catalog_is_honestly_unresolved
      make_passage(doc_urn: "urn:a", urn: "urn:a:1", title: "Alpha")
      run_id = seed_run
      seed_edge(from: "urn:a:1", to: "urn:gone:9", run_id: run_id)

      edge = reader.run("urn:a:1").groups.fetch("parallel").first
      assert_equal "urn:gone:9", edge.urn
      refute_predicate edge, :resolved?
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
