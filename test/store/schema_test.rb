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

    # P50-r1 (migration 022): sources.last_ingest_identity — the last-INGEST
    # canonical identity the `nabu data build` stale-ingest guard reads. The
    # backfill copies each stamped source's canonical_identity: the stamp
    # asserts the rows satisfied that identity at the last rebuild, so the
    # copy can only cause honest refusals (canonical moved since) — never a
    # false pass. Unstamped sources stay nil (= "cannot prove", guard refuses).
    def test_migration_022_backfills_last_ingest_identity_from_derivation_stamps
      db = Sequel.sqlite
      require "sequel/extensions/migration"
      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: 21, allow_missing_migration_files: true)
      db[:sources].insert(slug: "alpha", name: "Alpha", adapter_class: "T", license_class: "open")
      db[:sources].insert(slug: "beta", name: "Beta", adapter_class: "T", license_class: "open")
      db[:derivation_stamps].insert(
        slug: "alpha", fingerprint: "f" * 64, canonical_identity: "c" * 64, parser_digest: "p",
        fold_digest: "d", migration_level: 21, config_json: "{}", stamped_at: Time.now
      )

      Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, allow_missing_migration_files: true)

      assert_equal "c" * 64, db[:sources].first(slug: "alpha")[:last_ingest_identity]
      assert_nil db[:sources].first(slug: "beta")[:last_ingest_identity],
                 "an unstamped source has no honest identity to backfill"
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

    # The passage-grain facet surface (migration 045): a per-source value
    # dictionary (the vocabulary a pattern scans) + a WITHOUT ROWID pair
    # table keyed (value_id, passage_id) — the filter index IS the table.
    def test_passage_facet_tables_are_dictionary_encoded
      values = @db.schema(:passage_facet_values).to_h
      assert_equal false, values[:source_id][:allow_null]
      assert_equal false, values[:facet][:allow_null]
      assert_equal false, values[:value][:allow_null]
      refute values[:ref][:allow_null] == false, "ref is optional (labels carry none)"
      assert(@db.indexes(:passage_facet_values).values.any? { |i| i[:columns] == %i[facet value] })
      assert(@db.indexes(:passage_facet_values).values.any? { |i| i[:columns] == %i[source_id] })

      pairs = @db.schema(:passage_facets).to_h
      assert_equal %i[passage_id value_id], pairs.keys.sort
      assert pairs[:value_id][:primary_key]
      assert pairs[:passage_id][:primary_key]
      ddl = @db["SELECT sql FROM sqlite_master WHERE name = 'passage_facets'"].get(:sql)
      assert_match(/WITHOUT ROWID/i, ddl)
    end

    # The inline-entity index (migration 050): a per-source verbatim name
    # dictionary carrying a folded search key + a WITHOUT ROWID
    # (name_id, passage_id) pair table.
    def test_passage_entity_tables_are_dictionary_encoded
      names = @db.schema(:passage_entity_names).to_h
      assert_equal false, names[:source_id][:allow_null]
      assert_equal false, names[:search_key][:allow_null]
      %i[type text identity key ref subtype].each do |column|
        refute names[column][:allow_null] == false, "#{column} is optional (verbatim, often absent)"
      end
      assert(@db.indexes(:passage_entity_names).values.any? { |i| i[:columns] == %i[source_id] })

      pairs = @db.schema(:passage_entities).to_h
      assert_equal %i[name_id passage_id], pairs.keys.sort
      assert pairs[:name_id][:primary_key]
      assert pairs[:passage_id][:primary_key]
      ddl = @db["SELECT sql FROM sqlite_master WHERE name = 'passage_entities'"].get(:sql)
      assert_match(/WITHOUT ROWID/i, ddl)
    end

    # The dictionary-entry grain of the same mold (migration 046): entries
    # carry their annotations (nullable — NULL is "none", the common case
    # on million-entry shelves), and the facet surface is a per-source
    # value dictionary + a WITHOUT ROWID (value_id, entry_id) pair table.
    def test_entry_facet_tables_are_dictionary_encoded
      column = @db.schema(:dictionary_entries).to_h[:annotations_json]
      refute_nil column, "dictionary_entries.annotations_json missing (migration 046)"
      refute column[:allow_null] == false, "annotations_json is NULL for an unannotated entry"

      values = @db.schema(:entry_facet_values).to_h
      assert_equal false, values[:source_id][:allow_null]
      assert_equal false, values[:facet][:allow_null]
      assert_equal false, values[:value][:allow_null]
      refute values[:ref][:allow_null] == false, "ref is optional (labels carry none)"
      assert(@db.indexes(:entry_facet_values).values.any? { |i| i[:columns] == %i[facet value] })
      assert(@db.indexes(:entry_facet_values).values.any? { |i| i[:columns] == %i[source_id] })

      pairs = @db.schema(:entry_facets).to_h
      assert_equal %i[entry_id value_id], pairs.keys.sort
      assert pairs[:value_id][:primary_key]
      assert pairs[:entry_id][:primary_key]
      ddl = @db["SELECT sql FROM sqlite_master WHERE name = 'entry_facets'"].get(:sql)
      assert_match(/WITHOUT ROWID/i, ddl)
      # Migration 049: the reverse probe (an entry's own facets, the define
      # card) answers by index, never a pair-table scan.
      assert(@db.indexes(:entry_facets).values.any? { |i| i[:columns] == %i[entry_id] },
             "entry_facets(entry_id) index missing (migration 049)")
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

    # Migration 048: the single-column passages(document_id) index is gone —
    # the unique (document_id, sequence) index's left prefix serves every
    # document_id probe (EXPLAIN QUERY PLAN verified against the live
    # statistics: each consumer switches to the composite, none scans).
    def test_passages_carries_no_redundant_document_id_index
      refute(@db.indexes(:passages).values.any? { |i| i[:columns] == [:document_id] },
             "passages(document_id) is redundant beside the (document_id, sequence) unique index")
    end

    # A catalog migrated through 047 (index present, the live shape) and then
    # forward ends with exactly the index set a from-zero migration creates.
    def test_migration_048_converges_with_a_fresh_schema
      require "sequel/extensions/migration"
      upgraded = Sequel.sqlite
      Sequel::Migrator.run(upgraded, Nabu::Store::MIGRATIONS_DIR, target: 47, allow_missing_migration_files: true)
      assert(upgraded.indexes(:passages).values.any? { |i| i[:columns] == [:document_id] },
             "precondition: the pre-048 schema carries the single-column index")
      Sequel::Migrator.run(upgraded, Nabu::Store::MIGRATIONS_DIR, allow_missing_migration_files: true)

      assert_equal @db.indexes(:passages), upgraded.indexes(:passages)
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

    def test_license_class_check_accepts_all_six_values
      # odbl joined the enum in migration 018 (P40-6, D40-c: Rundata/SRDB).
      %w[open attribution nc odbl research_private restricted].each_with_index do |lc, i|
        @db[:sources].insert(slug: "s#{i}", name: "S", adapter_class: "X", license_class: lc)
      end
      assert_equal 6, @db[:sources].count
    end

    def test_documents_license_override_check_allows_null_and_valid
      source_id = insert_source
      @db[:documents].insert(document_row(source_id).merge(license_override: nil))
      @db[:documents].insert(document_row(source_id, urn: "urn:doc:2").merge(license_override: "nc"))
      @db[:documents].insert(document_row(source_id, urn: "urn:doc:3").merge(license_override: "odbl"))
      assert_equal 3, @db[:documents].count
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
