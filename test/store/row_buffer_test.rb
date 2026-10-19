# frozen_string_literal: true

require "test_helper"

module Store
  # Store::RowBuffer: the builders' batched write path. Rows land in the
  # order they were added (so autoincrement ids are what row-at-a-time
  # inserts minted), as multi-row INSERTs, inside one transaction.
  class RowBufferTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      source = @db[:sources].insert(slug: "s", name: "s", adapter_class: "X", license_class: "open")
      @doc = @db[:documents].insert(source_id: source, urn: "urn:d", title: "t", language: "grc",
                                    canonical_path: "/d", metadata_json: "{}", content_sha256: "x",
                                    revision: 1, withdrawn: false, retired_upstream: false)
    end

    def facet(value, raw: nil) = { document_id: @doc, facet: "genre", value: value, raw: raw }

    def inserts(&)
      io = StringIO.new
      @db.loggers << Logger.new(io)
      yield
      @db.loggers.clear
      io.string.lines.count { |line| line.include?("INSERT INTO `document_facets`") }
    end

    def test_rows_land_in_order_in_slices
      statements = inserts do
        count = Nabu::Store::RowBuffer.into(@db[:document_facets], slice: 2) do |rows|
          %w[a b c d e].each { |value| rows.insert(facet(value)) }
        end

        assert_equal 5, count
      end

      assert_equal 3, statements # 2 + 2 + the trailing 1
      assert_equal %w[a b c d e], @db[:document_facets].order(:id).select_map(:value)
    end

    # A row whose column set differs from the buffered run flushes the run
    # first: each statement carries one column set, so an omitted column
    # keeps its table default exactly as a row-at-a-time insert left it.
    def test_a_changed_column_set_flushes_the_run
      Nabu::Store::RowBuffer.into(@db[:document_facets]) do |rows|
        rows.insert(facet("a"))
        rows.insert({ document_id: @doc, facet: "genre", value: "b" })
        rows.insert(facet("c", raw: "C"))
      end

      assert_equal [["a", nil], ["b", nil], %w[c C]],
                   @db[:document_facets].order(:id).select_map(%i[value raw])
    end

    def test_the_buffer_writes_inside_one_transaction
      io = StringIO.new
      @db.loggers << Logger.new(io)
      Nabu::Store::RowBuffer.into(@db[:document_facets], slice: 1) do |rows|
        3.times { |i| rows.insert(facet(i.to_s)) }
      end
      @db.loggers.clear

      assert_equal(1, io.string.lines.count { |line| line.include?("BEGIN") })
      assert_equal(1, io.string.lines.count { |line| line.include?("COMMIT") })
    end

    def test_transaction_false_commits_per_statement
      io = StringIO.new
      @db.loggers << Logger.new(io)
      Nabu::Store::RowBuffer.into(@db[:document_facets], slice: 2, transaction: false) do |rows|
        3.times { |i| rows.insert(facet(i.to_s)) }
      end
      @db.loggers.clear

      assert_equal(0, io.string.lines.count { |line| line.include?("BEGIN") })
      assert_equal 3, @db[:document_facets].count
    end

    def write_then_return
      Nabu::Store::RowBuffer.into(@db[:document_facets]) do |rows|
        rows.insert(facet("a"))
        return :early
      end
    end

    # A `return` out of the caller's block still lands the buffered rows
    # (the transaction commits on a non-local exit)...
    def test_a_non_local_exit_still_flushes
      assert_equal :early, write_then_return
      assert_equal %w[a], @db[:document_facets].select_map(:value)
    end

    # ...while an exception rolls the whole lane back.
    def test_an_exception_writes_nothing
      assert_raises(Nabu::Error) do
        Nabu::Store::RowBuffer.into(@db[:document_facets], slice: 1) do |rows|
          rows.insert(facet("a"))
          rows.insert(facet("b"))
          raise Nabu::Error, "lane failed"
        end
      end

      assert_equal 0, @db[:document_facets].count
    end

    def test_an_empty_buffer_writes_nothing
      statements = inserts { assert_equal 0, Nabu::Store::RowBuffer.into(@db[:document_facets]) { |_rows| nil } }

      assert_equal 0, statements
    end
  end
end
