# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/char-postings builder (P73-8 + the Edubba P-1 rider) — the
    # Han character × source doc-frequency census, published. One row per
    # (character, source): how many documents of that corpus attest the
    # character, with the row's language riding in-band (the census spans
    # lzh/jpn/otb/ojp corpora — hence the mul/ slug, settled in-packet
    # from the survey's "naming TBD"). IDs are codepoint-minted
    # (kanripo-U984F) — a Han character itself can never be a CLDF
    # identifier.
    #
    # The Edubba P-1 rider (char/sign frequency datasets any school can
    # consume) is satisfied in two halves: this dataset is the character
    # half (the kanripo/aozora lanes Edubba's survey called Tier-1); the
    # cuneiform sign half ships as sux/sign-table's attestation counts
    # (P73-9). Circularity guard: Edubba's own frequency TSVs are NEVER
    # an input here — the census derives from Nabu's ingested corpora
    # only.
    #
    # License (owner ruling №R-24): CC BY-SA 4.0 — the kanripo lane's
    # share-alike grant. Only open/attribution sources publish; the nc
    # slices (cbeta, ud, e84000, openiti) are excluded row-by-row and
    # censused in nabu.eval — character frequencies are fact-like, but
    # the repo's no-nc-derivation policy sentence settles it.
    class CharPostingsBuilder
      FILENAME = "char-postings.csv"
      COLUMNS = %w[ID Char Language_ID Count Source].freeze

      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      OVERVIEW =
        "Which Han characters actually occur in premodern East Asian corpora, and how widely? " \
        "This dataset publishes Nabu's precomputed census: for each character and each corpus, " \
        "the number of documents attesting it — across Classical Chinese, Japanese, Old " \
        "Tibetan and Old Japanese collections. Teaching tools can grade reading material by " \
        "real attestation instead of modern frequency lists; NLP pipelines get historical " \
        "out-of-vocabulary planning; font projects get honest subsetting data."

      def initialize(fulltext: nil, registry: nil)
        @fulltext = fulltext
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/char-postings needs the catalog open — license classes live there" if catalog.nil?

        fulltext = @fulltext || open_fulltext
        rows, census, published_slugs, digest = published_rows(fulltext, catalog)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          citations: citations(published_slugs),
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def open_fulltext
        path = Nabu::Config.load.fulltext_path
        raise Error, "no fulltext index at #{path} — run `nabu rebuild` (the index stage) first" unless
          File.exist?(path)

        Nabu::Store.connect_fulltext(path, readonly: true)
      end

      def published_rows(fulltext, catalog)
        sources = catalog[:sources].select_hash(:id, %i[slug license_class])
        state = { rows: [], excluded: Hash.new(0), slugs: {}, chars: {}, total: 0,
                  sha: Digest::SHA256.new }
        ordered_postings(fulltext).each do |row|
          state[:total] += 1
          slug, license_class = sources[row[:source_id]]
          unless PUBLISHABLE_LICENSE_CLASSES.include?(license_class)
            state[:excluded][license_class] += 1
            next
          end

          publish(state, row, slug)
        end
        census = { "postings_rows" => state[:total], "published_rows" => state[:rows].size,
                   "excluded_rows" => state[:excluded].sort_by { |reason, _| reason.to_s }.to_h,
                   "distinct_chars" => state[:chars].size }
        [state[:rows], census, state[:slugs].keys.sort, state[:sha].hexdigest]
      end

      # Deterministic export order: by source id then codepoint. The table
      # is small (~62K rows) — sorted in memory.
      def ordered_postings(fulltext)
        fulltext[:char_postings].all.sort_by { |row| [row[:source_id], row[:char].ord] }
      end

      def publish(state, row, slug)
        state[:slugs][slug] = true
        state[:chars][row[:char]] = true
        state[:sha] << [slug, row[:char], row[:language], row[:docs]].join("\x1f") << "\n"
        state[:rows] << { "ID" => "#{slug}-U#{format('%04X', row[:char].ord)}",
                          "Char" => row[:char], "Language_ID" => row[:language],
                          "Count" => row[:docs], "Source" => slug }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: name == "Count" ? "integer" : "string" } }
        Resource.new(name: "char_postings", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "char-postings v1: project the fulltext char_postings census at (source, character) " \
          "grain, license classes #{PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered " \
          "(source, codepoint); published-slice sha256=#{digest}"
      end

      def citations(published_slugs)
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        published_slugs.filter_map do |slug|
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
