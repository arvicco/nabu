# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../language_shelf"
require_relative "../language_dossier"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/language-dossiers builder (P85-A, №R-47/48) — the curated
    # language dossiers, PUBLISHED so a fresh install gets the same
    # hand-written context the originating curator wrote instead of a bare
    # language code. The overlay layer of the composition model: canonical
    # reference + corpus holdings + THIS curated overlay + private notes.
    #
    # == What travels, and what deliberately does not
    #
    # A dossier (local/shelves/local-language/<code>.md) carries a curated
    # front-matter/prose layer (name, family, a context paragraph, extra
    # scalar lanes) AND section accretions derived from other sources (iecor
    # varieties, corpus witnesses, the lect stage ladder). ONLY the curated,
    # non-derivable layer is published here: every install rebuilds the
    # section accretions from its OWN synced sources (iecor, its corpus,
    # nabu-lects), so republishing them would be circular tier-laundering.
    # The overlay is exactly the layer a fresh install cannot reconstruct.
    #
    # == Shape — a CLDF ValueTable (tidy, one attribute per row)
    #
    # language-dossiers.csv: ID, Language_ID, Parameter_ID, Value. One row per
    # (code, attribute): the Nabu language code in Language_ID, the attribute
    # name (name | family | context | <extra> | provenance) in Parameter_ID,
    # the curated text in Value. Tidy — not wide — because the curated lanes
    # differ per language (a heavy dossier has period/scripts extras a stub
    # lacks) and CLDF's column vocabulary has no Name/Family term; the tidy
    # form uses only CLDF terms and stays open to new lanes without a schema
    # change. The consumer groups by Language_ID.
    #
    # == License (№R-48, 2026-08-28)
    #
    # CC BY-SA 4.0 for the whole dataset: ~71% of the context prose is
    # Wikipedia-derived (share-alike), so the whole set inherits it rather
    # than splitting per-dossier. The per-dossier provenance rides as its own
    # Parameter_ID row, and the Wikipedia-derived share is censused in
    # nabu.eval. Personal per-language notes are NOT here — they ride the
    # private `nabu note` layer (local/, never published), composed onto the
    # card beneath this universal overlay.
    #
    # == Provenance
    #
    # The local dossier files are the source of truth (own authorship — no
    # canonical corpus cone); the recipe embeds the published-slice sha256, so
    # an unchanged dossier corpus is a fingerprint no-op.
    class LanguageDossiersBuilder
      FILENAME = "language-dossiers.csv"
      COLUMNS = %w[ID Language_ID Parameter_ID Value].freeze

      # The curated lanes published, in row order. Sections are excluded by
      # construction (they are never emitted here).
      CURATED_PARAMETERS = %w[name family context].freeze

      OVERVIEW =
        "What does Nabu actually know about each of its languages — the language's name, where " \
        "it sits in its family, and a paragraph of human-written context? This dataset publishes " \
        "those curated language dossiers, so a freshly installed Nabu shows the same context the " \
        "original curator wrote rather than a bare code. Each row is one attribute (name, family, " \
        "a context paragraph, or its provenance) of one language, cited by its Nabu language " \
        "code. Much of the context prose is adapted from Wikipedia, which is why the whole " \
        "dataset is share-alike (CC BY-SA 4.0); each dossier's provenance travels beside it."

      def initialize(dir: nil)
        @dossier_dir = dir
      end

      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        rows, census, digest = collect_rows
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def dossier_dir
        @dossier_dir ||= Nabu::LanguageShelf.dir(Nabu::Config.load)
      end

      # Every dossier, in code order; one ValueTable row per curated attribute
      # that carries content (absent lanes stay absent — binding honesty).
      def collect_rows
        rows = []
        state = { scanned: 0, published: 0, wikipedia: 0, by_parameter: Hash.new(0),
                  sha: Digest::SHA256.new }
        codes.each do |code|
          dossier = Nabu::LanguageDossier.parse(File.read(dossier_path(code), encoding: "UTF-8"),
                                                code: code)
          state[:scanned] += 1
          emitted = emit_dossier(dossier, rows, state)
          state[:published] += 1 if emitted.positive?
          state[:wikipedia] += 1 if emitted.positive? && wikipedia_derived?(dossier)
        end
        [rows, census(state), state[:sha].hexdigest]
      end

      def emit_dossier(dossier, rows, state)
        emitted = 0
        attributes(dossier).each do |parameter, value|
          text = value.to_s.strip
          next if text.empty?

          rows << { "ID" => CsvWriter.mint_id(dossier.code, parameter),
                    "Language_ID" => dossier.code, "Parameter_ID" => parameter, "Value" => text }
          state[:by_parameter][parameter] += 1
          state[:sha] << [dossier.code, parameter, text].join("\x1f") << "\n"
          emitted += 1
        end
        emitted
      end

      # The curated attributes in deterministic order: name, family, context,
      # then extra scalar lanes (period, scripts…) sorted, then provenance.
      def attributes(dossier)
        pairs = [["name", dossier.name], ["family", dossier.family], ["context", dossier.context]]
        dossier.extras.sort.each { |key, value| pairs << [key, value] }
        pairs << ["provenance", provenance_text(dossier.provenance)] if dossier.provenance
        pairs
      end

      def provenance_text(provenance)
        case provenance
        when Hash then provenance.map { |key, value| "#{key}: #{value}" }.join("; ")
        else provenance.to_s
        end
      end

      # A dossier whose curated prose is Wikipedia-derived — the share-alike
      # majority (№R-48). Detected from the provenance block and context prose.
      def wikipedia_derived?(dossier)
        haystack = [provenance_text(dossier.provenance), dossier.context].join(" ")
        haystack.match?(/wikipedia/i)
      end

      def codes
        Dir.glob(File.join(dossier_dir, "*.md")).map { |path| File.basename(path, ".md") }.sort
      end

      def dossier_path(code) = File.join(dossier_dir, "#{code}.md")

      def census(state)
        { "dossiers_scanned" => state[:scanned], "dossiers_published" => state[:published],
          "published_rows" => state[:by_parameter].values.sum,
          "rows_by_parameter" => state[:by_parameter].sort.to_h,
          "wikipedia_derived_dossiers" => state[:wikipedia] }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: "string" } }
        Resource.new(name: "language_dossiers", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "language-dossiers v1: publish the curated dossier layer (name, family, context, extra " \
          "lanes, provenance) from local/shelves/local-language, one CLDF ValueTable row per " \
          "(code, attribute), code order; section accretions (iecor/witness/lect-ladder) excluded " \
          "as per-install derivable; published-slice sha256=#{digest}"
      end
    end
  end
end
