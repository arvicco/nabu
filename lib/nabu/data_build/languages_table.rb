# frozen_string_literal: true

require_relative "csv_writer"
require_relative "builder"

module Nabu
  module DataBuild
    # Every dataset ships languages.csv (CLDF LanguageTable nomenclature):
    # ID is Nabu's language code; Name/Glottocode/ISO639P3code come from the
    # feature's static Language declaration (registry.rb — verified against
    # the Glottolog cone when minted, never looked up at build time).
    class LanguagesTable
      FILENAME = "languages.csv"
      COLUMNS = %w[ID Name Glottocode ISO639P3code].freeze

      # Write languages.csv for +languages+ (Language values) into +dir+.
      # Returns the row count.
      def self.write(dir:, languages:)
        rows = languages.map do |language|
          { "ID" => language.id, "Name" => language.name,
            "Glottocode" => language.glottocode, "ISO639P3code" => language.iso639p3 }
        end
        CsvWriter.write(path: File.join(dir, FILENAME), columns: COLUMNS, rows: rows)
      end

      # The manifest resource entry for the table just written.
      def self.resource(count:)
        Resource.new(
          name: "languages", path: FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end
    end
  end
end
