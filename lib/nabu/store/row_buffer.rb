# frozen_string_literal: true

require "English"

module Nabu
  module Store
    # The derived-table builders' write path: rows buffered in insertion
    # order and written as multi-row INSERTs, +slice+ rows per statement,
    # all inside ONE transaction. Row-at-a-time inserts in autocommit pay a
    # commit per row (measured 7-10x slower on 100k document_axes rows);
    # this keeps the bytes identical — same rows, same order, so the same
    # autoincrement ids — and drops the per-row overhead.
    #
    # Each statement carries ONE column set: a row whose keys differ from
    # the buffered run flushes the run first (Sequel's multi_insert takes
    # the first row's columns), so an omitted column keeps its table
    # default exactly as a single-row insert left it.
    #
    # Rows are only VISIBLE once flushed: a lane that reads back what it
    # wrote must flush first (no builder does today).
    class RowBuffer
      SLICE = 2_000

      # Yields a buffer over +dataset+ inside a transaction, flushes the
      # tail, and returns how many rows were written. +transaction: false+
      # commits per statement instead — for a library-wide lane whose rows
      # would otherwise pile millions into one transaction (each statement
      # still carries +slice+ rows, so the commit cost stays 1/slice).
      def self.into(dataset, slice: SLICE, transaction: true)
        buffer = new(dataset, slice: slice)
        write = lambda do |*|
          failed = true
          yield buffer
          failed = false
        ensure
          # Flush on completion AND on a non-local exit (a `return` out of
          # the caller's block, which the transaction commits); never on an
          # exception, which rolls the transaction back.
          buffer.flush unless failed && $ERROR_INFO
        end
        transaction ? dataset.db.transaction(&write) : write.call
        buffer.count
      end

      attr_reader :count

      def initialize(dataset, slice: SLICE)
        @dataset = dataset
        @slice = slice
        @rows = []
        @keys = nil
        @count = 0
      end

      # Same call shape as Dataset#insert, so a lane swaps its target, not
      # its row hashes.
      def insert(row)
        flush unless @keys.nil? || row.keys == @keys
        @keys = row.keys
        @rows << row
        @count += 1
        flush if @rows.size >= @slice
        self
      end

      def flush
        @dataset.multi_insert(@rows) unless @rows.empty?
        @rows = []
        @keys = nil
      end
    end
  end
end
