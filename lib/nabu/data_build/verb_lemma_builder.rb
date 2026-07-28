# frozen_string_literal: true

require "digest"

require_relative "../config"
require_relative "../normalize"
require_relative "../adapters/flat_csv_parser"
require_relative "../adapters/tibetan_verbs"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The xct/verb-lemma builder (P50-W4) — the TABLE HALF of the Tibetan
    # verb stem → paradigm-lemma map, derived from the Tibetan Verbs Database
    # (tibetan-nlp TVD, CC0-1.0). The anchored layer over the canon (stem
    # occurrences pinned to passage URNs) is explicitly deferred behind
    # xct/segmentation; anchoring stays "none" by design, not omission.
    #
    # == Read path
    #
    # canonical/tibetan-verbs/db.csv, read-only, through the adapter's own
    # FlatCsvParser + header constants (a silent upstream rename fails loudly
    # in the adapter and here alike). NOT the catalog: the shelf collapses
    # the stem tuple and its attributions into rendered entry-body text —
    # only the canonical CSV carries the full structure.
    #
    # == The grain (owner-approved): one row per grammarian-analysis
    #
    # Upstream keeps its authorities' disagreements as separate uncollapsed
    # rows ("no choice has been made about the correctness of the different
    # forms" — upstream README), each row flagged by one or more source
    # columns (TDC/PH/GT/KN). This table goes one step finer: one output row
    # per (stem tuple × attesting source), so Analysis_Source always names
    # exactly one authority and never a false consensus. Whole-file census
    # (2026-07-28): 2,491 upstream rows → 3,889 attestation rows; even
    # (stem tuple, source) repeats once (PH restates འབྲལ verbatim), so the
    # primary key is the minted ID, not any column tuple.
    #
    # - Lemma: the paradigm lemma = the present stem (ད་ལྟ), the citation
    #   form — the same call the adapter makes for the shelf headword.
    # - Empty stems stay empty cells, never invented (599 upstream rows lack
    #   an imperative; 11 carry only a present stem).
    # - Tibetan script only: upstream carries no Wylie romanization and this
    #   builder never transliterates (xct/wylie-fold owns that space).
    # - Language_ID: "xct" throughout — the one-tag call. Upstream carries
    #   no language tagging at all; the tense-stem paradigm system is the
    #   classical one. (Nabu's own shelf files these entries under the
    #   adapter's broader "bod" tag; the published dataset commits to the
    #   honest narrow tag its registry Language declares.)
    class VerbLemmaBuilder
      CONE = Adapters::TibetanVerbs::DICTIONARY_SLUG
      FILENAME = "verb-lemma.csv"
      COLUMNS = %w[ID Language_ID Lemma Present Past Future Imperative Analysis_Source Comment Source].freeze
      LANGUAGE_ID = "xct"
      BIB_KEY = "tvd"

      # The ID digest separator — the DerivationFingerprint token discipline.
      SEPARATOR = "\x1f"

      # Part of the derivation fingerprint: changing the derivation MUST
      # change this string.
      RECIPE = "verb-lemma v1: canonical/tibetan-verbs/db.csv expanded to one row per " \
               "(stem tuple × attesting source tag TDC/PH/GT/KN, read from the cell value, not " \
               "the column position) — disagreements uncollapsed, " \
               "empty stems stay empty, values NFC-normalized, Tibetan script only (no " \
               "transliteration); Lemma = the present stem; ID = v-<sha256(stem tuple)[0,12]>-" \
               "<source>, positional -<n> when upstream restates a (stems, source) row. Table " \
               "half only: the anchored layer over the canon is deferred behind xct/segmentation."

      NOTES = <<~NOTES.strip
        ## Scope — the table half only

        This release is the verb-stem table alone. The anchored layer over the
        canon (stem occurrences pinned to passage URNs in the Tibetan corpora)
        is explicitly deferred: it depends on tsheg-bar/word segmentation,
        which lands with `xct/segmentation`. Anchoring here is `none` by
        design, not omission.

        ## The grain — one row per grammarian-analysis

        The TVD deliberately preserves its sources' disagreements ("no choice
        has been made about the correctness of the different forms" — upstream
        README). This table keeps them uncollapsed and goes one step finer:
        each upstream stem-tuple row becomes one row per attesting source, so
        `Analysis_Source` always names exactly one authority — the values
        (`TDC`, `PH`, `GT`, `KN`) are the TVD's own source tags, verbatim; see
        the upstream repository's bibliography for the works behind them.
        Filtering on one `Analysis_Source` value yields that authority's
        complete verb table. Note that `(Lemma, Analysis_Source)` is NOT
        unique — one authority can give several paradigms for one present
        stem — and upstream even restates one `(stems, source)` row verbatim,
        so the primary key is the minted `ID`.

        ## Columns

        `Lemma` is the paradigm lemma — the present stem (ད་ལྟ), the citation
        form. `Present`/`Past`/`Future`/`Imperative` carry the stems in
        Tibetan script as upstream gives them (NFC-normalized; upstream's
        second-suffix-ད / alternate-orthography notation `༼ད༽` kept verbatim).
        An empty cell means the authority gives no such form — absence is
        honest, never filled in. Upstream carries no Wylie romanization, so
        none is published here: transliteration belongs to `xct/wylie-fold`.
        `Language_ID` is `xct` (Classical Tibetan) throughout — upstream
        carries no language tagging of its own; the one-tag call is stated in
        the producer contract.

        ## Loading

            import pandas as pd
            df = pd.read_csv("verb-lemma.csv", keep_default_na=False)
      NOTES

      def initialize(canonical_dir: Nabu::Config.load.canonical_dir)
        @canonical_dir = canonical_dir
      end

      # The builder contract: read canonical/tibetan-verbs read-only, write
      # verb-lemma.csv into out_dir, describe the derivation. The catalog is
      # deliberately unused (see the read-path note above).
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: table_rows)
        BuildResult.new(resources: [resource(count)], recipe: RECIPE, citations: citations, notes: NOTES)
      end

      private

      def csv_path
        path = File.join(@canonical_dir, CONE, Adapters::TibetanVerbs::CSV_FILENAME)
        return path if File.file?(path)

        raise Error, "canonical input #{CONE.inspect} has no #{Adapters::TibetanVerbs::CSV_FILENAME} " \
                     "under #{File.join(@canonical_dir, CONE)} — run `nabu sync tibetan-verbs` first"
      end

      def table_rows
        occurrences = Hash.new(0)
        rows = []
        parser.each_row(csv_path) do |record|
          stems = Adapters::TibetanVerbs::STEM_COLUMNS.transform_values do |column|
            value = Normalize.nfc(record[column].to_s.strip)
            value.empty? ? nil : value
          end
          attesting_sources(record).each { |source| rows << row(stems, source, occurrences) }
        end
        rows
      end

      # The authority is the CELL VALUE, not the column position — the same
      # read the adapter makes. Upstream places its tags loosely ("each
      # source is indicated in the 5, 6 or 7th column", upstream README);
      # whole-file census 2026-07-28: exactly one cell carries a tag outside
      # its own column (ཀེར's PH sits in the TDC column), no row repeats a
      # tag. In-row order (column order) is kept.
      def attesting_sources(record)
        Adapters::TibetanVerbs::SOURCE_COLUMNS.filter_map do |column|
          value = record[column].to_s.strip
          value unless value.empty?
        end
      end

      # The same required-headers contract as the adapter: a silently renamed
      # upstream column fails loudly, never yields nil-filled rows.
      def parser
        Adapters::FlatCsvParser.new(
          required_headers: Adapters::TibetanVerbs::STEM_COLUMNS.values + Adapters::TibetanVerbs::SOURCE_COLUMNS
        )
      end

      def row(stems, source, occurrences)
        occurrence = (occurrences[[stems, source]] += 1)
        {
          "ID" => mint_id(stems, source, occurrence),
          "Language_ID" => LANGUAGE_ID,
          "Lemma" => stems.fetch("Present"),
          "Present" => stems.fetch("Present"),
          "Past" => stems.fetch("Past"),
          "Future" => stems.fetch("Future"),
          "Imperative" => stems.fetch("Imperative"),
          "Analysis_Source" => source,
          "Comment" => (occurrence > 1 ? "upstream restates this (stems, source) row — occurrence #{occurrence}" : nil),
          "Source" => BIB_KEY
        }
      end

      # Deterministic, content-derived, ASCII (Tibetan script cannot survive
      # the CLDF identifier class, so the stem tuple is digested): stable
      # across upstream row reordering; only genuine restatements of the same
      # (stems, source) pair fall back to a positional suffix.
      def mint_id(stems, source, occurrence)
        digest = Digest::SHA256.hexdigest(stems.values.join(SEPARATOR))[0, 12]
        components = ["v", digest, source]
        components << occurrence.to_s if occurrence > 1
        CsvWriter.mint_id(*components)
      end

      def resource(count)
        Resource.new(
          name: "verb-lemma", path: FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end

      # The TVD cited as docs/02-sources.md records it; the CC0 grant noted.
      def citations
        [Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "Tibetan Verbs Database (TVD)",
            "howpublished" => "https://github.com/tibetan-nlp/tibetan-verbs-database",
            "note" => "CC0-1.0 (in-repo LICENSE); source tags TDC/PH/GT/KN are the TVD's own " \
                      "authority abbreviations — see the upstream bibliography for the works behind them"
          }
        )]
      end
    end
  end
end
