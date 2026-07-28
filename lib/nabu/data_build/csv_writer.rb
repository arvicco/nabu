# frozen_string_literal: true

require "csv"

require_relative "../errors"

module Nabu
  module DataBuild
    # CLDF-compatible CSV emission (P50-W1) — the nomenclature enforcement
    # point for every table a dataset ships. House rules (owner-approved,
    # from the CLDF spec; the full contract is docs/nabu-data.md):
    #
    # - Column names use CLDF's exact Title_Snake spellings where a CLDF term
    #   exists (CLDF_COLUMNS below); Nabu extension columns are the four in
    #   NABU_COLUMNS, spelled consistently across datasets.
    # - ID is ALWAYS the first column, and every ID value matches the CLDF
    #   identifier regex (ID_PATTERN). A URN is NEVER an ID — colons are
    #   illegal there; mint one with .mint_id instead and keep the URN in a
    #   URN column.
    # - Violations RAISE (Nabu::ValidationError) rather than publish a
    #   malformed table: the rail's output is public data.
    class CsvWriter
      # The CLDF identifier regex, verbatim.
      ID_PATTERN = /\A[a-zA-Z0-9\-_]+\z/

      # CLDF terms the datasets reuse, in the spec's exact spellings.
      CLDF_COLUMNS = %w[
        ID Language_ID Form Segments Parameter_ID Value Headword Part_Of_Speech
        Entry_ID Description Primary_Text Position Comment Source
      ].freeze

      # Nabu extension columns, spelled consistently across all datasets.
      NABU_COLUMNS = %w[URN Passage_SHA256 Tier Count].freeze

      class << self
        # Deterministic ID minter: components joined with "-", every run of
        # characters outside the CLDF identifier class (colons, dots, spaces,
        # non-ASCII, ...) folded to a single "-", leading/trailing hyphens
        # trimmed. Idempotent on its own output; raises when nothing
        # identifier-worthy survives (the caller has no honest ID to mint).
        def mint_id(*components)
          id = components.join("-")
                         .gsub(/[^a-zA-Z0-9\-_]+/, "-")
                         .squeeze("-")
                         .gsub(/\A-+|-+\z/, "")
          raise Nabu::ValidationError, "mint_id: nothing identifier-worthy in #{components.inspect}" if id.empty?

          id
        end

        # Write +rows+ (hashes keyed by column name) to +path+ under
        # +columns+ (first MUST be "ID"). Cells are emitted in column order
        # regardless of hash key order; a missing key is an empty cell; an
        # unknown key raises (it is a typo, not data). Returns the row count.
        def write(path:, columns:, rows:)
          validate_columns!(columns)
          seen = {}
          CSV.open(path, "w", encoding: Encoding::UTF_8) do |csv|
            csv << columns
            rows.each do |row|
              validate_row!(row, columns: columns, seen: seen)
              csv << columns.map { |name| row[name] }
            end
          end
          rows.size
        end

        private

        def validate_columns!(columns)
          raise Nabu::ValidationError, "CSV columns must not be empty" if columns.empty?
          unless columns.first == "ID"
            raise Nabu::ValidationError, "ID must be the first column (CLDF house rule), " \
                                         "got #{columns.first.inspect}"
          end
          return if columns.uniq.size == columns.size

          raise Nabu::ValidationError, "duplicate column names in #{columns.inspect}"
        end

        def validate_row!(row, columns:, seen:)
          unknown = row.keys - columns
          unless unknown.empty?
            raise Nabu::ValidationError, "row carries keys outside the declared columns: #{unknown.inspect}"
          end

          id = row["ID"].to_s
          unless id.match?(ID_PATTERN)
            raise Nabu::ValidationError, "illegal CLDF identifier #{id.inspect} — IDs match " \
                                         "#{ID_PATTERN.inspect}; a URN is never an ID (mint one " \
                                         "with CsvWriter.mint_id and keep the URN in a URN column)"
          end
          raise Nabu::ValidationError, "duplicate ID #{id.inspect}" if seen.key?(id)

          seen[id] = true
        end
      end
    end
  end
end
