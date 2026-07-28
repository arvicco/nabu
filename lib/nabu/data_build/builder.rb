# frozen_string_literal: true

require_relative "../errors"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # == The builder contract (P50-W1)
    #
    # A feature's builder is a plain class instantiated with no arguments and
    # driven through ONE method:
    #
    #   #build(catalog:, out_dir:) -> BuildResult
    #
    # catalog:  an open read-only Sequel handle on catalog.sqlite3, or nil on
    #           a box with no catalog — a builder that needs one raises
    #           Nabu::DataBuild::Error with a message naming the missing input.
    # out_dir:  the dataset directory (already created). The builder writes
    #           its OWN data files there — CSVs through CsvWriter (the CLDF
    #           nomenclature enforcement point), non-tabular projections
    #           directly — and must NOT write datapackage.json, languages.csv,
    #           sources.bib, or README.md: those belong to the Runner.
    #
    # Builders are read-only on canonical/ and on the catalog: a build derives
    # and writes into the nabu-data clone, never back into Nabu's stores.

    # One file the builder wrote, as the manifest will describe it.
    # Tabular resources carry +fields+ ([{ name:, type: }, ...] in column
    # order) and optionally +primary_key+; non-tabular ones leave fields nil
    # and say what they are via +format+/+mediatype+. +rows+ is the data row
    # count (nil when rows are not the honest unit, e.g. a .bib).
    Resource = Data.define(:name, :path, :rows, :fields, :primary_key, :format, :mediatype) do
      def initialize(name:, path:, rows: nil, fields: nil, primary_key: nil, format: nil, mediatype: nil)
        super
      end

      def tabular? = !fields.nil?
    end

    # One structured citation for sources.bib. +key+ is the BibTeX key —
    # citable from CSV Source columns (";"-separated), so it obeys the CLDF
    # identifier regex. +fields+ is an ordered { "title" => ..., ... } hash,
    # emitted verbatim in the given order.
    Citation = Data.define(:key, :type, :fields) do
      def initialize(key:, fields:, type: "misc")
        unless key.to_s.match?(CsvWriter::ID_PATTERN)
          raise Nabu::ValidationError, "citation key #{key.inspect} must match " \
                                       "#{CsvWriter::ID_PATTERN.inspect} (it is cited from CSV Source columns)"
        end
        super
      end
    end

    # What #build returns: the resources written (manifest order), the
    # recipe string (a short honest description of the derivation — part of
    # the fingerprint, so changing the derivation MUST change it), the
    # citations for sources.bib, and optional free-text notes the Runner
    # appends to the dataset README.
    BuildResult = Data.define(:resources, :recipe, :citations, :notes) do
      def initialize(resources:, recipe:, citations: [], notes: nil)
        raise Nabu::ValidationError, "a build result needs at least one resource" if resources.empty?
        raise Nabu::ValidationError, "a build result needs a non-empty recipe string" if recipe.to_s.strip.empty?

        super
      end
    end
  end
end
