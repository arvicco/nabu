# frozen_string_literal: true

require "test_helper"
require "nabu/ops/embed_census"

module Ops
  # Nabu::Ops::EmbedCensus (`rake aggregates:embed_census`): fills
  # source_aggregates.vector_coverage_count — per source, the LIVE
  # passages holding a vector for the model in vectors.sqlite3. Explicit
  # only (never sync/rebuild: vectors outlive rebuilds); presence only.
  class EmbedCensusTest < Minitest::Test
    include StoreTestDB

    AGG = Nabu::Store::SourceAggregates
    CENSUS = Nabu::Ops::EmbedCensus

    def setup
      @db = store_test_db
      @source = make_source("texts")
    end

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "nc")
    end

    def load(source, docs)
      Nabu::Store::Loader.new(db: @db, source: source).load(docs)
    end

    def document(urn, count)
      doc = Nabu::Document.new(urn: urn, title: urn, language: "grc", canonical_path: "#{urn}.xml", metadata: {})
      count.times do |i|
        doc << Nabu::Passage.new(urn: "#{urn}:#{i + 1}", sequence: i, language: "grc", text: "w #{i}",
                                 text_normalized: "w #{i}")
      end
      doc
    end

    def coverage(source) = AGG.fetch(@db, source.id).vector_coverage_count

    def vectors_db(urns, model: Nabu::Embed::MODEL)
      vectors = Sequel.sqlite
      Nabu::Embed.ensure_schema!(vectors)
      urns.each { |urn| insert_vector(vectors, urn, model) }
      vectors
    end

    def insert_vector(vectors, urn, model)
      vectors[Nabu::Embed::VECTORS_TABLE].insert(model: model, urn: urn, language: "grc", text_sha: "x",
                                                 vec: Sequel.blob("v"))
    end

    def test_counts_live_embedded_passages_per_source
      load(@source, [document("u:a", 3), document("u:gone", 2)])
      other = make_source("other")
      load(other, [document("u:o", 2)])
      never = make_source("never")
      load(never, [document("u:n", 1)])
      load(@source, [document("u:a", 3)]) # the sweep withdraws u:gone
      vectors = vectors_db(%w[u:a:1 u:a:2 u:gone:1 u:o:1 u:o:2 u:orphan:1])
      insert_vector(vectors, "u:a:3", "another-model")
      walked = []

      tally = CENSUS.run!(catalog: @db, vectors: vectors, model: Nabu::Embed::MODEL, page: 2,
                          progress: ->(seen) { walked << seen })

      assert_equal({ @source.id => 2, other.id => 2 }, tally,
                   "live passages only, this model only; orphan urns and withdrawn rows count nowhere")
      assert_equal [2, 2, 0], [coverage(@source), coverage(other), coverage(never)],
                   "every row re-set: an untallied source is known-zero, never left NULL"
      assert_equal [2, 4, 6], walked, "one progress call per keyset page of vector rows"
    ensure
      vectors&.disconnect
    end

    def test_a_vectors_file_without_the_table_writes_zero_coverage
      load(@source, [document("u:a", 1)])
      vectors = Sequel.sqlite
      assert_equal({}, CENSUS.run!(catalog: @db, vectors: vectors, model: Nabu::Embed::MODEL))
      assert_equal 0, coverage(@source)
    ensure
      vectors&.disconnect
    end

    def test_a_catalog_without_the_aggregates_table_is_refused_with_nil
      @db.drop_table(AGG::TABLE)
      assert_nil CENSUS.run!(catalog: @db, vectors: Sequel.sqlite, model: Nabu::Embed::MODEL)
    end
  end
end
