# frozen_string_literal: true

require "test_helper"

module Export
  # Nabu::Export::Lemmas (P121 assembly): the lemma × century attestation
  # matrix out of the precompiled lemma_rollup — the exporter face of the
  # `nabu lemma` desk's rows. Reads ONLY the rollup (never passages): a
  # catalog without migration 038 refuses with the migration hint, an
  # empty rollup exports honestly with the refresh note.
  class LemmasTest < Minitest::Test
    include StoreTestDB

    COLUMNS = %w[lemma language century basis grade source
                 occurrences documents license_class].freeze

    def setup
      @catalog = store_test_db
      @alpha = Nabu::Store::Source.create(slug: "alpha", name: "alpha", adapter_class: "TestAdapter",
                                          license_class: "open")
      @beta = Nabu::Store::Source.create(slug: "beta", name: "beta", adapter_class: "TestAdapter",
                                         license_class: "nc")
    end

    def cell(lemma:, language:, grade:, source:, century: nil, basis: nil, occurrences: 1, documents: 1)
      @catalog[:lemma_rollup].insert(lemma: lemma, language: language, century: century, basis: basis,
                                     grade: grade, source_id: source.id, occurrences: occurrences,
                                     documents: documents)
    end

    def rows(**)
      table = Nabu::Export::Lemmas.new(catalog: @catalog, **)
      collected = []
      table.each_row { |row| collected << row }
      [table, collected]
    end

    def test_columns_and_values_round_trip
      cell(lemma: "lupus", language: "lat", century: -1, basis: "composition", grade: "gold",
           source: @alpha, occurrences: 7, documents: 3)
      table, collected = rows
      assert_equal COLUMNS, table.columns.map(&:name)
      assert_equal 1, collected.size
      assert_equal ["lupus", "lat", -1, "composition", "gold", "alpha", 7, 3, "open"], collected.first.values
      assert_equal [%w[alpha open]], collected.first.draws
      assert_empty table.notes, "a non-empty export carries no empty-rollup note"
    end

    def test_undated_cells_export_with_null_century_and_basis
      cell(lemma: "zima", language: "chu", grade: "silver", source: @beta)
      _, collected = rows
      assert_equal ["zima", "chu", nil, nil, "silver", "beta", 1, 1, "nc"], collected.first.values
    end

    def test_language_and_grade_filters_narrow_and_echo_into_filters
      cell(lemma: "lupus", language: "lat", grade: "gold", source: @alpha)
      cell(lemma: "lykos", language: "grc", grade: "gold", source: @alpha)
      cell(lemma: "lupus", language: "lat", grade: "silver", source: @beta)
      table, collected = rows(langs: ["lat"], grades: ["gold"])
      assert_equal [["lupus", "lat", nil, nil, "gold", "alpha", 1, 1, "open"]], collected.map(&:values)
      assert_equal({ "language" => ["lat"], "grade" => ["gold"] }, table.filters)
    end

    def test_an_unknown_grade_refuses
      error = assert_raises(Nabu::Export::Error) { Nabu::Export::Lemmas.new(catalog: @catalog, grades: ["bronze"]) }
      assert_match(/bronze/, error.message)
    end

    def test_paging_streams_every_row_once
      30.times { |i| cell(lemma: "l#{i}", language: "lat", grade: "gold", source: @alpha) }
      table = Nabu::Export::Lemmas.new(catalog: @catalog, page_size: 7)
      lemmas = []
      table.each_row { |row| lemmas << row.values.first }
      assert_equal (0...30).map { |i| "l#{i}" }.sort, lemmas.sort
      assert_equal 30, lemmas.size, "keyset paging yields each row exactly once"
    end

    def test_an_empty_rollup_exports_honestly_with_the_refresh_note
      table, collected = rows
      assert_empty collected
      assert_equal true, table.notes["rollup_empty"]
      assert_match(/builders:refresh/, table.notes["hint"])
    end

    def test_a_catalog_without_the_rollup_refuses_with_the_migration_hint
      @catalog.drop_table(:lemma_rollup)
      error = assert_raises(Nabu::Export::Error) { rows }
      assert_match(/migration 038/, error.message)
    end

    def test_the_table_is_registered
      assert_equal Nabu::Export::Lemmas, Nabu::Export.table("lemmas")
      assert_includes Nabu::Export.names, "lemmas"
    end
  end
end
