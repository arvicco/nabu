# frozen_string_literal: true

require "test_helper"

module Store
  class SchemaTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
    end

    def test_migrations_create_all_tables
      %i[sources documents passages provenance enrichments document_axes document_facets].each do |table|
        assert @db.table_exists?(table), "expected table #{table} to exist"
      end
    end

    # P17-2: the facet table is skinny and open-vocabulary — facet/value
    # required, raw (the upstream verbatim, `?` certainty included) optional.
    def test_document_facets_columns_and_index
      columns = @db.schema(:document_facets).to_h
      assert_equal false, columns[:facet][:allow_null], "facet is required"
      assert_equal false, columns[:value][:allow_null], "value is required"
      refute columns[:raw][:allow_null] == false, "raw is optional"
      assert(@db.indexes(:document_facets).values.any? { |i| i[:columns] == %i[facet value] })
    end

    # P17-2 rider: documents carry their adapter-emitted metadata (persons,
    # crosswalk ids, facets) — NOT NULL, default "{}", never content-hashed.
    def test_documents_metadata_json_column_defaults_to_empty_object
      column = @db.schema(:documents).to_h[:metadata_json]
      refute_nil column, "documents.metadata_json missing (migration 009)"
      assert_equal false, column[:allow_null]

      source_id = insert_source
      id = @db[:documents].insert(document_row(source_id))
      assert_equal "{}", @db[:documents].first(id: id)[:metadata_json]
    end

    # P15-2: the timeline is document-keyed, signed-integer-year columns.
    def test_document_axes_columns
      columns = @db.schema(:document_axes).to_h
      assert_equal :integer, columns[:not_before][:type]
      assert_equal :integer, columns[:not_after][:type]
      refute columns[:not_before][:allow_null] == false, "either bound may be NULL (open-ended)"
      assert_equal false, columns[:axis_source][:allow_null], "axis_source is required"
    end

    # P17-3 (migration 010): the crosswalk's per-edge loan flag — NULLABLE
    # boolean, three honest states (true/false from the flag-aware parser,
    # NULL = the row predates the reparse; the parse-only resync backfills).
    def test_dictionary_reflexes_borrowed_is_a_nullable_boolean
      column = @db.schema(:dictionary_reflexes).to_h[:borrowed]
      refute_nil column, "dictionary_reflexes.borrowed must exist (migration 010)"
      assert_equal :boolean, column[:type]
      refute_equal false, column[:allow_null], "NULL is the pre-reparse honest unknown"
    end

    # P7-1: runs and source_repos moved to the history ledger (as slug-keyed
    # runs and pins — see ledger_test.rb); migration 005 drops them from the
    # catalog, along with the license baseline column.
    def test_history_tables_are_not_in_the_catalog
      refute @db.table_exists?(:runs), "runs live in db/history.sqlite3 now"
      refute @db.table_exists?(:source_repos), "pins live in db/history.sqlite3 now"
      refute @db[:sources].columns.include?(:license_baseline_sha256)
    end

    def test_sources_slug_unique_index_present
      assert(@db.indexes(:sources).values.any? { |i| i[:columns] == [:slug] && i[:unique] })
    end

    def test_documents_urn_unique_index_present
      assert(@db.indexes(:documents).values.any? { |i| i[:columns] == [:urn] && i[:unique] })
      # P18-4 follow-up (migration 012): the `nabu language` card's live
      # relevance counts query by language column — indexed, never scanned.
      assert(@db.indexes(:dictionary_reflexes).values.any? { |i| i[:columns] == [:lang_code] },
             "dictionary_reflexes.lang_code index missing (migration 012)")
      assert(@db.indexes(:documents).values.any? { |i| i[:columns] == [:language] },
             "documents.language index missing (migration 012)")
      assert(@db.indexes(:passages).values.any? { |i| i[:columns] == [:language] },
             "passages.language index missing (migration 013)")
    end

    def test_passages_composite_unique_index_present
      assert(@db.indexes(:passages).values.any? { |i| i[:columns] == %i[document_id sequence] && i[:unique] })
    end

    def test_enrichments_composite_index_present
      assert(@db.indexes(:enrichments).values.any? { |i| i[:columns] == %i[passage_id kind] })
    end

    def test_provenance_passage_id_index_present
      assert(@db.indexes(:provenance).values.any? { |i| i[:columns] == [:passage_id] })
    end

    # P5-2: documents carry retired_upstream (upstream scrapped the file; the
    # attic kept it) — distinct from withdrawn, NOT NULL, default false.
    def test_documents_retired_upstream_column_defaults_false
      column = @db.schema(:documents).to_h[:retired_upstream]
      refute_nil column, "documents.retired_upstream must exist (migration 002)"
      refute column[:allow_null]

      source_id = insert_source
      id = @db[:documents].insert(document_row(source_id))
      assert_equal false, @db[:documents].first(id: id)[:retired_upstream]
    end

    def test_license_class_check_rejects_bad_value
      error = assert_raises(Sequel::DatabaseError) do
        @db[:sources].insert(
          slug: "bad", name: "Bad", adapter_class: "X", license_class: "bogus"
        )
      end
      assert_match(/constraint/i, error.message)
    end

    def test_license_class_check_accepts_all_five_values
      %w[open attribution nc research_private restricted].each_with_index do |lc, i|
        @db[:sources].insert(slug: "s#{i}", name: "S", adapter_class: "X", license_class: lc)
      end
      assert_equal 5, @db[:sources].count
    end

    def test_documents_license_override_check_allows_null_and_valid
      source_id = insert_source
      @db[:documents].insert(document_row(source_id).merge(license_override: nil))
      @db[:documents].insert(document_row(source_id, urn: "urn:doc:2").merge(license_override: "nc"))
      assert_equal 2, @db[:documents].count
    end

    def test_documents_license_override_check_rejects_bad_value
      source_id = insert_source
      assert_raises(Sequel::DatabaseError) do
        @db[:documents].insert(document_row(source_id).merge(license_override: "bogus"))
      end
    end

    def test_documents_urn_unique_rejects_duplicates
      source_id = insert_source
      @db[:documents].insert(document_row(source_id))
      assert_raises(Sequel::DatabaseError) do
        @db[:documents].insert(document_row(source_id))
      end
    end

    def test_foreign_key_enforced_on_passages
      assert_raises(Sequel::DatabaseError) do
        @db[:passages].insert(
          document_id: 9999, urn: "urn:p:1", sequence: 1,
          text: "x", text_normalized: "x", content_sha256: "abc"
        )
      end
    end

    def test_passages_composite_uniqueness_enforced
      source_id = insert_source
      document_id = @db[:documents].insert(document_row(source_id))
      @db[:passages].insert(passage_row(document_id, sequence: 1, urn: "urn:p:1"))
      assert_raises(Sequel::DatabaseError) do
        @db[:passages].insert(passage_row(document_id, sequence: 1, urn: "urn:p:2"))
      end
    end

    private

    def insert_source
      @db[:sources].insert(slug: "s", name: "S", adapter_class: "X", license_class: "open")
    end

    def document_row(source_id, urn: "urn:doc:1")
      { source_id: source_id, urn: urn, content_sha256: "abc" }
    end

    def passage_row(document_id, sequence:, urn:)
      {
        document_id: document_id, urn: urn, sequence: sequence,
        text: "x", text_normalized: "x", content_sha256: "abc"
      }
    end
  end
end
