# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../script_dossiers"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/script-dossiers builder (P86-4c, №R-49) — the curated
    # per-script context layer, published. The wylie-fold pattern, not the
    # language-dossiers one: the source of truth is a CONFIG fact file
    # (config/script_dossiers.yml, git-shared, present in every install), so
    # the card never depends on this dataset — the publication is the
    # public, citable mirror of the same curation.
    #
    # == Shape — the language-dossiers tidy ValueTable, script-keyed
    #
    # script-dossiers.csv: ID, Script_Tag, Parameter_ID, Value. One row per
    # (registry script tag, attribute): name | context | desk. The desk lane
    # (how the originating library's shelves hold the script) is absent
    # where nothing shelf-specific applies — binding honesty, no "—".
    #
    # == License
    #
    # CC BY 4.0 — own authorship throughout (no Wikipedia-derived prose, the
    # suite-guarded difference from language-dossiers' BY-SA inheritance).
    class ScriptDossiersBuilder
      FILENAME = "script-dossiers.csv"
      COLUMNS = %w[ID Script_Tag Parameter_ID Value].freeze
      PARAMETERS = %w[name context desk].freeze

      OVERVIEW =
        "What is this writing system, and how does a working research library actually hold " \
        "it? One curated dossier per script in the registry's global scripts table — a " \
        "human-written context paragraph (what the script is, when and how it ran) and, where " \
        "it applies, the desk conventions the originating library uses (transliteration " \
        "surfaces, fold tables, honest gaps). Each row is one attribute of one script, keyed " \
        "by its lowercased ISO 15924 tag. Own authorship throughout (CC BY 4.0); the source " \
        "of truth is the library's config/script_dossiers.yml, of which this dataset is the " \
        "public mirror."

      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        rows, digest, desk_count = collect_rows
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          evaluation: { "scripts" => Nabu::ScriptDossiers.table.size,
                        "desk_bearing" => desk_count },
          overview: OVERVIEW
        )
      end

      private

      def collect_rows
        rows = []
        sha = Digest::SHA256.new
        desk_count = 0
        Nabu::ScriptDossiers.table.keys.sort.each do |tag|
          dossier = Nabu::ScriptDossiers.lookup(tag)
          desk_count += 1 if dossier.desk
          { "name" => dossier.name, "context" => dossier.context,
            "desk" => dossier.desk }.each do |parameter, value|
            text = value.to_s.strip
            next if text.empty?

            rows << { "ID" => CsvWriter.mint_id(tag, parameter),
                      "Script_Tag" => tag, "Parameter_ID" => parameter, "Value" => text }
            sha << [tag, parameter, text].join("\x1f") << "\n"
          end
        end
        [rows, sha.hexdigest, desk_count]
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: "string" } }
        Resource.new(name: "script_dossiers", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "script-dossiers v1: publish the curated per-script dossiers (name, context, desk " \
          "conventions) from config/script_dossiers.yml, one tidy row per (tag, attribute), " \
          "tag order; the registry drift guard pins tags == the nabu-lects scripts table; " \
          "published-slice sha256=#{digest}"
      end
    end
  end
end
