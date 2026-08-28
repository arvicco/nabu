# frozen_string_literal: true

require "csv"

module Nabu
  # The READ seam over the mul/language-dossiers overlay (P85-A) — the curated
  # language layer Nabu itself PUBLISHES to nabu-data (LanguageDossiersBuilder)
  # and re-consumes here, the two-way loop the FormLemma/VerbLemma seams already
  # walk: `nabu data build` derives the ValueTable from the local dossiers, the
  # owner publishes it, and `nabu sync nabu-data` lands it under
  # canonical/nabu-data/ where this resolver reads it. No catalog table, no
  # migration: nabu-data is a feature module (kind: module) — absent file =
  # overlay off, byte-identical (the CldfSpine/Lila posture).
  #
  # == The dataset (grounded in the published bytes)
  #
  # language-dossiers.csv is a CLDF ValueTable: ID, Language_ID, Parameter_ID,
  # Value — one row per (language code, curated attribute). This seam groups
  # the rows by Language_ID into one Dossier per code: the named lanes (name,
  # family, context, provenance) map to fields; every other Parameter_ID is an
  # extra lane (period, scripts…), mirroring the dossier's own front-matter
  # extras. The consumer (the language card) composes this overlay beneath the
  # instance's local curation and above the canonical reference.
  class LanguageDossiers
    DATASET_FILE = File.join("mul", "language-dossiers", "language-dossiers.csv")
    SLUG = "nabu-data"

    # The named lanes with dedicated fields; any other Parameter_ID → extras.
    NAMED_LANES = %w[name family context provenance].freeze

    # One language's curated overlay layer. +extras+ holds the non-named lanes
    # (period, scripts…) in file order; absent lanes are nil / empty.
    Dossier = Data.define(:code, :name, :family, :context, :provenance, :extras)

    # Build a resolver from a canonical/nabu-data-shaped directory. A missing
    # dataset file loads empty (a partial tree stays honest).
    def self.load(dir)
      new(index: build_index(File.join(dir, DATASET_FILE)))
    end

    # Feature-detect the overlay from the owner's canonical tree: nil when
    # `nabu sync nabu-data` has not landed it, so a corpus without the overlay
    # behaves byte-identically (the FormLemma posture).
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, SLUG)
      File.file?(File.join(dir, DATASET_FILE)) ? load(dir) : nil
    end

    # code => { "name" => …, "family" => …, extras… } in file order.
    def self.build_index(csv_path)
      return {} unless File.file?(csv_path)

      index = {}
      CSV.foreach(csv_path, headers: true, encoding: Encoding::UTF_8) do |row|
        (index[row["Language_ID"]] ||= {})[row["Parameter_ID"]] = row["Value"]
      end
      index
    end

    def initialize(index:)
      @index = index
    end

    # The curated overlay for +code+, or nil when the overlay carries none.
    def dossier(code)
      lanes = @index[code.to_s] or return nil

      Dossier.new(
        code: code.to_s, name: lanes["name"], family: lanes["family"],
        context: lanes["context"], provenance: lanes["provenance"],
        extras: lanes.except(*NAMED_LANES)
      )
    end

    # How many distinct language codes the overlay carries.
    def size = @index.size
  end
end
