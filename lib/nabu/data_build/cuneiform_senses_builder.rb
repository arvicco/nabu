# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/cuneiform-senses builder (P102-3) — the BY-SA sense-lane
    # sidecar the P73 sign-table deliberately deferred so its core
    # could stay CC-BY (P73-9, sign-table survey §2.6). Wiktionary's
    # sense glosses for the cuneiform languages, republished VERBATIM
    # from the three kaikki shelves (wiktionary-sux · wiktionary-akk ·
    # wiktionary-hit): one row per sense — headword, language, POS
    # (split from the shelf's entry id), the gloss, and the entry URN
    # that anchors it back into the library. CC BY-SA 4.0, Wiktionary's
    # own license, carried whole; the CC-BY sign-table core stays
    # untouched beside it — exactly the sidecar design.
    #
    # Declared inputs WITH cones (unlike the catalog-projection mul/
    # datasets): the rows republish upstream shelf content, so the
    # stale-ingest guard is load-bearing here — a drifted kaikki
    # extract refuses to publish.
    class CuneiformSensesBuilder
      FILENAME = "cuneiform-senses.csv"
      COLUMNS = %w[ID Headword Language_ID Part_Of_Speech Description URN Source].freeze

      SHELVES = {
        "wiktionary-sux" => "sux",
        "wiktionary-akk" => "akk",
        "wiktionary-hit" => "hit"
      }.freeze

      OVERVIEW =
        "What do the words of the cuneiform world mean? This dataset republishes the sense " \
        "glosses of Wiktionary's Sumerian, Akkadian and Hittite lanes (via the kaikki.org " \
        "machine-readable extraction) as one uniform table: headword (cuneiform or " \
        "romanized), language, part of speech, and the verbatim gloss, each row anchored by " \
        "the library entry URN it was published from. The share-alike sidecar beside the " \
        "CC-BY sux/sign-table core: sign lists and attestation counts there, senses here."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/cuneiform-senses needs the catalog open — the shelves live there" if catalog.nil?

        rows, census, digest = published_rows(catalog)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          citations: citations,
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def published_rows(catalog)
        rows = []
        by_language = Hash.new(0)
        sha = Digest::SHA256.new
        each_entry(catalog) do |row|
          language = SHELVES.fetch(row[:slug])
          by_language[language] += 1
          pos = part_of_speech(row)
          sha << [row[:urn], row[:gloss]].join("\x1f") << "\n"
          rows << { "ID" => CsvWriter.mint_id(row[:urn]),
                    "Headword" => row[:headword], "Language_ID" => language,
                    "Part_Of_Speech" => pos, "Description" => row[:gloss],
                    "URN" => row[:urn], "Source" => row[:slug] }
        end
        [rows, { "rows_by_language" => by_language.sort.to_h }, sha.hexdigest]
      end

      def each_entry(catalog, &)
        catalog[:dictionary_entries]
          .join(:dictionaries, id: :dictionary_id)
          .where(Sequel[:dictionaries][:slug] => SHELVES.keys,
                 Sequel[:dictionary_entries][:withdrawn] => false)
          .select(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:urn],
                  Sequel[:dictionary_entries][:entry_id], Sequel[:dictionary_entries][:key_raw],
                  Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:gloss])
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:headword],
                 Sequel[:dictionary_entries][:id])
          .paged_each(&)
      end

      # The shelf's entry id is "<headword>:<pos>"; strip the headword
      # prefix (never split on ":" — a headword may carry one).
      def part_of_speech(row)
        return nil if row[:entry_id] == row[:key_raw]

        row[:entry_id].delete_prefix("#{row[:key_raw]}:")
      end

      def resource(count)
        Resource.new(name: "cuneiform_senses", path: FILENAME, rows: count,
                     fields: COLUMNS.map { |name| { name: name, type: "string" } },
                     primary_key: ["ID"])
      end

      def recipe(digest)
        "cuneiform-senses v1: republish the sense glosses of the #{SHELVES.keys.join(', ')} " \
          "shelves verbatim, one row per sense, ordered (shelf, headword, entry); " \
          "published-slice sha256=#{digest}"
      end

      def citations
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        SHELVES.keys.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}" })
        end
      end
    end
  end
end
