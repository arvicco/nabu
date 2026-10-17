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
    # `attribution`), riding the D51-a share-alike carve-out (owner ruling 2026-08-11) exactly
    # like mul/char-postings' kanripo lane. The builder refuses to publish
    # if the aes row's license class is not in the publishable set.
    #
    # == The word grain (v2)
    #
    # Each AES token IS a word, so every Gardiner row also carries Words:
    # the word tokens whose spelling carries the code at least once
    # (Words <= Tokens; a sign repeated inside one word — Z2's plural
    # strokes — counts once per word). AES carries no damage flag, so the
    # damaged-attestation count rides the second resource instead:
    # hiero-glyphs.csv, the catalog's precompiled AED per-glyph census
    # (hiero_postings, Store::HieroPostingsBuilder over aed's per-text
    # stand-off hieroglyph files; migration 042 documents the columns) —
    # one row per Unicode hieroglyph: Texts attesting it, Signs (every
    # occurrence), Words (<w> word tokens carrying it at least once,
    # <= Signs) and Unclear (occurrences read inside <unclear> — damaged;
    # a subset of Signs, NOT of Words). Join key: Codepoint/ID against
    # egy/unikemet-signs. AED is CC BY-SA 4.0 too (class `attribution`,
    # gated the same way), so the dataset license is unchanged.
    class HieroFrequencyBuilder
      FILENAME = "hiero-frequency.csv"
      COLUMNS = %w[ID Gardiner Subcorpus Tokens Words Docs Source].freeze
      GLYPHS_FILENAME = "hiero-glyphs.csv"
      GLYPH_COLUMNS = %w[ID Codepoint Glyph Texts Signs Words Unclear Source].freeze
      INTEGER_COLUMNS = %w[Tokens Words Docs Texts Signs Unclear].freeze

      SOURCE_SLUG = "aes"
      GLYPH_SOURCE_SLUG = "aed"
      POSTINGS = :hiero_postings
      ALL = "all"
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      # The hiero_card precedent: the sign spellings are extracted from
      # annotations_json by scan, never a full JSON parse per passage.
      INVENTAR = /"hiero_inventar":\s*"([^"]*)"/

      OVERVIEW =
        "How often does each Egyptian hieroglyph actually occur in real texts — and in which " \
        "genres? This dataset censuses Gardiner-code frequencies from the Ancient Egyptian " \
        "Sentences corpus (TLA gold annotation): for every sign, its token occurrences and " \
        "attesting word and document counts, overall and per subcorpus (Pyramid Texts, Amarna " \
        "letters, medical papyri…). A companion table, hiero-glyphs.csv, counts each Unicode " \
        "hieroglyph across the dictionary's per-text hieroglyph transcriptions — texts, " \
        "occurrences, words, and how many occurrences are damaged (read inside `<unclear>`). " \
        "Sign-learning curricula can order signs by real attestation instead of list order; " \
        "join to egy/unikemet-signs by the Gardiner or Codepoint column for identities."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "egy/hiero-frequency needs the catalog open" if catalog.nil?

        source = publishable_source!(catalog, SOURCE_SLUG)
        publishable_source!(catalog, GLYPH_SOURCE_SLUG)
        glyphs = glyph_postings!(catalog)
        tallies, census, digest = census_documents(catalog, source[:id])
        rows = frequency_rows(tallies)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        glyph_count = CsvWriter.write(path: File.join(out_dir, GLYPHS_FILENAME), columns: GLYPH_COLUMNS,
                                      rows: glyph_rows(glyphs))
        BuildResult.new(
          resources: [resource(count), glyph_resource(glyph_count)],
          recipe: recipe(digest, glyph_digest(glyphs)),
          citations: [citation(SOURCE_SLUG), citation(GLYPH_SOURCE_SLUG)],
          evaluation: census.merge(glyph_census(glyphs)),
          overview: OVERVIEW
        )
      end

      private

      def publishable_source!(catalog, slug)
        source = catalog[:sources].where(slug: slug).select(:id, :license_class).first
        raise Error, "egy/hiero-frequency: the #{slug} source is not in the catalog" if source.nil?
        unless PUBLISHABLE_LICENSE_CLASSES.include?(source[:license_class])
          raise Error, "egy/hiero-frequency: #{slug} license class " \
                       "#{source[:license_class].inspect} is not publishable " \
                       "(#{PUBLISHABLE_LICENSE_CLASSES.join('/')})"
        end

        source
      end

      # The precompiled AED per-glyph census, read BEFORE anything is
      # written: an empty table (aed's hiero cone never synced) refuses,
      # so the dataset never ships without its word-grain resource.
      def glyph_postings!(catalog)
        rows = catalog.table_exists?(POSTINGS) ? catalog[POSTINGS].order(:glyph).all : []
        if rows.empty?
          raise Error, "egy/hiero-frequency: the catalog's #{POSTINGS} table is empty — " \
                       "sync aed (bin/nabu sync aed) to project the AED per-glyph census"
        end

        rows
      end

      # Stream the LIVE aes documents; per document, read its subcorpus
      # (document metadata) once and scan its live passages' annotations
      # for sign spellings. tallies[code][subcorpus] = {tokens:, docs:}.
      def census_documents(catalog, source_id)
        tallies = Hash.new do |h, code|
          h[code] = Hash.new { |g, sub| g[sub] = { tokens: 0, words: 0, docs: 0 } }
        end
        census = { "documents_scanned" => 0, "documents_with_signs" => 0, "tokens_counted" => 0,
                   "words_counted" => 0 }
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
            word_codes = spelling.split(";").map(&:strip).reject(&:empty?)
            next if word_codes.empty?

            census["words_counted"] += 1
            word_codes.each do |code|
              census["tokens_counted"] += 1
              tallies[code][subcorpus][:tokens] += 1
              tallies[code][ALL][:tokens] += 1
            end
            # One AES token = one word: each code counts once per word.
            word_codes.uniq.each do |code|
              tallies[code][subcorpus][:words] += 1
              tallies[code][ALL][:words] += 1
              codes << code
            end
          end
        end
        codes
      end

      # Deterministic order: Gardiner code, then `all` first, then
      # subcorpora alphabetically. IDs mint through the fold+minter (the
      # 2026-09-19 live catch: upstream spellings carry non-Gardiner
      # marker tokens like "!", illegal in a CLDF identifier verbatim —
      # the verbatim code stays in the Gardiner column).
      def frequency_rows(tallies)
        minter = IdMinter.new
        tallies.keys.sort.flat_map do |code|
          subs = tallies[code]
          ([ALL] + (subs.keys - [ALL]).sort).map do |sub|
            { "ID" => minter.mint(code, sub), "Gardiner" => code, "Subcorpus" => sub,
              "Tokens" => subs[sub][:tokens], "Words" => subs[sub][:words], "Docs" => subs[sub][:docs],
              "Source" => SOURCE_SLUG }
          end
        end
      end

      # One row per hiero_postings glyph, codepoint order. The ID is the
      # codepoint without its "+" — the egy/unikemet-signs ID shape, so
      # the two tables join on ID (or Codepoint) directly.
      def glyph_rows(glyphs)
        glyphs.map do |row|
          codepoint = format("U+%04X", row[:glyph].ord)
          { "ID" => codepoint.delete("+"), "Codepoint" => codepoint, "Glyph" => row[:glyph],
            "Texts" => row[:texts], "Signs" => row[:signs], "Words" => row[:words],
            "Unclear" => row[:unclear], "Source" => GLYPH_SOURCE_SLUG }
        end
      end

      def glyph_census(glyphs)
        { "glyphs" => glyphs.size,
          "glyph_sign_occurrences" => glyphs.sum { |row| row[:signs] },
          "glyph_unclear_occurrences" => glyphs.sum { |row| row[:unclear] },
          "glyphs_with_unclear" => glyphs.count { |row| row[:unclear].positive? } }
      end

      # The published glyph census, digested — so a moved AED census moves
      # the recipe (the fingerprint) even when the AES side is unchanged.
      def glyph_digest(glyphs)
        sha = Digest::SHA256.new
        glyphs.each do |row|
          sha << row.values_at(:glyph, :texts, :signs, :words, :unclear).join("\x1f") << "\n"
        end
        sha.hexdigest
      end

      def resource(count)
        Resource.new(name: "hiero_frequency", path: FILENAME, rows: count,
                     fields: typed_fields(COLUMNS), primary_key: ["ID"])
      end

      def glyph_resource(count)
        Resource.new(name: "hiero_glyphs", path: GLYPHS_FILENAME, rows: count,
                     fields: typed_fields(GLYPH_COLUMNS), primary_key: ["ID"])
      end

      def typed_fields(columns)
        columns.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
      end

      def recipe(digest, glyph_digest)
        "hiero-frequency v2: census Gardiner codes from aes hiero_inventar annotations at " \
          "(code, subcorpus) grain, token + word (one aes token = one word; a code counts once " \
          "per word) + attesting-doc counts, `all` roll-up per code, live rows only; " \
          "doc-attestation sha256=#{digest}; plus hiero-glyphs.csv, the catalog's aed " \
          "hiero_postings per-glyph census verbatim (texts, signs, words, unclear) " \
          "sha256=#{glyph_digest}"
      end

      def citation(slug)
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        manifest = registry[slug]&.manifest
        return Citation.new(key: slug, type: "misc", fields: { "title" => slug.upcase }) if manifest.nil?

        Citation.new(key: slug, type: "misc",
                     fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                               "note" => "license: #{manifest.license}" })
      end
    end
  end
end
