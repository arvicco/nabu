# frozen_string_literal: true

require "csv"
require_relative "../store/links_journal"
require_relative "../version"
require_relative "source_read"

module Nabu
  module Adapters
    # The CLLG SC↔TLG alignment producer: the Sources Chrétiennes corpus's
    # own sc_tlg.csv (upstream README: "produced once by the sc-tlg-align
    # Claude skill … every link was checked by an agent") re-derived into
    # links-journal edges after every cllg-sc sync, through the adapter's
    # reference seam (the KyotoKanripoCrosswalk shape — a TEXT source whose
    # canonical tree also ships a crosswalk file; Burman/Trismegistos for
    # the identity hub). Lives under adapters/ (the MvpCrosswalk placement)
    # so its edits dirty only the cllg-sc stamp.
    #
    # == The file (census over the 219176d8 clone, 2026-11-13)
    #
    # 243 rows, columns sc,source,tlg,urn,path,added,tlg_title,verdict,
    # evidence,here: one SC volume (`sc`, "132", "1 bis") aligned to one TLG
    # work (`tlg`, "2042.001" — all 243 well-formed). `source` irvine (124:
    # the work is in the freed TLG corpus, its edition urn in `urn` —
    # urn:cts:…cllg-grc1, a cllg-freed document) or tlg-online (119: TLG
    # online only, no free text). `here` (185) is the SC corpus's own
    # edition urn of that volume — the held cllg-sc document; 58 rows carry
    # none (the volume is not in the corpus). `verdict` same-edition (217),
    # same-text-other-edition (23), urn-clash (3).
    #
    # == Edges (two families, one run)
    #
    # For every row with a `here` urn:
    #   - here → tlg:<tlg> (kind=reference) — the TLG work identity, the
    #     compact external-id hub of the house (tm:<id>, phi:, cil: …), in
    #     upstream's own "NNNN.NNN" spelling. It is the ONLY bridge for the
    #     tlg-online rows (no free text) and for SC works whose urn is not a
    #     TLG id (tlg4090.cllg001 → TLG 4090.177/178/179), which CTS sibling
    #     resolution (suffix equality) can never find.
    #   - here → urn (kind=parallel-witness, the CopticWitnesses kind: same
    #     text, other witness, documents never merged) when the row names a
    #     freed edition — the SC (Cerf) and TLG editions of one work.
    # Rows sharing an edge pair (one SC document spanning several volumes —
    # Contra Celsum is SC 132/136/147/150) merge onto ONE edge, each row's
    # "SC <sc> ↔ TLG <tlg> <title> · <verdict> (<source>) · <evidence>"
    # joined by " | " in file order — the alignment rows ARE the payload.
    #
    # Skipped and counted, never guessed: rows without `here` or with a
    # malformed `tlg` (+skipped_unmapped+), and upstream's own `urn-clash`
    # verdict rows (+skipped_clash+) — their `here` names the freed urn the
    # SC file carried before its rename to sc-cllg-grc1; each has a
    # companion row with the current urn, which carries the pairing.
    # Edges mint independent of catalog presence (dangling-but-stable, the
    # P32-6 doctrine).
    #
    # Over the census clone: 182 aligned rows → 135 identity edges + 78
    # witness edges = 213 edges (58 unmapped, 3 clash), from 130 distinct
    # SC documents — all 130 held cllg-sc documents in the live catalog
    # (2026-11-13). 71 of the 78 freed witness targets are held; the other
    # 7 name files cllg-freed skips by rule (no citeStructure) and resolve
    # the day upstream declares a tree.
    class CllgTlgAlignment
      PRODUCER = "cllg-sc-tlg"
      IDENTITY_KIND = "reference"
      WITNESS_KIND = "parallel-witness"
      CODE_VERSION = "cllg-tlg-alignment/1 nabu/#{VERSION}".freeze

      CSV_FILENAME = "sc_tlg.csv"
      CLASH = "urn-clash"
      TLG_ID = /\A\d{4}\.\d{3}\z/

      Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                           :superseded_runs, :superseded_edges, :rows,
                           :skipped_unmapped, :skipped_clash, :identity_edges, :witness_edges)

      def initialize(catalog:, journal:)
        @catalog = catalog
        @journal = journal
      end

      # Re-derive every alignment edge from <workdir>/sc_tlg.csv,
      # superseding the prior (producer, scope) run. A workdir without the
      # CSV is the honest no-op (pre-first-sync).
      def run(slug, workdir: nil)
        path = workdir && File.join(workdir, CSV_FILENAME)
        return absent_result(slug) unless path && File.file?(path)

        counts = Hash.new(0)
        edges = csv_edges(path, counts)
        run_id = superseded = nil
        @journal.transaction do
          superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
          run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                             params: { kinds: [IDENTITY_KIND, WITNESS_KIND] },
                                                             code_version: CODE_VERSION)
          write_edges(edges, run_id, counts)
        end
        Result.new(scope: slug, run_id: run_id, edges_written: counts[:inserted],
                   edges_refreshed: counts[:refreshed], superseded_runs: superseded[0],
                   superseded_edges: superseded[1], rows: counts[:rows],
                   skipped_unmapped: counts[:unmapped], skipped_clash: counts[:clash],
                   identity_edges: counts[IDENTITY_KIND], witness_edges: counts[WITNESS_KIND])
      end

      private

      def absent_result(slug)
        Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0, superseded_runs: 0,
                   superseded_edges: 0, rows: 0, skipped_unmapped: 0, skipped_clash: 0,
                   identity_edges: 0, witness_edges: 0)
      end

      # [from, to, kind] => [row lines], file order (Hash insertion order —
      # determinism).
      def csv_edges(path, counts)
        text = SourceRead.utf8_file(path, label: "cllg-sc #{CSV_FILENAME}")
        CSV.parse(text, headers: true).each_with_object({}) do |row, edges|
          counts[:rows] += 1
          here = cell(row, "here")
          tlg = cell(row, "tlg")
          if cell(row, "verdict") == CLASH
            counts[:clash] += 1
          elsif here.nil? || !TLG_ID.match?(tlg.to_s)
            counts[:unmapped] += 1
          else
            line = row_line(row)
            (edges[[here, "tlg:#{tlg}", IDENTITY_KIND]] ||= []) << line
            freed = cell(row, "urn")
            (edges[[here, freed, WITNESS_KIND]] ||= []) << line if freed && freed != here
          end
        end
      end

      def cell(row, column)
        value = row[column].to_s.strip
        value unless value.empty?
      end

      def row_line(row)
        "SC #{cell(row, 'sc')} ↔ TLG #{cell(row, 'tlg')} #{cell(row, 'tlg_title')} · " \
          "#{cell(row, 'verdict')} (#{cell(row, 'source')}) · #{cell(row, 'evidence')}"
      end

      def write_edges(edges, run_id, counts)
        edges.each do |(from, to, kind), lines|
          outcome = Store::LinksJournal.write_edge!(@journal, from_urn: from, to_urn: to, kind: kind,
                                                              score: nil, run_id: run_id,
                                                              detail: lines.uniq.join(" | "))
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
          counts[kind] += 1
        end
      end
    end
  end
end
