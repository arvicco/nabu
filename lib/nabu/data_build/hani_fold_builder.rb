# frozen_string_literal: true

require_relative "../config"
require_relative "../adapters/unihan"
require_relative "../ops/hani_fold_builder"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The zho/hani-fold builder (P52-3): publishes the Han trad↔simp↔z-variant
    # fold as a nabu-data dataset. THE DESIGN RULE (fold-in audit): the source
    # of truth STAYS upstream Unihan — canonical/unihan/Unihan_Variants.txt is
    # the declared input cone, and the resolution runs through
    # Nabu::Ops::HaniFoldBuilder, the SAME seam `rake fold:hani` compiles into
    # Nabu::Hani (one resolution path, two consumers; nothing is inverted into
    # an own-authored rules file — unlike xct/wylie-fold, which IS own
    # authorship).
    #
    # Two tables: pairs.csv (the resolved fold, variant → canonical
    # traditional, sorted by variant codepoint) and refusals.csv (the censused
    # refusals, one row per refused form WITH its reason — the conservative
    # curation is the value, so it is published, not buried in a comment).
    #
    # Tier call (stated where it is decided): gold-DERIVED, not gold — the
    # pairs are a mechanical, deterministic resolution of upstream-declared
    # variant relations, the exact posture of xct/verb-lemma's expansion of
    # TVD rows; "gold" is reserved for own-authored/hand-curated tables
    # (wylie-fold, aozora-gaiji).
    #
    # Per-pair provenance kind (direct / z-cluster / reverse-only) is
    # deliberately NOT a column: chains compose to fixed points (a→b→c ⇒ a→c),
    # so a composed pair can mix evidence kinds and a per-row label would
    # overclaim. The aggregate census rides the README instead. Likewise the
    # kSemanticVariant/kSpecializedSemanticVariant annotations do NOT ride:
    # semantic variants name different WORDS (㐀 "hillock" vs 丘) — they never
    # enter the graph upstream of us (the ops builder's field discipline), and
    # publishing them here would smuggle a word-identity claim into an
    # orthography table.
    class HaniFoldBuilder
      CONE = Adapters::Unihan::DICTIONARY_SLUG
      VARIANTS_FILENAME = Adapters::Unihan::VARIANTS_FILE
      PAIRS_FILENAME = "pairs.csv"
      REFUSALS_FILENAME = "refusals.csv"
      PAIRS_COLUMNS = %w[ID Variant Traditional Variant_Codepoint Traditional_Codepoint Source].freeze
      REFUSALS_COLUMNS = %w[ID Form Reason Source].freeze
      BIB_KEY = "unihan"

      # Census field → the published refusal Reason, in publication order.
      REASONS = {
        self_ambiguous: "self-listing",
        multi_trad: "multi-traditional",
        multi_reverse: "multi-reverse",
        trad_simp_conflicts: "trad-simp-conflict",
        z_conflicts: "z-cluster-unmergeable"
      }.freeze

      # Part of the derivation fingerprint: changing the derivation MUST
      # change this string (the input bytes ride the unihan cone sha).
      RECIPE = "hani-fold v1: canonical/unihan/Unihan_Variants.txt resolved through " \
               "Nabu::Ops::HaniFoldBuilder — the SAME seam `rake fold:hani` compiles into " \
               "Nabu::Hani (one resolution path, two consumers). kTraditionalVariant/" \
               "kSimplifiedVariant/kZVariant only; kSemanticVariant, kSpecializedSemanticVariant " \
               "and kSpoofingVariant are structurally excluded (different words / security data, " \
               "never orthography). Conservative resolution: z-cluster union-find, single-target " \
               "direct folds, multi-targets resolved only within one z-cluster, reverse-only " \
               "kSimplifiedVariant evidence, chains composed to fixed points, cycles to the " \
               "lowest codepoint; every ambiguity is REFUSED and published per-row in " \
               "refusals.csv. Codepoints NFC at build; pairs sorted by variant codepoint; " \
               "ID minted from the variant codepoint (U+4E9A → U-4E9A)."

      NOTES = <<~NOTES.strip
        ## What the fold is (and is not)

        Each pair maps a variant codepoint to its CANONICAL TRADITIONAL form —
        the form the traditional-script corpora (kanripo, cbeta) store — so
        simplified-script queries and traditional-script text meet on one
        skeleton. It is an ORTHOGRAPHY table: only Unihan's
        kTraditionalVariant / kSimplifiedVariant / kZVariant fields enter the
        graph. The semantic-variant fields (kSemanticVariant,
        kSpecializedSemanticVariant) name different words that mean the same
        thing — folding them would be a lie — and kSpoofingVariant is security
        data; all three are excluded structurally, never row-by-row.

        Per-pair provenance kind (direct / z-cluster / reverse-only) is
        deliberately not a column: chains compose to fixed points, so one
        published pair can mix evidence kinds. The aggregate census above is
        the honest grain.

        ## The refusals are the curation

        Every ambiguous fold is refused and PUBLISHED in refusals.csv with its
        reason: `self-listing` (the char lists itself among its traditional
        variants — a traditional word in its own right; 了→瞭 would merge two
        real words), `multi-traditional` (targets across distinct clusters —
        发→發/髮 is a genuine merger; picking one is a guess),
        `multi-reverse`, `trad-simp-conflict` (the two directional fields
        disagree), and `z-cluster-unmergeable` (whose Form lists the whole
        cluster's members). Consumers wanting a looser fold can relax exactly
        the classes they accept.

        ## Language scope (the zho call)

        languages.csv lists zho — the ISO 639-3 macrolanguage, the same
        pan-CJK macro tag Nabu's own unihan shelf files under. Glottolog
        assigns macrolanguages no glottocode, so that cell is honestly empty.
        Inside Nabu the fold normalizes search for the Literary Chinese
        corpora (lzh, och — kanripo/cbeta); it applies wherever Han
        orthography variation crosses a query, and the one-language-per-
        feature rail contract states that here instead of duplicating rows.

        ## Loading

            import pandas as pd
            pairs = pd.read_csv("pairs.csv")
            refusals = pd.read_csv("refusals.csv")

        `ID` is the primary key in both tables; `Variant` is also unique in
        pairs.csv (one fold per codepoint), and every `Traditional` value is a
        fixed point — never itself a variant key.
      NOTES

      def initialize(canonical_dir: Nabu::Config.load.canonical_dir)
        @canonical_dir = canonical_dir
      end

      # The builder contract: read canonical/unihan read-only through the
      # shared ops resolver, write pairs.csv + refusals.csv into out_dir. The
      # catalog is deliberately unused (the fold is a pure function of the
      # variants file; the Runner's stale-ingest guard still rides the cone).
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        fold = Ops::HaniFoldBuilder.new(variants_path: variants_path)
        pair_count = CsvWriter.write(path: File.join(out_dir, PAIRS_FILENAME),
                                     columns: PAIRS_COLUMNS, rows: pair_rows(fold))
        refusal_count = CsvWriter.write(path: File.join(out_dir, REFUSALS_FILENAME),
                                        columns: REFUSALS_COLUMNS, rows: refusal_rows(fold.census))
        BuildResult.new(
          resources: [resource("pairs", PAIRS_FILENAME, PAIRS_COLUMNS, pair_count),
                      resource("refusals", REFUSALS_FILENAME, REFUSALS_COLUMNS, refusal_count)],
          recipe: RECIPE, citations: citations, notes: notes(fold.census, pair_count)
        )
      end

      private

      def variants_path
        path = File.join(@canonical_dir, CONE, VARIANTS_FILENAME)
        return path if File.file?(path)

        raise Error, "canonical input #{CONE.inspect} has no #{VARIANTS_FILENAME} under " \
                     "#{File.join(@canonical_dir, CONE)} — run `nabu sync unihan` first"
      end

      # The resolved fold, already key-sorted by the ops builder; every key
      # and value is a single NFC codepoint (asserted at resolution).
      def pair_rows(fold)
        fold.table.map do |variant, traditional|
          { "ID" => CsvWriter.mint_id(codepoint(variant)),
            "Variant" => variant, "Traditional" => traditional,
            "Variant_Codepoint" => codepoint(variant),
            "Traditional_Codepoint" => codepoint(traditional),
            "Source" => BIB_KEY }
        end
      end

      # One row per censused refusal, reason-major, codepoint-sorted within a
      # reason. A z-cluster-unmergeable Form is the whole cluster's members.
      def refusal_rows(census)
        REASONS.flat_map do |field, reason|
          census[field].sort_by { |form| form.chars.map(&:ord) }.map do |form|
            { "ID" => CsvWriter.mint_id(reason, *form.each_char.map { |char| codepoint(char) }),
              "Form" => form, "Reason" => reason, "Source" => BIB_KEY }
          end
        end
      end

      def codepoint(char)
        format("U+%04X", char.ord)
      end

      def resource(name, path, columns, count)
        Resource.new(
          name: name, path: path, rows: count,
          fields: columns.map { |column| { name: column, type: "string" } },
          primary_key: ["ID"]
        )
      end

      # The census at this derivation, quoted in the README above the static
      # notes — deterministic for a given input, so build-twice stays
      # byte-identical.
      def notes(census, pair_count)
        refused = REASONS.sum { |field, _| census[field].size }
        census_section = <<~CENSUS.strip
          ## The census at this derivation

          Unihan #{census.unihan_version} (file date #{census.unihan_date}):
          #{pair_count} fold pairs — #{census.direct} direct,
          #{census.cluster_resolved} via z-cluster targets,
          #{census.reverse_only.size} reverse-only, #{census.z_members} z-cluster
          members; #{census.cycles} cycle(s) resolved to lowest codepoint.
          Refused (published in refusals.csv): #{refused} —
          #{census.self_ambiguous.size} self-listing,
          #{census.multi_trad.size} multi-traditional,
          #{census.multi_reverse.size} multi-reverse,
          #{census.trad_simp_conflicts.size} trad-simp-conflict,
          #{census.z_conflicts.size} z-cluster-unmergeable.
          Excluded structurally: #{census.semantic_lines_excluded} semantic-variant
          lines (never read into the graph).
        CENSUS
        "#{census_section}\n\n#{NOTES}"
      end

      # Unihan cited as docs/02-sources.md row 100 records it (Unicode
      # License V3 → open; notice preservation).
      def citations
        [Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "Unihan — the Unicode Han Database (Unihan_Variants.txt)",
            "author" => "{The Unicode Consortium}",
            "howpublished" => "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip",
            "note" => "Unicode License V3 (unicode.org/license.txt: \"Permission is hereby granted, " \
                      "free of charge, ... to deal in the Data Files or Software without " \
                      "restriction ...\" with notice preservation)"
          }
        )]
      end
    end
  end
end
