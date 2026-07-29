# frozen_string_literal: true

require "digest"

require_relative "builder"
require_relative "csv_writer"
require_relative "../display"

module Nabu
  module DataBuild
    # The lzh/kanripo-gaiji builder (P52-4): publishes the hand-curated
    # Kanripo gaiji display ladder — the per-character resolution of the
    # `&KR\d+;` references the ~9,355 kanripo (lzh) text repos embed for
    # not-yet-encoded characters — as a gold-tier CC BY-SA 4.0 dataset.
    # Three lanes, one per descending display rung (rung 4, the honest ⬚
    # placeholder U+2B1A, is the absence of a row in all three):
    #
    #   faithful.csv     rung 1 — a real assigned Unicode codepoint that IS
    #                    the character (no Private-Use, single codepoint, NFC)
    #   ids.csv          rung 2 — an Ideographic Description Sequence (ships
    #                    empty: the charlist's one composition resolved to an
    #                    encoded glyph form and landed faithful)
    #   substitutes.csv  rung 3 — a lossy standard-char normalization (a
    #                    scholar's read-through, labeled as such)
    #
    # The lanes are DISJOINT by ref (an upper rung wins; validated here and
    # at display time). OWN CURATION over KR-Gaiji (the wylie-fold config
    # precedent): the in-repo config/gaiji/kanripo*.tsv files ARE the data —
    # the SAME files `--display reading` loads through
    # Nabu::Display.load_gaiji_map (one seam, two consumers) — hand-curated
    # from KR-Gaiji's charlist.org.txt at the commit the TSV headers record,
    # deliberately not re-derived at build time, so there are no canonical
    # cones: provenance is the recipe's three file sha256s plus the recorded
    # charlist pin. Refreshing = `nabu sync kr-gaiji`, re-curate by hand
    # (the P38-1 procedure), and the recipe re-fingerprints.
    #
    # BY-SA honesty (owner ruling D51-a): the curation derives from the
    # KR-Gaiji charlist, which rides the kanripo org grant — "Licensed as
    # CC BY SA 4.0." — so the dataset publishes as CC BY-SA 4.0.
    class KanripoGaijiBuilder
      GAIJI_DIR = File.expand_path("../../../config/gaiji", __dir__)
      # The charlist commit the curated TSV headers record (P38-1).
      CHARLIST_PIN = "662fd61d"

      LANES = [
        { name: "faithful", filename: "faithful.csv", tsv: "kanripo.tsv", column: "Glyph" },
        { name: "ids", filename: "ids.csv", tsv: "kanripo-ids.tsv", column: "IDS" },
        { name: "substitutes", filename: "substitutes.csv", tsv: "kanripo-substitutes.tsv",
          column: "Substitute" }
      ].freeze

      REF_PATTERN = /\AKR\d{4}\z/
      BIB_KEY = "kr-gaiji"

      def initialize(gaiji_dir: GAIJI_DIR)
        @gaiji_dir = gaiji_dir
      end

      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        maps = LANES.to_h { |lane| [lane[:name], load_lane(lane)] }
        validate!(maps)
        resources = LANES.map do |lane|
          rows = maps[lane[:name]].sort.map { |ref, value| { "ID" => ref, lane[:column] => value } }
          count = CsvWriter.write(path: File.join(out_dir, lane[:filename]),
                                  columns: ["ID", lane[:column]], rows: rows)
          Resource.new(name: lane[:name], path: lane[:filename], rows: count,
                       fields: ["ID", lane[:column]].map { |name| { name: name, type: "string" } },
                       primary_key: ["ID"])
        end
        BuildResult.new(resources: resources, recipe: recipe, citations: citations, notes: notes(maps))
      end

      private

      # The display ladder's OWN loader — the seam the `reading` mode uses.
      def load_lane(lane)
        path = File.join(@gaiji_dir, lane[:tsv])
        raise Error, "lzh/kanripo-gaiji: #{path} is missing — the curated ladder ships in-repo" unless
          File.file?(path)

        Nabu::Display.load_gaiji_map(path)
      end

      # The ladder contract, re-proven at publish time: KR-shaped refs,
      # non-empty resolutions, lanes disjoint (an upper rung wins).
      def validate!(maps)
        maps.each do |name, map|
          map.each do |ref, value|
            raise Nabu::ValidationError, "#{name}: ref #{ref.inspect} is not KR-shaped" unless
              ref.match?(REF_PATTERN)
            raise Nabu::ValidationError, "#{name}: #{ref} resolves to nothing" if value.to_s.strip.empty?
          end
        end
        overlap = (maps["faithful"].keys & maps["ids"].keys) |
                  (maps["faithful"].keys & maps["substitutes"].keys) |
                  (maps["ids"].keys & maps["substitutes"].keys)
        return if overlap.empty?

        raise Nabu::ValidationError, "gaiji ladder lanes must be disjoint by ref (an upper rung " \
                                     "wins); shared: #{overlap.sort.join(', ')}"
      end

      # No canonical cones: the recipe is the fingerprint's only moving part,
      # so it carries all three curated files' content identities + the
      # charlist commit the curation derives from.
      def recipe
        shas = LANES.map do |lane|
          "#{lane[:tsv]} sha256 #{Digest::SHA256.file(File.join(@gaiji_dir, lane[:tsv])).hexdigest}"
        end
        "lzh/kanripo-gaiji v1: the hand-curated Kanripo gaiji display ladder (#{shas.join('; ')}), " \
          "curated from KR-Gaiji charlist.org.txt @ #{CHARLIST_PIN} (github.com/kanripo/KR-Gaiji) — " \
          "the same three TSVs Nabu's `--display reading` mode loads for kanripo passages"
      end

      def citations
        [
          Citation.new(
            key: BIB_KEY, type: "misc",
            fields: {
              "title" => "KR-Gaiji — Kanseki Repository not-yet-encoded characters (charlist.org.txt)",
              "author" => "{Kanseki Repository (Christian Wittern et al.)}",
              "howpublished" => "https://github.com/kanripo/KR-Gaiji",
              "note" => "Kanripo org-level grant, verbatim: \"Comprehensive collection of premodern " \
                        "Chinese texts. Licensed as CC BY SA 4.0.\" (github.com/kanripo; no per-repo " \
                        "LICENSE file) — the share-alike grant this dataset inherits"
            }
          )
        ]
      end

      def notes(maps)
        resolved = maps.values.sum(&:size)
        <<~NOTES.strip
          ## The ladder — four rungs, three lanes

          Kanripo text repos embed `&KR\\d+;` references for characters not
          yet encoded in Unicode. The display ladder resolves each reference
          per character, in four descending rungs: **faithful** (a real
          assigned codepoint that IS the character), **IDS** (an Ideographic
          Description Sequence — shown when no single codepoint fits),
          **substitute** (a lossy standard-character normalization, a
          scholar's read-through — labeled as such, never merged with
          faithful), and finally the honest **⬚ placeholder** (U+2B1A) for
          the #{5254 - resolved} refs of the charlist's 5,254 that none of
          the lanes resolves — a rung-4 ref is the ABSENCE of a row here,
          never a fake glyph. An upper rung always wins: the lanes are
          disjoint by ref (validated at build time).

          The IDS lane ships EMPTY by census, not by omission: the charlist
          holds exactly one column-3 composition (KR0198 `[沔-丏+丐]`), and
          its resolution ⿰氵丐 is an encoded glyph form of 沔 (U+6C94), so it
          lands in the faithful lane. The lane's shape is published so IDS
          resolutions have a home when curation adds them.

          ## Provenance of the curation

          Hand-curated (the P38-1 honesty gates: single real assigned
          codepoint, no Private-Use-Area rows, NFC, uncertain `?`-marks and
          multi-character cells dropped) from KR-Gaiji `charlist.org.txt` @
          #{CHARLIST_PIN} (2019-11-30), reconciled against Unihan and
          BabelStone IDS. Curation-time coverage census: faithful rows cover
          36.55% of all 1,751,360 gaiji occurrences in the kanripo corpus,
          substitutes a further 45.25% (cumulative 81.80%). The curation is
          pinned to that charlist commit — deliberately NOT re-derived at
          build time — so this dataset declares no canonical inputs; its
          derivation identity is the recipe's three file sha256s. When
          upstream advances: `nabu sync kr-gaiji`, re-curate, rebuild.

          These resolutions serve Literary Chinese (lzh) kanripo passages;
          inside Nabu the same three files feed `--display reading`.
        NOTES
      end
    end
  end
end
