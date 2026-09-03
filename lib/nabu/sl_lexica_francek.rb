# frozen_string_literal: true

require "nokogiri"

module Nabu
  # Producer #8 for the links journal (P95-2 — the Franček crosswalk
  # rider the P17-6 survey sketched and Q33 carried): the Franček
  # portal's historical module (CLARIN.SI hdl 11356/1472, CC BY 4.0,
  # ZRC SAZU) keys 41,886 portal entries into the id spaces of the HELD
  # sl-lexica dictionaries — Pleteršnik (rc/@geslo-id) and the Svetokriški
  # JSV (ge/@geslo-id) — and carries 16th-century Protestant FIRST
  # ATTESTATIONS (author/title/year) for ~8k of them.
  #
  # == What lands (v1, the held-target rule)
  #
  # One kind=reference edge per Pleteršnik×JSV pairing within an FR-Z
  # entry (3,567 pairs censused 2026-09-04) — the two dictionaries'
  # entries for the same word, joined on the portal's own identity. When
  # the entry also carries a Protestant attestation, the earliest record
  # rides the edge detail ("first attested: Primož Trubar, Katekizem,
  # 1550") — the crosswalk's philological payoff. Entries keyed into
  # only ONE held space mint nothing (an edge needs two ends), and the
  # geslo-prot/FR-Z-KV id spaces are the portal's own, not held
  # dictionaries — recorded here, never minted as urns (the P19-4 bar).
  #
  # The module file arrives as sl-lexica's fourth fetch artifact
  # (<workdir>/francek/FR-zgodovina.xml); like every producer, edges are
  # a pure function of (canonical, code) — reruns supersede, rebuild
  # never touches the journal.
  class SlLexicaFrancek
    PRODUCER = "sl-lexica"
    KIND = "reference"
    CODE_VERSION = "sl-lexica-francek/1 nabu/#{VERSION}".freeze

    MODULE_PATH = File.join("francek", "FR-zgodovina.xml").freeze

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive the crosswalk from the fetched module file, superseding
    # the prior (producer, scope) run atomically. A workdir without the
    # module (pre-refetch trees) supersedes to zero edges honestly.
    def run(slug, workdir: nil)
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      pairs = workdir ? crosswalk_pairs(File.join(workdir, MODULE_PATH)) : []
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        pairs.each do |pair|
          write_edge(run_id, pair, counts)
        end
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1])
    end

    private

    def crosswalk_pairs(path)
      return [] unless File.file?(path)

      doc = Nokogiri::XML(File.read(path), &:strict)
      doc.xpath("//FR-Z").flat_map { |entry| entry_pairs(entry) }
    rescue Nokogiri::XML::SyntaxError => e
      raise Nabu::Error, "francek module #{path}: malformed XML: #{e.message}"
    end

    def entry_pairs(entry)
      plet = entry.xpath(".//FR-Z-Plet/rc/@geslo-id").map(&:value)
      svet = entry.xpath(".//FR-Z-Svet/ge/@geslo-id").map(&:value)
      attestation = first_attestation(entry)
      plet.product(svet).map do |plet_id, svet_id|
        {
          from: "urn:nabu:dict:pletersnik:#{plet_id}",
          to: "urn:nabu:dict:jsv:#{svet_id}",
          fr: entry["fr-sklic"],
          attestation: attestation
        }
      end
    end

    # The earliest Protestant attestation record, rendered legibly.
    def first_attestation(entry)
      records = entry.xpath(".//FR-Z-Prot//zapis").map do |zapis|
        {
          year: zapis.at_xpath("leto")&.text.to_i,
          text: [zapis.at_xpath("avtor")&.text, zapis.at_xpath("naslov")&.text,
                 zapis.at_xpath("leto")&.text].compact.reject(&:empty?).join(", ")
        }
      end
      records.reject { |r| r[:year].zero? }.min_by { |r| r[:year] }&.fetch(:text)
    end

    def write_edge(run_id, pair, counts)
      detail = "Franček #{pair[:fr]}"
      detail += "; first attested: #{pair[:attestation]}" if pair[:attestation]
      outcome = Store::LinksJournal.write_edge!(
        @journal, from_urn: pair[:from], to_urn: pair[:to], kind: KIND,
                  score: nil, run_id: run_id, detail: detail
      )
      counts[outcome == :inserted ? :inserted : :refreshed] += 1
    end
  end
end
