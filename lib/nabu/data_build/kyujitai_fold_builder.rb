# frozen_string_literal: true

require_relative "builder"
require_relative "csv_writer"
require_relative "../config"
require_relative "../ops/jpn_fold_builder"

module Nabu
  module DataBuild
    # The jpn/kyujitai-fold builder (P52-4): publishes the two-lane Japanese
    # kyūjitai↔shinjitai pair census as a gold-tier, CC BY-SA 4.0 nabu-data
    # dataset. The derivation is Nabu::Ops::JpnFoldBuilder — the SAME
    # resolution seam `rake fold:jpn` compiles into Nabu::Jpn, Nabu's jpn
    # search fold (one seam, two consumers; the D38-b policy and the
    # 2026-07-21 merge-admission ruling live on that class):
    #
    #   lane "jinmeiyo"        Unihan kJinmeiyoKanji 1:1 reform pairs — the
    #                          SEMANTIC old/new relation (Unicode License V3)
    #   lane "kanjidic"        KANJIDIC2 jis208/jis213 variant edges whose
    #                          target is jōyō (grade 1–6/8 ∩ kJoyoKanji) —
    #                          1:1 singles (EDRDG, CC BY-SA 4.0)
    #   lane "kanjidic-merge"  the admitted reform merges (辨/瓣/辯→弁): each
    #                          old claimant is one edge onto the shared new
    #
    # A kanjidic edge that duplicates a jinmeiyō pair exactly (國→国 rides
    # both) is emitted ONCE, under its authoritative lane. The generator's
    # refusals are part of the census and ship as refusals.csv — one-to-many
    # ambiguous olds (never picked arbitrarily) and jinmeiyō-lane conflicts.
    #
    # BY-SA honesty (owner ruling D51-a): the load-bearing kanjidic lanes
    # derive from KANJIDIC2, EDRDG share-alike — the whole table publishes as
    # CC BY-SA 4.0 and its manifest overrides the repo-default CC BY.
    class KyujitaiFoldBuilder
      MAPPINGS_RELPATH = File.join("unihan", "Unihan_OtherMappings.txt")
      KANJIDIC_RELPATH = File.join("edrdg", "kanjidic2", "kanjidic2.xml.gz")

      PAIRS_FILENAME = "pairs.csv"
      REFUSALS_FILENAME = "refusals.csv"
      PAIR_COLUMNS = %w[ID Old_Form New_Form Lane Source].freeze
      REFUSAL_COLUMNS = %w[ID Form Reason Detail].freeze

      UNIHAN_BIB_KEY = "unihan"
      KANJIDIC_BIB_KEY = "kanjidic2"

      # Part of the derivation fingerprint (with the two cone shas): changing
      # the lane policy or the rendering MUST change this string.
      RECIPE = "jpn/kyujitai-fold v1: two-lane kyūjitai↔shinjitai pair census rendered through " \
               "Nabu::Ops::JpnFoldBuilder — the same resolution seam `rake fold:jpn` compiles into " \
               "Nabu::Jpn, Nabu's jpn search fold. Lane 1 (jinmeiyo): Unihan kJinmeiyoKanji 1:1 " \
               "reform pairs, NFC-identity compat pointers dropped. Lane 2 (kanjidic): KANJIDIC2 " \
               "jis208/jis213 variant edges (decoded through the held JIS X 0213 table; jis212 " \
               "refused — a different standard) whose target is jōyō = KANJIDIC2 grade 1–6/8 ∩ " \
               "Unihan kJoyoKanji (D38-b), reform merges admitted per the 2026-07-21 owner ruling; " \
               "one-to-many ambiguous olds and jinmeiyō-lane conflicts refused into refusals.csv. " \
               "A kanjidic edge duplicating a jinmeiyō pair is emitted once, under lane jinmeiyo."

      def initialize(canonical_dir: Nabu::Config.load.canonical_dir)
        @canonical_dir = canonical_dir
      end

      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        seam = Ops::JpnFoldBuilder.new(mappings_path: input_path(MAPPINGS_RELPATH, "unihan"),
                                       kanjidic_path: input_path(KANJIDIC_RELPATH, "edrdg"))
        pair_count = CsvWriter.write(path: File.join(out_dir, PAIRS_FILENAME),
                                     columns: PAIR_COLUMNS, rows: pair_rows(seam))
        refusal_count = CsvWriter.write(path: File.join(out_dir, REFUSALS_FILENAME),
                                        columns: REFUSAL_COLUMNS, rows: refusal_rows(seam))
        BuildResult.new(
          resources: [tabular_resource("pairs", PAIRS_FILENAME, pair_count, PAIR_COLUMNS),
                      tabular_resource("refusals", REFUSALS_FILENAME, refusal_count, REFUSAL_COLUMNS)],
          recipe: RECIPE, citations: citations, notes: notes(seam)
        )
      end

      private

      def input_path(relpath, slug)
        path = File.join(@canonical_dir, relpath)
        return path if File.file?(path)

        raise Error, "jpn/kyujitai-fold needs canonical/#{relpath} and it is missing — " \
                     "run `nabu sync #{slug}` before building"
      end

      # -- rows ---------------------------------------------------------------

      # Lane 1 first (sorted by old form), then the kanjidic edges in the
      # seam's deterministic (new, old) order, minus exact lane-1 duplicates.
      def pair_rows(seam)
        jinmeiyo = seam.reform_pairs.map { |new, old| pair_row(old, new, "jinmeiyo", UNIHAN_BIB_KEY) }
                                    .sort_by { |row| row["ID"] }
        kanjidic = seam.kanjidic_edges
                       .reject { |edge| seam.reform_pairs[edge.new_form] == edge.old_form }
                       .map do |edge|
          pair_row(edge.old_form, edge.new_form, edge.merge ? "kanjidic-merge" : "kanjidic", KANJIDIC_BIB_KEY)
        end
        jinmeiyo + kanjidic
      end

      def pair_row(old, new, lane, source)
        { "ID" => mint_pair_id(old, new), "Old_Form" => old, "New_Form" => new,
          "Lane" => lane, "Source" => source }
      end

      # Codepoint-derived and content-stable: 國→国 mints "u570b-u56fd".
      # (old, new) is unique across the census — an old folds into at most
      # one group and lane-1 duplicates are dropped — so the ID is the PK.
      def mint_pair_id(old, new)
        CsvWriter.mint_id(format("u%04x", old.ord), format("u%04x", new.ord))
      end

      def refusal_rows(seam)
        ambiguous = seam.census.ambiguous_refused.map do |old, news|
          { "ID" => CsvWriter.mint_id("refused", format("u%04x", old.ord)), "Form" => old,
            "Reason" => "one-to-many-ambiguity",
            "Detail" => "variant-linked to #{news.size} distinct jōyō forms (#{news.join(' ')}); " \
                        "never picked arbitrarily" }
        end
        conflicts = seam.census.jinmeiyo_conflicts.map do |from, kept, dropped|
          { "ID" => CsvWriter.mint_id("conflict", format("u%04x", from.ord)), "Form" => from,
            "Reason" => "jinmeiyo-lane-conflict",
            "Detail" => "the jinmeiyō lane already folds it to #{kept}; the kanjidic edge to " \
                        "#{dropped} is dropped (lane 1 is authoritative)" }
        end
        ambiguous + conflicts
      end

      # -- furniture ----------------------------------------------------------

      def tabular_resource(name, path, rows, columns)
        Resource.new(name: name, path: path, rows: rows,
                     fields: columns.map { |column| { name: column, type: "string" } },
                     primary_key: ["ID"])
      end

      def citations
        [
          Citation.new(
            key: UNIHAN_BIB_KEY, type: "misc",
            fields: {
              "title" => "Unihan — the Unicode Han Database (Unihan_OtherMappings.txt: " \
                         "kJinmeiyoKanji, kJoyoKanji)",
              "author" => "{The Unicode Consortium}",
              "howpublished" => "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip",
              "note" => "Unicode License V3 (https://www.unicode.org/license.txt)"
            }
          ),
          Citation.new(
            key: KANJIDIC_BIB_KEY, type: "misc",
            fields: {
              "title" => "KANJIDIC2 (The KANJIDIC Project)",
              "author" => "{Electronic Dictionary Research and Development Group}",
              "howpublished" => "https://www.edrdg.org/wiki/index.php/KANJIDIC_Project",
              "note" => "Property of the EDRDG, used in conformance with the Group's licence " \
                        "(https://www.edrdg.org/edrdg/licence.html): \"The dictionary files are " \
                        "made available under a Creative Commons Attribution-ShareAlike Licence " \
                        "(V4.0).\" — the share-alike input that makes this dataset CC BY-SA 4.0"
            }
          )
        ]
      end

      def notes(seam)
        census = seam.census
        <<~NOTES.strip
          ## The two lanes — and what a row asserts

          `Lane=jinmeiyo` rows are Unicode's own kJinmeiyoKanji reform pairs:
          the SEMANTIC kyūjitai relation (the character card's old/new
          cross-reference). `Lane=kanjidic` and `Lane=kanjidic-merge` rows are
          FINDABILITY edges mined from KANJIDIC2 variant links under the
          jōyō-target policy — not all of them are genuine "old forms" (弃 is
          棄's ancient form), so they feed search folding, never the semantic
          relation. A merge row's new form is shared by 2+ old claimants
          (辨/瓣/辯→弁): distinct classical words the script reform collapsed,
          admitted deliberately to match modern reading habits.

          Inside Nabu the same census compiles (via `rake fold:jpn`) into the
          jpn search fold, whose fold TARGET composes through the Han
          traditional/simplified table so Japanese and Chinese forms land on
          one skeleton — this dataset publishes the pair relation itself and
          leaves skeleton composition to the consumer's Han table.

          ## The census (this derivation)

          - jinmeiyō 1:1 pairs: #{census.jinmeiyo_pairs}
          - kanjidic 1:1 singles: #{census.kanjidic_singles}
          - kanjidic merges: #{census.merges.size} new forms ← #{census.merges.values.sum(&:size)} old claimants
          - refused (refusals.csv): #{census.ambiguous_refused.size} one-to-many ambiguous, \
          #{census.jinmeiyo_conflicts.size} jinmeiyō-lane conflicts
          - dropped silently by policy: #{census.nfc_identity_dropped} NFC-identity compat pointers \
          (they cannot survive NFC text); all jis212 variant links (JIS X 0212 is a different \
          standard than the JIS X 0213 table used for decoding)

          Upstream at derivation: Unihan #{census.unihan_version} (file date #{census.unihan_date}),
          KANJIDIC2 #{census.kanjidic_version} (date of creation #{census.kanjidic_date}).

          ## Licensing

          The jinmeiyō lane derives from Unihan (Unicode License V3); the
          kanjidic lanes derive from KANJIDIC2, which the EDRDG makes
          available under CC BY-SA 4.0. The combined table is therefore
          published CC BY-SA 4.0 (see sources.bib for the required
          attributions), overriding the nabu-data repository default.
        NOTES
      end
    end
  end
end
