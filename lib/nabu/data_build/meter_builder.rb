# frozen_string_literal: true

require "digest"
require "sequel"

require_relative "../errors"
require_relative "../config"
require_relative "../hypotactic_meter"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The grc/meter builder (P52-2) — the flagship fold-in dataset: D.
    # Chamberlain's Hypotactic scansions (CC BY 4.0) published as rows
    # citable at urn:cts:greekLit grain. Upstream has NO citation scheme
    # (work = filename, line = file order); the URN + Passage_SHA256
    # anchoring Nabu derives by exact folded-text match IS the added value.
    #
    # == The license rule this class is built around (the audit's load-bearing
    # design decision)
    #
    # Primary_Text is ALWAYS the Greek line from Hypotactic's own TSV bytes —
    # NEVER the held passage's text. Perseus and First1KGreek are CC BY-SA
    # 4.0: embedding their bytes would contaminate this CC BY 4.0 dataset.
    # The exact-fold resolution makes the two texts equal LETTER-wise, but
    # not byte-wise (elision spelling, final punctuation differ), and the
    # provenance of the published bytes must be Hypotactic's TSV either way.
    # Anchoring into the BY-SA corpora is by URN + passage content sha only —
    # facts about where the line lives, not expression from it.
    #
    # == Read paths
    #
    # canonical/hypotactic/tsv/*.tsv through the SAME grammar and fold the
    # HypotacticMeter enrichment producer uses (its public class-level
    # seams — one definition, zero drift), matched against the live grc
    # passages of the declared anchor corpora in the catalog. The builder
    # contract passes no config, so the canonical dir resolves through
    # Nabu::Config.load (the same env-honoring path the CLI used to build
    # the Runner's config); tests inject a fixture tree via the constructor
    # seam (the segmentation kangyur_slice precedent).
    #
    # All three inputs (hypotactic + the two anchor corpora) are declared in
    # the registry, so the Runner's stale-ingest guard refuses the build
    # whenever ANY of them drifted from what the catalog last ingested —
    # Passage_SHA256 anchors are only honest against the recorded cones.
    class MeterBuilder
      HYPOTACTIC_SLUG = "hypotactic"
      # The corpora whose passages the scansions anchor into — the catalog
      # query is restricted to these slugs so the registry's declared inputs
      # are honest by construction (no undeclared source can leak anchors in).
      ANCHOR_SOURCE_SLUGS = %w[perseus-greek first1k-greek].freeze

      CSV_FILENAME = "meter.csv"
      COLUMNS = %w[ID URN Passage_SHA256 Primary_Text Meter Pattern Caesura Tier Source].freeze

      WORKS_FILENAME = "works.csv"
      WORKS_COLUMNS = %w[ID Filename Work URN_Prefix Source].freeze
      WORKS_PRIMARY_KEY = %w[Filename Work].freeze

      TIER = "gold-derived"
      BIB_KEY = "hypotactic"

      # Part of the derivation fingerprint: changing the resolution, the
      # dedup rule, or the provenance rule MUST change this string.
      RECIPE = "grc/meter v1: resolve every line of canonical/hypotactic/tsv/*.tsv (D. " \
               "Chamberlain's Greek scansions; the file NAME carries the work via the curated " \
               "filename→CTS crosswalk published as works.csv — upstream has no citation " \
               "column) onto the held live grc passages of perseus-greek + first1k-greek by " \
               "EXACT folded-text match (the house grc search-form fold reduced to letters " \
               "only; no fuzzy matching — unmatched lines are censused in nabu.eval, never " \
               "guessed); one row per anchored passage (Homer's verbatim formulaic repeats " \
               "dedupe to the first-held occurrence; a repeated line still counts as matched); " \
               "Primary_Text carries Hypotactic's own TSV line bytes (CC BY 4.0), NEVER the " \
               "Perseus/First1K passage bytes (those corpora are CC-BY-SA — anchoring is by " \
               "URN + Passage_SHA256 only, so no share-alike text enters this CC BY dataset)."

      def initialize(canonical_dir: nil)
        @canonical_dir = canonical_dir
      end

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "grc/meter reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        files = tsv_files
        census, rows = resolve(catalog, files)
        if rows.empty?
          raise Error, "no Hypotactic line matched a held greekLit passage — ingest the anchor " \
                       "corpora (bin/nabu sync perseus-greek, bin/nabu sync first1k-greek) " \
                       "before building grc/meter"
        end

        meter_count = CsvWriter.write(path: File.join(out_dir, CSV_FILENAME), columns: COLUMNS,
                                      rows: rows.sort_by { |row| row["URN"] })
        works = works_rows
        CsvWriter.write(path: File.join(out_dir, WORKS_FILENAME), columns: WORKS_COLUMNS, rows: works)

        BuildResult.new(resources: [meter_resource(meter_count), works_resource(works.size)],
                        recipe: RECIPE, citations: citations, notes: notes(census),
                        evaluation: census)
      end

      private

      # -- canonical read -----------------------------------------------------

      def canonical_dir
        @canonical_dir ||= Nabu::Config.load.canonical_dir
      end

      def tsv_files
        dir = File.join(canonical_dir, HYPOTACTIC_SLUG, Nabu::HypotacticMeter::DIRNAME)
        files = Dir.glob(File.join(dir, "*.tsv"))
        if files.empty?
          raise Error, "canonical/hypotactic has no tsv/ scansion files (#{dir}) — " \
                       "sync hypotactic (bin/nabu sync hypotactic) before building grc/meter"
        end
        files
      end

      # -- resolution ---------------------------------------------------------

      # The HypotacticMeter resolution, re-run for publication: same grammar,
      # same fold, same WORK_MAP, same census semantics (a malformed file is
      # censused by name, an unmapped or unheld work censuses its whole line
      # count as unmatched, a mapped work is one that resolved ≥1 line) —
      # with the passage query additionally restricted to live rows of the
      # declared anchor sources, because a publication must not cite a
      # withdrawn passage or an undeclared input.
      def resolve(catalog, files)
        counts = Hash.new(0)
        malformed = []
        rows = []
        written = {}
        index_cache = {}
        files.each do |path|
          begin
            parsed = Nabu::HypotacticMeter.parse_tsv(path)
          rescue ParseError
            malformed << File.basename(path)
            next
          end
          counts[:lines] += parsed.size
          work = Nabu::HypotacticMeter::WORK_MAP[File.basename(path, ".tsv")]
          index = work ? (index_cache[work] ||= held_line_index(catalog, work)) : {}
          before = counts[:matched]
          parsed.each do |line|
            resolve_line(line, index, counts, rows, written)
          end
          counts[counts[:matched] > before ? :mapped_works : :unmapped_works] += 1
        end
        [census(counts, files, malformed, rows.size), rows]
      end

      def resolve_line(line, index, counts, rows, written)
        held = index[Nabu::HypotacticMeter.match_key(line[:text])]
        if held
          counts[:matched] += 1
          return if written[held[:urn]]

          written[held[:urn]] = true
          rows << csv_row(held, line)
        else
          counts[:unmatched] += 1
        end
      end

      # { fold-key => { urn:, sha: } } over the live grc passages of every
      # held edition of the mapped work(s) — a WORK_MAP value verbatim (one
      # work id, an array, or a bare textgroup: the urn LIKE prefix covers
      # all three). Ordered by passage id so first-occurrence-wins is
      # deterministic; memoized per map value (the 24 per-book Homer files
      # share one index).
      def held_line_index(catalog, works)
        likes = Array(works).map { |work| Sequel.like(Sequel[:documents][:urn], "urn:cts:greekLit:#{work}.%") }
        index = {}
        held_line_rows(catalog, likes).each do |row|
          key = Nabu::HypotacticMeter.match_key(row[:text])
          index[key] ||= { urn: row[:urn], sha: row[:content_sha256] } unless key.empty?
        end
        index
      end

      def held_line_rows(catalog, likes)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:sources][:slug] => ANCHOR_SOURCE_SLUGS)
          .where(Sequel.|(*likes))
          .where(Sequel[:passages][:language] => Nabu::HypotacticMeter::MATCH_LANGUAGE)
          .order(Sequel[:passages][:id])
          .select(Sequel[:passages][:urn], Sequel[:passages][:text],
                  Sequel[:passages][:content_sha256])
          .all
      end

      # One anchored row. Primary_Text is line[:text] — the TSV's bytes, the
      # class-note license rule: the held passage's text NEVER enters the
      # dataset; the passage contributes only its URN and content sha.
      def csv_row(held, line)
        {
          "ID" => CsvWriter.mint_id("m", Digest::SHA256.hexdigest(held[:urn])[0, 12]),
          "URN" => held[:urn],
          "Passage_SHA256" => held[:sha],
          "Primary_Text" => line[:text],
          "Meter" => line[:meter],
          "Pattern" => line[:scansion],
          "Caesura" => line[:caesura],
          "Tier" => TIER,
          "Source" => BIB_KEY
        }
      end

      # -- the crosswalk sidecar ----------------------------------------------

      # The WORK_MAP published as data: one row per (filename, work) pair,
      # URN_Prefix documenting the exact resolution grain (a bare textgroup
      # value resolves every held work under it — the trailing dot is the
      # LIKE prefix verbatim).
      def works_rows
        pairs = Nabu::HypotacticMeter::WORK_MAP.flat_map do |filename, works|
          Array(works).map do |work|
            { "ID" => CsvWriter.mint_id("w", filename, work), "Filename" => filename,
              "Work" => work, "URN_Prefix" => "urn:cts:greekLit:#{work}.", "Source" => BIB_KEY }
          end
        end
        pairs.sort_by { |row| [row["Filename"], row["Work"]] }
      end

      # -- census -------------------------------------------------------------

      # The honesty stat, published verbatim as nabu.eval (the segmentation
      # precedent): how many upstream lines resolved, how many did not.
      def census(counts, files, malformed, passages)
        lines = counts[:lines]
        {
          "files" => files.size,
          "lines_read" => lines,
          "matched_lines" => counts[:matched],
          "unmatched_lines" => counts[:unmatched],
          "match_rate" => lines.zero? ? 0.0 : (counts[:matched].to_f / lines).round(4),
          "mapped_works" => counts[:mapped_works],
          "unmapped_works" => counts[:unmapped_works],
          "passages" => passages,
          "malformed_files" => malformed,
          "against" => "held live grc passages of perseus-greek + first1k-greek, exact " \
                       "folded-text match (no fuzzy matching — an unmatched line is censused, " \
                       "never guessed into a false anchor)"
        }
      end

      # -- furniture ----------------------------------------------------------

      def meter_resource(count)
        Resource.new(
          name: "meter", path: CSV_FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end

      def works_resource(count)
        Resource.new(
          name: "works", path: WORKS_FILENAME, rows: count,
          fields: WORKS_COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: WORKS_PRIMARY_KEY
        )
      end

      # Chamberlain's reference expectation (the mirror README's ask, already
      # honored in every enrichment payload) is honored here in the citation
      # the Source column points at; the anchor corpora are cited as anchor
      # TARGETS — no text of theirs is included.
      def citations
        [
          Citation.new(
            key: BIB_KEY, type: "misc",
            fields: {
              "author" => "Chamberlain, David",
              "title" => "Hypotactic — metrical scansions of Greek and Latin verse",
              "howpublished" => "https://hypotactic.com (mirror: https://github.com/Urdatorn/hypotactic)",
              "note" => "CC BY 4.0 (the mirror repository). Chamberlain asks that significant " \
                        "or extensive published use reference him (David Chamberlain) and " \
                        "hypotactic.com — this dataset is that reference."
            }
          ),
          Citation.new(
            key: "perseus-greek", type: "misc",
            fields: {
              "title" => "Perseus Digital Library — canonical Greek literature",
              "howpublished" => "https://github.com/PerseusDL/canonical-greekLit",
              "note" => "CC BY-SA 4.0; anchor target only — rows cite its passages by URN and " \
                        "content sha, no Perseus text is included in this dataset"
            }
          ),
          Citation.new(
            key: "first1k-greek", type: "misc",
            fields: {
              "title" => "Open Greek and Latin — First1KGreek",
              "howpublished" => "https://github.com/OpenGreekAndLatin/First1KGreek",
              "note" => "CC BY-SA 4.0; anchor target only — rows cite its passages by URN and " \
                        "content sha, no First1KGreek text is included in this dataset"
            }
          )
        ]
      end

      def notes(census)
        malformed = census.fetch("malformed_files")
        malformed_note = malformed.empty? ? "" : "; malformed: #{malformed.join(', ')}"
        <<~NOTES.strip
          ## What a row means — the anchoring contract

          Each row anchors one of Hypotactic's expert scansions to one held Greek
          line: `URN` names the CTS passage, `Passage_SHA256` the exact bytes of
          that passage in the corpus it was derived against. Rows apply only where
          the passage sha matches — if a corpus edition moves, re-derive rather
          than trust stale anchors. `Primary_Text` is the Greek line **from
          Hypotactic's own CC BY 4.0 TSV** — deliberately never the Perseus/First1K
          passage bytes, because those corpora are CC BY-SA and this dataset is
          CC BY: the anchor is a fact (URN + sha), the text is Chamberlain's.
          `Meter`/`Pattern`/`Caesura` are the TSV's own columns verbatim (the
          caesura cell is empty when the line carries none).

          ## The crosswalk sidecar

          Upstream files carry no citation scheme (work = filename, line = file
          order). `works.csv` publishes the curated filename→CTS crosswalk this
          dataset resolves through — own curation, factual id maps; `URN_Prefix`
          is the exact resolution grain (a bare textgroup prefix spans every held
          work under it).

          ## The resolution census — the honesty stat

          #{census.fetch('matched_lines')} of #{census.fetch('lines_read')} upstream lines
          (#{format('%.2f%%', census.fetch('match_rate') * 100)}) resolved onto
          #{census.fetch('passages')} held passages
          (#{census.fetch('mapped_works')} works matched, #{census.fetch('unmapped_works')} files
          unmatched#{malformed_note});
          #{census.fetch('unmatched_lines')} lines found no held passage and are
          censused, never guessed. Matching is exact on the folded letter sequence
          (accents/breathings/punctuation/elision spelling neutralized) — the same
          numbers ride `datapackage.json` under `nabu.eval`.

          ## Loading

              import pandas as pd
              df = pd.read_csv("meter.csv", keep_default_na=False)

          How to cite: reference David Chamberlain and hypotactic.com (the
          `hypotactic` key in `sources.bib`) alongside this dataset's
          `datapackage.json` provenance block.
        NOTES
      end
    end
  end
end
