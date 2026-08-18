# frozen_string_literal: true

require "csv"
require_relative "store/links_journal"
require_relative "version"

module Nabu
  # The Burman concordance producer (P77-r19; the KyotoKanripo/
  # Trismegistos mold): re-derives same-inscription reference edges from
  # canonical/burman-concordance/burman-concordance.csv after every sync
  # of the instrument. One edge per row that carries BOTH a CIE number
  # (the held open-etruscan corpus's own id scheme → urn cie-<n>, the
  # adapter's slugging) and a Trismegistos number (→ the bare `tm:<id>`
  # identity urns the TrismegistosCrosswalk aggregates) — so `nabu links`
  # answers an Etruscan inscription's whole identity trail, and the tm:
  # hub connects it onward to any other held witness of the same stone.
  # The row's remaining identities (ET1, ET2, TLE, Bakkum, CIL, CII)
  # ride the edge detail verbatim — the concordance line IS the payload.
  #
  # Honesty counters: rows without the CIE+TM pair are counted
  # skipped_unmapped, never guessed (ET-only rows wait for an ET-keyed
  # held corpus). Edges mint independent of catalog presence —
  # dangling-but-stable (the P32-6 doctrine): an open-etruscan doc not
  # yet synced gets its edge the moment it lands.
  class BurmanCrosswalk
    PRODUCER = "burman-concordance"
    KIND = "reference"
    CODE_VERSION = "burman-crosswalk/1 nabu/#{VERSION}".freeze

    CSV_FILENAME = "burman-concordance.csv"
    OPEN_ETRUSCAN_PREFIX = "urn:nabu:open-etruscan:"

    # The identity columns that ride the detail, in the CSV's own order.
    DETAIL_COLUMNS = ["CIE", "Rix. ET1", "Meiser. ET2", "TLE", "Bakkum", "CIL I", "CIL I(2)",
                      "CIL III", "CIL VI", "CIL XI", "CII", "CII Suppl.", "CII App"].freeze

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unmapped)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every concordance edge from the canonical CSV,
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
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unmapped: counts[:unmapped])
    end

    private

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_unmapped: 0)
    end

    def csv_edges(path, counts)
      CSV.foreach(path, col_sep: ";", headers: true).filter_map do |row|
        cie = number(row["CIE"], /\ACIE\s+0*(\d+)\z/)
        tm = number(row["Trismegistos"], /\ATM\s+(\d+)\z/)
        if cie.nil? || tm.nil?
          counts[:unmapped] += 1
          next
        end

        { from: "#{OPEN_ETRUSCAN_PREFIX}cie-#{cie}", to: "tm:#{tm}", detail: detail_for(row) }
      end
    end

    def number(cell, pattern)
      cell.to_s.strip[pattern, 1]
    end

    # The concordance line verbatim: every non-empty identity cell, in
    # column order — the row IS the payload.
    def detail_for(row)
      cells = DETAIL_COLUMNS.filter_map do |column|
        value = row[column].to_s.strip
        value unless value.empty?
      end
      "Burman concordance: #{cells.join(' · ')}"
    end

    def write_edges(edges, run_id, counts)
      edges.each do |edge|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: edge[:from], to_urn: edge[:to],
                    kind: KIND, score: nil, run_id: run_id, detail: edge[:detail]
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end
