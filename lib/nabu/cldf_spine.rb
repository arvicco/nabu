# frozen_string_literal: true

require "csv"

module Nabu
  # The CLDF reference spine (P46-6): a pure READ seam over the two thin
  # reference files the comparativist shelves cite into — Concepticon
  # concept ids (WOLD parameters, CLICS³ nodes) and Glottolog languoid ids
  # (WOLD donor glottocodes, language rows across the lexibank ecosystem) —
  # the way Nabu::Pleiades serves place ids and Nabu::Lila serves Latin
  # lemmas. There is NO catalog table and NO migration: cldf-spine is a
  # feature module (kind: module) whose canonical assets are two files
  # landed by `nabu sync cldf-spine` under canonical/cldf-spine/:
  #
  #   concepticon/concepticon.tsv  the Concepticon concept list (v3.4.0:
  #                                4,033 rows; ID / GLOSS / SEMANTICFIELD /
  #                                DEFINITION / ONTOLOGICAL_CATEGORY /
  #                                REPLACEMENT_ID — a retired concept points
  #                                at its successor, reported verbatim and
  #                                never followed silently)
  #   glottolog/languages.csv      the Glottolog-CLDF languoid table (v5.3:
  #                                27,177 rows; glottocode / Name / ISO 639-3
  #                                / Level language|family|dialect /
  #                                Family_ID — one hop to the family row is
  #                                the classification this spine serves)
  #
  # THIN is the design bar (the packet spec): the id-and-name spine plus
  # what WOLD/CLICS rows need to resolve — never the full datasets (no
  # concept relations graph, no Glottolog refs/sources, no tree walk beyond
  # the Family_ID hop). Both files are plain-parseable with stdlib CSV; a
  # missing side loads empty so a partial sync stays honest.
  class CldfSpine
    # One Concepticon concept. +replacement_id+ is non-nil on retired
    # concepts (the upstream REPLACEMENT_ID pointer, verbatim).
    Concept = Data.define(:id, :gloss, :semantic_field, :definition, :category, :replacement_id)

    # One Glottolog languoid. +family_id+ is nil on family rows and
    # isolates; +iso+ is nil when Glottolog carries no ISO 639-3 code.
    Languoid = Data.define(:id, :name, :iso, :level, :family_id)

    CONCEPTICON_FILE = File.join("concepticon", "concepticon.tsv")
    GLOTTOLOG_FILE = File.join("glottolog", "languages.csv")
    SLUG = "cldf-spine"

    # Build a spine from a canonical/cldf-spine-shaped directory. Either
    # file may be absent (that side loads empty).
    def self.load(dir)
      new(
        concepts: read_concepticon(File.join(dir, CONCEPTICON_FILE)),
        languoids: read_glottolog(File.join(dir, GLOTTOLOG_FILE))
      )
    end

    # Feature-detect the spine from the owner's canonical tree: nil when
    # `nabu sync cldf-spine` has not landed either file, so a corpus
    # without the spine behaves byte-identically (the lila posture).
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, SLUG)
      present = [CONCEPTICON_FILE, GLOTTOLOG_FILE].any? { |rel| File.file?(File.join(dir, rel)) }
      present ? load(dir) : nil
    end

    # concepticon.tsv is tab-separated with no quoting (definitions carry
    # commas and quotes but never tabs) — a line split reads it whole.
    def self.read_concepticon(path)
      return {} unless File.file?(path)

      lines = File.read(path, encoding: Encoding::UTF_8).split("\n")
      header = lines.shift.to_s.split("\t")
      column = header.each_with_index.to_h
      lines.to_h do |line|
        cells = line.split("\t")
        at = ->(name) { presence(cells[column.fetch(name)]) }
        id = cells[column.fetch("ID")]
        [id, Concept.new(id: id, gloss: at.call("GLOSS"), semantic_field: at.call("SEMANTICFIELD"),
                         definition: at.call("DEFINITION"), category: at.call("ONTOLOGICAL_CATEGORY"),
                         replacement_id: at.call("REPLACEMENT_ID"))]
      end
    end

    def self.read_glottolog(path)
      return {} unless File.file?(path)

      CSV.read(path, headers: true, encoding: Encoding::UTF_8).to_h do |row|
        [row.fetch("ID"), Languoid.new(
          id: row.fetch("ID"), name: row["Name"], iso: presence(row["ISO639P3code"]),
          level: presence(row["Level"]), family_id: presence(row["Family_ID"])
        )]
      end
    end

    def self.presence(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
    private_class_method :presence

    def initialize(concepts:, languoids:)
      @concepts = concepts
      @languoids = languoids
      @by_iso = languoids.each_value.select(&:iso).to_h { |languoid| [languoid.iso, languoid] }
    end

    # Concepticon id (String or Integer) -> Concept, nil when unknown.
    def concept(id)
      id.nil? ? nil : @concepts[id.to_s]
    end

    # Glottocode -> Languoid, nil when unknown.
    def languoid(glottocode)
      glottocode.nil? ? nil : @languoids[glottocode.to_s]
    end

    # ISO 639-3 code -> Languoid (Glottolog maps ISO codes one-to-one).
    def languoid_by_iso(iso)
      iso.nil? ? nil : @by_iso[iso.to_s]
    end

    # The one-hop classification this spine serves: a languoid's top-level
    # family row, nil for family rows and isolates.
    def family(glottocode)
      resolved = languoid(glottocode)
      resolved&.family_id && @languoids[resolved.family_id]
    end

    def concept_count = @concepts.size
    def languoid_count = @languoids.size
  end
end
