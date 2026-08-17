# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The egy/hiero-frequency builder (P77-r17, the sign-learning survey's
    # P-1 Egyptian half — "the first public hieroglyph frequency list
    # anywhere"): Gardiner-code frequencies censused from the AES corpus's
    # per-word `hiero_inventar` annotations (TLA gold lemmatization ships
    # each word form's sign spelling), overall AND per subcorpus (Pyramid
    # Texts vs Amarna letters vs medical papyri… — frequency is
    # genre-dependent, the survey's own point). One row per
    # (Gardiner code, subcorpus) plus an `all` roll-up row per code:
    # token occurrences and attesting-document counts, at the same
    # long-format grain as mul/char-postings. Join spine: the Gardiner
    # column keys against egy/unikemet-signs.
    #
    # License: CC BY-SA 4.0 — derived from AES (CC BY-SA 4.0, class
    # `attribution`), riding the №R-24/D51-a share-alike carve-out exactly
    # like mul/char-postings' kanripo lane. The builder refuses to publish
    # if the aes row's license class is not in the publishable set.
    class HieroFrequencyBuilder
      FILENAME = "hiero-frequency.csv"
      COLUMNS = %w[ID Gardiner Subcorpus Tokens Docs Source].freeze

      SOURCE_SLUG = "aes"
      ALL = "all"
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      # The hiero_card precedent: the sign spellings are extracted from
      # annotations_json by scan, never a full JSON parse per passage.
      INVENTAR = /"hiero_inventar":\s*"([^"]*)"/

      OVERVIEW =
        "How often does each Egyptian hieroglyph actually occur in real texts — and in which " \
        "genres? This dataset censuses Gardiner-code frequencies from the Ancient Egyptian " \
        "Sentences corpus (TLA gold annotation): for every sign, its token occurrences and " \
        "attesting document counts, overall and per subcorpus (Pyramid Texts, Amarna letters, " \
        "medical papyri…). Sign-learning curricula can order signs by real attestation instead " \
        "of list order; join to egy/unikemet-signs by the Gardiner column for identities."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "egy/hiero-frequency needs the catalog open" if catalog.nil?

        source = aes_source!(catalog)
        tallies, census, digest = census_documents(catalog, source[:id])
        rows = frequency_rows(tallies)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          citations: [citation],
          evaluation: census,
          overview: OVERVIEW
        )
      end

      private

      def aes_source!(catalog)
        source = catalog[:sources].where(slug: SOURCE_SLUG).select(:id, :license_class).first
        raise Error, "egy/hiero-frequency: the #{SOURCE_SLUG} source is not in the catalog" if source.nil?
        unless PUBLISHABLE_LICENSE_CLASSES.include?(source[:license_class])
          raise Error, "egy/hiero-frequency: #{SOURCE_SLUG} license class " \
                       "#{source[:license_class].inspect} is not publishable " \
                       "(#{PUBLISHABLE_LICENSE_CLASSES.join('/')})"
        end

        source
      end

      # Stream the LIVE aes documents; per document, read its subcorpus
      # (document metadata) once and scan its live passages' annotations
      # for sign spellings. tallies[code][subcorpus] = {tokens:, docs:}.
      def census_documents(catalog, source_id)
        tallies = Hash.new { |h, code| h[code] = Hash.new { |g, sub| g[sub] = { tokens: 0, docs: 0 } } }
        census = { "documents_scanned" => 0, "documents_with_signs" => 0, "tokens_counted" => 0 }
        sha = Digest::SHA256.new
        live_documents(catalog, source_id).each do |doc|
          census["documents_scanned"] += 1
          subcorpus = subcorpus_of(doc)
          doc_codes = scan_document(catalog, doc[:id], subcorpus, tallies, census)
          next if doc_codes.empty?

          census["documents_with_signs"] += 1
          doc_codes.sort.each do |code|
            tallies[code][subcorpus][:docs] += 1
            tallies[code][ALL][:docs] += 1
            sha << [code, subcorpus, doc[:id]].join("\x1f") << "\n"
          end
        end
        [tallies, census, sha.hexdigest]
      end

      def live_documents(catalog, source_id)
        catalog[:documents].where(source_id: source_id, withdrawn: false)
                           .select(:id, :metadata_json).order(:id)
      end

      def subcorpus_of(doc)
        doc[:metadata_json].to_s[/"subcorpus":\s*"([^"]*)"/, 1] || "unknown"
      end

      def scan_document(catalog, document_id, subcorpus, tallies, census)
        codes = Set.new
        catalog[:passages].where(document_id: document_id, withdrawn: false)
                          .select_map(:annotations_json).each do |json|
          json.to_s.scan(INVENTAR) do |(spelling)|
            spelling.split(";").each do |code|
              code = code.strip
              next if code.empty?

              census["tokens_counted"] += 1
              tallies[code][subcorpus][:tokens] += 1
              tallies[code][ALL][:tokens] += 1
              codes << code
            end
          end
        end
        codes
      end

      # Deterministic order: Gardiner code, then `all` first, then
      # subcorpora alphabetically.
      def frequency_rows(tallies)
        tallies.keys.sort.flat_map do |code|
          subs = tallies[code]
          ([ALL] + (subs.keys - [ALL]).sort).map do |sub|
            { "ID" => "#{code}-#{sub}", "Gardiner" => code, "Subcorpus" => sub,
              "Tokens" => subs[sub][:tokens], "Docs" => subs[sub][:docs], "Source" => SOURCE_SLUG }
          end
        end
      end

      def resource(count)
        fields = COLUMNS.map do |name|
          { name: name, type: %w[Tokens Docs].include?(name) ? "integer" : "string" }
        end
        Resource.new(name: "hiero_frequency", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "hiero-frequency v1: census Gardiner codes from aes hiero_inventar annotations at " \
          "(code, subcorpus) grain, token + attesting-doc counts, `all` roll-up per code, " \
          "live rows only; doc-attestation sha256=#{digest}"
      end

      def citation
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        entry = registry[SOURCE_SLUG]
        manifest = entry&.manifest
        return Citation.new(key: SOURCE_SLUG, type: "misc", fields: { "title" => "AES" }) if manifest.nil?

        Citation.new(key: SOURCE_SLUG, type: "misc",
                     fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                               "note" => "license: #{manifest.license}" })
      end
    end
  end
end
