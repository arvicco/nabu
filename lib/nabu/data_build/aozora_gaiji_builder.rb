# frozen_string_literal: true

require "digest"

require_relative "../ops/aozora_ids_builder"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The jpn/aozora-gaiji builder (P52-3): publishes the Aozora Bunko gaiji
    # composition census — the formulas Aozora transcribers write for glyphs
    # Unicode cannot encode (※［＃…］ notations) — plus the IDS lane a
    # conservative structural grammar can prove.
    #
    # == The input call (stated where it is decided)
    #
    # inputs/canonical_cones are EMPTY: the build is a pure function of the
    # checked-in census TSV (config/gaiji/aozora-descriptions.tsv) — the
    # source of truth, snapshotted read-only from the live Aozora corpus on
    # the owner's schedule (snapshot provenance rides the TSV header). The
    # aozora cone is NOT declared, deliberately: the dataset must not drift
    # with every corpus sync — it moves when the owner re-censuses — and the
    # builder never reads canonical or the catalog. The wylie-fold precedent
    # covers the fingerprint: the recipe embeds the TSV's sha256, so a
    # re-census re-fingerprints the dataset; the corpus linkage is carried as
    # provenance (citation + README), not as a cone.
    #
    # Two tables, joined on ID/Description: descriptions.csv (the full census
    # — occurrence Count and Resolution status per formula) and ids.csv (the
    # derived Ideographic Description Sequences). The IDS lane derives through
    # Nabu::Ops::AozoraIdsBuilder — the SAME grammar `rake gaiji:aozora_ids`
    # compiles for the display ladder (one grammar, two consumers).
    class AozoraGaijiBuilder
      DESCRIPTIONS_FILENAME = "descriptions.csv"
      IDS_FILENAME = "ids.csv"
      DESCRIPTIONS_COLUMNS = %w[ID Description Count Resolution Source].freeze
      IDS_COLUMNS = %w[ID Description IDS Source].freeze
      BIB_KEY = "aozora"

      # Refusal class → the published Resolution value ("ids" marks the
      # derived rows; everything else names WHY the grammar refused).
      RESOLUTIONS = {
        kana_component: "kana-component", replace: "replace", subtractive: "subtractive",
        parenthesised: "parenthesised", multi_operator: "multi-operator", other: "other"
      }.freeze

      NOTES = <<~NOTES.strip
        ## What the census is

        Aozora Bunko transcribers describe unencodable glyphs (gaiji) in-text
        with composition formulas — ※［＃「口＋斗」…］ "mouth beside dipper".
        descriptions.csv is the census of every DISTINCT composition formula
        in the public-domain corpus (the parser's class-(c) unresolved-gaiji
        annotations), with its live occurrence Count at the snapshot date and
        its Resolution status. The checked-in census TSV is the dataset's
        source of truth; its header carries the snapshot provenance (corpus
        size, date), and this dataset re-fingerprints whenever the owner
        re-censuses (the recipe embeds the TSV's sha256).

        ## The honesty bar for ids.csv

        A derived ⿰AB is a STRUCTURAL claim (A-left, B-right), never an
        identity claim and never a real codepoint. The grammar therefore
        derives ONLY the mechanically unambiguous shapes — a single ＋ between
        two literal Han ideographs (⿰), a single ／ (⿱) — and refuses
        everything else, per class: `kana-component` (a radical NAME like
        にんべん is not a component glyph), `replace` (「…」に代えて prose),
        `subtractive` (旗－其＋冉 is arithmetic on parts, not IDS),
        `parenthesised` (nested grouping), `multi-operator` (ambiguous
        nesting), `other` (non-Han operands, malformed). Nothing is guessed;
        the refusal classes are the map of what a future, braver derivation
        would have to defend.

        ## Loading

            import pandas as pd
            census = pd.read_csv("descriptions.csv", keep_default_na=False)
            ids = pd.read_csv("ids.csv", keep_default_na=False)

        `ID` is the primary key in both tables (`g-<sha256(Description)[0,12]>`
        — the formula itself cannot survive the CLDF identifier class, so it
        is digested); `Description` is also unique per table, and ids.csv rows
        are exactly the `Resolution == "ids"` census rows.
      NOTES

      def initialize(census_path: Ops::AozoraIdsBuilder::CENSUS_PATH)
        @census_path = census_path
      end

      # The builder contract: a pure function of the checked-in census TSV —
      # no canonical, no catalog (deliberately unused).
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        ids_builder = Ops::AozoraIdsBuilder.new(census_path: @census_path)
        resolution = resolution_by_desc(ids_builder)
        desc_count = CsvWriter.write(path: File.join(out_dir, DESCRIPTIONS_FILENAME),
                                     columns: DESCRIPTIONS_COLUMNS,
                                     rows: description_rows(ids_builder, resolution))
        ids_count = CsvWriter.write(path: File.join(out_dir, IDS_FILENAME),
                                    columns: IDS_COLUMNS, rows: ids_rows(ids_builder))
        BuildResult.new(
          resources: [resource("descriptions", DESCRIPTIONS_FILENAME, DESCRIPTIONS_COLUMNS, desc_count),
                      resource("ids", IDS_FILENAME, IDS_COLUMNS, ids_count)],
          recipe: recipe(ids_builder), citations: citations, notes: NOTES
        )
      end

      private

      # desc → "ids" | refusal class, from the ops builder's own
      # classification — never re-derived here.
      def resolution_by_desc(ids_builder)
        map = ids_builder.lane.keys.to_h { |desc| [desc, "ids"] }
        ids_builder.refusals.each do |cls, descs|
          descs.each { |desc| map[desc] = RESOLUTIONS.fetch(cls) }
        end
        map
      end

      # Rows desc-sorted (codepoint order) — the generated TSV's stable-diff
      # discipline, and the order ids.csv shares.
      def description_rows(ids_builder, resolution)
        ids_builder.descriptions.sort_by { |desc, _| desc }.map do |desc, count|
          { "ID" => mint_id(desc), "Description" => desc, "Count" => count,
            "Resolution" => resolution.fetch(desc), "Source" => BIB_KEY }
        end
      end

      def ids_rows(ids_builder)
        ids_builder.lane.sort_by { |desc, _| desc }.map do |desc, ids|
          { "ID" => mint_id(desc), "Description" => desc, "IDS" => ids, "Source" => BIB_KEY }
        end
      end

      # Deterministic, content-derived, ASCII (the verb-lemma discipline):
      # the formula is the identity, so its digest is the ID — stable across
      # census reorderings and joinable across the two tables.
      def mint_id(desc)
        CsvWriter.mint_id("g", Digest::SHA256.hexdigest(desc)[0, 12])
      end

      # Part of the derivation fingerprint. The census sha256 is embedded
      # because this feature declares no canonical cones (the wylie-fold
      # precedent): the recipe is the fingerprint's only moving part.
      def recipe(ids_builder)
        "aozora-gaiji v1: the checked-in composition-description census " \
          "(config/gaiji/aozora-descriptions.tsv, sha256 #{ids_builder.census_sha256}; snapshotted " \
          "read-only from the live Aozora corpus — snapshot provenance in the TSV header) published " \
          "as descriptions.csv (occurrence Count + Resolution status per formula, desc-sorted); " \
          "ids.csv derives the IDS lane through Nabu::Ops::AozoraIdsBuilder — the SAME grammar " \
          "`rake gaiji:aozora_ids` compiles for the display ladder (single ＋ between two literal " \
          "Han ideographs → ⿰, single ／ → ⿱, everything else refused by class, never guessed); " \
          "ID = g-<sha256(desc)[0,12]>"
      end

      def resource(name, path, columns, count)
        Resource.new(
          name: name, path: path, rows: count,
          fields: columns.map { |column| { name: column, type: column == "Count" ? "integer" : "string" } },
          primary_key: ["ID"]
        )
      end

      # Aozora cited as docs/02-sources.md row 110 records it: PD works only
      # (作品著作権フラグ=なし), the 取り扱い規準 grant verbatim.
      def citations
        [Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "Aozora Bunko 青空文庫 — Japanese public-domain library",
            "howpublished" => "https://www.aozora.gr.jp/ (mirror: https://github.com/aozorabunko/aozorabunko)",
            "note" => "Public-domain works only (作品著作権フラグ=なし); site grant (kijyunn.html, " \
                      "verbatim): 「ファイルは、有償・無償であるかを問わず、自由に複製・再配布・共有する" \
                      "ことができます。」 — the composition formulas are the transcribers' own curation, " \
                      "censused from the corpus"
          }
        )]
      end
    end
  end
end
