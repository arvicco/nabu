# frozen_string_literal: true

require "csv"

module Nabu
  module Adapters
    # The flat-csv parser family (P29-0): ONE headered CSV artifact, one
    # domain record per CSV record — the OpenEtruscan corpus dump and the
    # Larth ETP_POS glossary shape (quoted fields may carry commas and
    # newlines; stdlib CSV streams records, so a multi-line inscription
    # stays one row). Deliberately thin: the family owns streaming, header
    # validation and the malformed-CSV error contract; what a row MEANS
    # (document vs dictionary entry) stays in each adapter.
    #
    # - +required_headers+: column names the adapter's row-reading depends
    #   on. Validated against the file's actual header on the first read —
    #   a silently renamed upstream column must fail loudly (naming the
    #   missing columns and the file), never yield nil-filled rows.
    # - #each_row streams string-keyed hashes in file order (CSV::Row
    #   converted; values are Strings or nil, exactly as stdlib CSV parses
    #   them). Malformed CSV raises Nabu::ParseError naming file and line.
    class FlatCsvParser
      def initialize(required_headers: [])
        @required_headers = required_headers
      end

      # Stream +path+'s records as string-keyed hashes, in file order.
      # Returns an Enumerator without a block. An UNNAMED leading column
      # (pandas index dumps: ",Etruscan,…" — stdlib CSV parses the empty
      # header cell as nil) keys as "" so every key stays a String.
      def each_row(path, &block)
        return enum_for(:each_row, path) unless block

        checked = false
        CSV.foreach(path, headers: true, encoding: Encoding::UTF_8) do |row|
          hash = row.to_h.transform_keys { |key| key.nil? ? "" : key }
          unless checked
            check_headers!(hash.keys, path)
            checked = true
          end
          yield hash
        end
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "flat-csv: malformed CSV in #{path}: #{e.message}"
      end

      private

      def check_headers!(headers, path)
        missing = @required_headers - headers
        return if missing.empty?

        raise Nabu::ParseError,
              "flat-csv: #{path} is missing required column(s) #{missing.join(', ')} " \
              "(upstream header changed?)"
      end
    end
  end
end
