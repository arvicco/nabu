# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::FacetBuilder (P17-2): document_facets projected from the
  # loaded documents' metadata_json — skinny rows, `?`-certainty surviving in
  # raw, drop-and-rebuild idempotent, withdrawn documents excluded.
  class FacetBuilderTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "edh", name: "EDH", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(urn, metadata: {}, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "lat",
        content_sha256: urn, revision: 1, withdrawn: withdrawn,
        metadata_json: JSON.generate(metadata)
      )
    end

    FACETS = {
      "facets" => {
        "genre" => { "value" => "epitaph", "raw" => "titsep?" },
        "province" => { "value" => "Pannonia inferior", "raw" => "PaI" }
      }
    }.freeze

    def test_projects_facet_rows_with_raw_certainty_surviving
      doc = make_document("urn:nabu:edh:hd000001", metadata: FACETS)
      summary = Nabu::Store::FacetBuilder.rebuild!(catalog: @db)

      assert_equal 1, summary.documents
      assert_equal 2, summary.rows
      rows = @db[:document_facets].where(document_id: doc.id).order(:facet).all
      assert_equal(%w[genre province], rows.map { |row| row[:facet] })
      assert_equal(["epitaph", "Pannonia inferior"], rows.map { |row| row[:value] })
      assert_equal "titsep?", rows.first[:raw], "the ? certainty survives in raw"
    end

    # P47-r3 (the lane-drift audit's health check caught it live): IIP
    # mints PLURAL "values" arrays ({"genre" => {"raw" => "#dedicatory",
    # "values" => ["dedicatory"]}}) — the singular-"value" reader skipped
    # every IIP facet and the source stayed dark through a full rebuild.
    # One row per value; both spellings first-class.
    def test_plural_values_arrays_project_one_row_per_value
      doc = make_document("urn:nabu:iip:zoor0001",
                          metadata: { "facets" => {
                            "genre" => { "raw" => "#dedicatory", "values" => ["dedicatory"] },
                            "religion" => { "values" => %w[jewish samaritan] }
                          } })
      summary = Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      assert_equal 1, summary.documents
      assert_equal 3, summary.rows
      rows = @db[:document_facets].where(document_id: doc.id).order(:facet, :value).all
      assert_equal([%w[genre dedicatory], %w[religion jewish], %w[religion samaritan]],
                   rows.map { |row| [row[:facet], row[:value]] })
      assert_equal "#dedicatory", rows.first[:raw]
    end

    def test_documents_without_facets_contribute_nothing
      make_document("urn:nabu:edh:hd000002", metadata: { "tm_nr" => "9" })
      summary = Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      assert_equal 0, summary.documents
      assert_equal 0, @db[:document_facets].count
    end

    def test_withdrawn_documents_are_excluded
      make_document("urn:nabu:edh:hd000003", metadata: FACETS, withdrawn: true)
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      assert_equal 0, @db[:document_facets].count
    end

    def test_rebuild_is_idempotent
      make_document("urn:nabu:edh:hd000004", metadata: FACETS)
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      first = @db[:document_facets].order(:id).all.map { |row| row.except(:id) }
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      second = @db[:document_facets].order(:id).all.map { |row| row.except(:id) }
      assert_equal first, second
      assert_equal 2, second.size, "drop-and-rebuild never accumulates"
    end

    def test_raw_less_facet_value_stands_alone
      make_document("urn:nabu:edh:hd000005",
                    metadata: { "facets" => { "material" => { "value" => "Marmor" } } })
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db)
      row = @db[:document_facets].first
      assert_equal "Marmor", row[:value]
      assert_nil row[:raw]
    end

    # -- the P104-1 metadata-field projection (Nabu::FacetMap) -------------

    def facet_map(fields)
      Nabu::FacetMap.new("sources" => { "edh" => { "fields" => fields } })
    end

    def test_facet_map_projects_declared_metadata_fields
      doc = make_document("urn:nabu:edh:hd000010",
                          metadata: { "corpus" => "Gaksadeungnok", "period" => "Old Babylonian" })
      summary = Nabu::Store::FacetBuilder.rebuild!(
        catalog: @db, facet_map: facet_map("corpus" => "collection", "period" => "period")
      )
      assert_equal 1, summary.documents
      assert_equal 2, summary.rows
      rows = @db[:document_facets].where(document_id: doc.id).order(:facet).all
      assert_equal(%w[collection period], rows.map { |row| row[:facet] })
      assert_equal(["Gaksadeungnok", "Old Babylonian"], rows.map { |row| row[:value] })
      assert_nil rows.first[:raw], "the value IS the upstream claim — nothing was normalized"
    end

    def test_facet_map_array_field_projects_one_row_per_value
      doc = make_document("urn:nabu:edh:hd000011",
                          metadata: { "languages" => %w[Egyptian Ugaritic] })
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db, facet_map: facet_map("languages" => "language"))
      values = @db[:document_facets].where(document_id: doc.id).order(:value).select_map(:value)
      assert_equal %w[Egyptian Ugaritic], values
    end

    def test_facet_map_skips_absent_empty_and_duplicate_values
      doc = make_document("urn:nabu:edh:hd000012",
                          metadata: { "corpus" => "", "languages" => ["Egyptian", "Egyptian", nil] })
      summary = Nabu::Store::FacetBuilder.rebuild!(
        catalog: @db, facet_map: facet_map("corpus" => "collection", "languages" => "language",
                                           "findspot" => "findspot")
      )
      assert_equal 1, summary.rows
      assert_equal [%w[language Egyptian]],
                   @db[:document_facets].where(document_id: doc.id).select_map(%i[facet value])
    end

    def test_facet_map_rides_beside_adapter_facets_without_double_counting_documents
      make_document("urn:nabu:edh:hd000013", metadata: FACETS.merge("corpus" => "Ilseongnok"))
      summary = Nabu::Store::FacetBuilder.rebuild!(catalog: @db, facet_map: facet_map("corpus" => "collection"))
      assert_equal 1, summary.documents, "one document, both lanes"
      assert_equal 3, summary.rows
    end

    def test_facet_map_excludes_withdrawn_documents
      make_document("urn:nabu:edh:hd000014", metadata: { "corpus" => "Ilseongnok" }, withdrawn: true)
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db, facet_map: facet_map("corpus" => "collection"))
      assert_equal 0, @db[:document_facets].count
    end

    def test_refresh_source_projects_the_facet_map_lane_too
      doc = make_document("urn:nabu:edh:hd000015", metadata: { "corpus" => "Ilseongnok" })
      rows = Nabu::Store::FacetBuilder.refresh_source!(
        catalog: @db, slug: "edh", facet_map: facet_map("corpus" => "collection")
      )
      assert_equal 1, rows
      assert_equal [%w[collection Ilseongnok]],
                   @db[:document_facets].where(document_id: doc.id).select_map(%i[facet value])
      # Idempotent per source: a second refresh never accumulates.
      Nabu::Store::FacetBuilder.refresh_source!(
        catalog: @db, slug: "edh", facet_map: facet_map("corpus" => "collection")
      )
      assert_equal 1, @db[:document_facets].count
    end

    def test_facet_map_rebuild_is_idempotent
      make_document("urn:nabu:edh:hd000016", metadata: { "corpus" => "Ilseongnok" })
      map = facet_map("corpus" => "collection")
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db, facet_map: map)
      first = @db[:document_facets].order(:id).all.map { |row| row.except(:id) }
      Nabu::Store::FacetBuilder.rebuild!(catalog: @db, facet_map: map)
      assert_equal(first, @db[:document_facets].order(:id).all.map { |row| row.except(:id) })
    end
  end
end
