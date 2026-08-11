# frozen_string_literal: true

require_relative "../errors"
require_relative "../config"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The egy/unikemet-signs builder (P73-9 rider) — the Egyptian sign
    # spine: one row per Unikemet codepoint, verbatim from the Unicode
    # data file (Unikemet.txt): the Gardiner-style catalog code (kEH_Cat),
    # the original Hieroglyphica-era code (kEH_UniK), core/legacy status,
    # description, functions, sound values, and the JSesh/Hieroglyphica/
    # IFAO concordances every Egyptological tool joins on. A tag absent
    # upstream stays an empty cell — nothing is inferred.
    class UnikemetSignsBuilder
      FILENAME = "unikemet-signs.csv"
      COLUMNS = %w[ID Codepoint Glyph Gardiner UniK Core Description Functions Values
                   JSesh Hieroglyphica IFAO Source].freeze

      CONE = "unikemet"
      DATA_FILE = "Unikemet.txt"
      BIB_KEY = "unikemet"

      # Unikemet tag → output column; multi-occurrence tags join with ";".
      TAG_COLUMNS = {
        "kEH_Cat" => "Gardiner", "kEH_UniK" => "UniK", "kEH_Core" => "Core",
        "kEH_Desc" => "Description", "kEH_Func" => "Functions", "kEH_FVal" => "Values",
        "kEH_JSesh" => "JSesh", "kEH_HG" => "Hieroglyphica", "kEH_IFAO" => "IFAO"
      }.freeze

      OVERVIEW =
        "The complete Unicode inventory of Egyptian hieroglyphs as one reference table: for " \
        "each of the encoded signs, its Gardiner-style catalog code, what it depicts, how it " \
        "functions (logogram, phonogram, classifier), its sound values, and the concordance " \
        "codes the standard Egyptological tools (JSesh, Hieroglyphica, IFAO) use — the join " \
        "spine for any digital Egyptology pipeline, flattened verbatim from the Unicode " \
        "Unikemet data file."

      def initialize(canonical_dir: nil)
        @canonical_dir = canonical_dir
      end

      # The catalog is deliberately unused — unikemet is a feature module
      # (no catalog rows); the dataset is a pure flattening of the cone.
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        rows = parse(data_path).map { |codepoint, tags| sign_row(codepoint, tags) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: "unikemet-signs v1: flatten Unikemet.txt to one row per codepoint, tag " \
                  "values verbatim (multi-occurrence tags ;-joined), file order",
          citations: [citation],
          overview: OVERVIEW
        )
      end

      private

      def data_path
        dir = @canonical_dir || Nabu::Config.load.canonical_dir
        path = File.join(dir, CONE, DATA_FILE)
        return path if File.file?(path)

        raise Error, "canonical input #{CONE.inspect} has no #{DATA_FILE} under " \
                     "#{File.join(dir, CONE)} — run `nabu sync unikemet` first"
      end

      # [[codepoint, {tag => [values]}], ...] in file order.
      def parse(path)
        signs = Hash.new { |hash, key| hash[key] = Hash.new { |tags, tag| tags[tag] = [] } }
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          next if line.start_with?("#") || line.strip.empty?

          codepoint, tag, value = line.chomp.split("\t", 3)
          next if codepoint.nil? || tag.nil? || value.nil?

          signs[codepoint][tag] << value
        end
        signs.to_a
      end

      def sign_row(codepoint, tags)
        row = { "ID" => codepoint.delete("+"), "Codepoint" => codepoint,
                "Glyph" => [Integer(codepoint.delete_prefix("U+"), 16)].pack("U"),
                "Source" => BIB_KEY }
        TAG_COLUMNS.each do |tag, column|
          values = tags[tag]
          row[column] = values.join(";") unless values.empty?
        end
        row
      end

      def resource(count)
        Resource.new(name: "unikemet_signs", path: FILENAME, rows: count,
                     fields: COLUMNS.map { |name| { name: name, type: "string" } },
                     primary_key: ["ID"])
      end

      def citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "Unikemet — Unicode data references for Egyptian Hieroglyphs",
            "howpublished" => "https://www.unicode.org/Public/UCD/latest/ucd/Unikemet.txt",
            "note" => "Unicode License V3 (permissive); every column is a verbatim tag value"
          }
        )
      end
    end
  end
end
