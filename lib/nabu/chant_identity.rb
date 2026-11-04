# frozen_string_literal: true

require "json"

module Nabu
  # The chant-identity link layer (the liturgy wave, 2026-11-04): GregoBase's
  # modern chant transcriptions and the Cantus Database's manuscript chant
  # records share one key — the Cantus ID, the Cantus Index network's
  # identifier that names the SAME chant across witnesses. Both adapters mint
  # it verbatim into document metadata under "cantus_id" (GregoBase from its
  # dump's own column, 2,676 of 18,422 docs at the first sync; Cantus on every
  # record), so each (gregobase document, cantus record) pair sharing an id
  # becomes a kind=chant-identity edge, and `nabu links` follows an antiphon
  # from its St Gall attestation to its modern Solesmes-book transcription
  # from either side. No new registry, no new table: the shared key IS the
  # layer (the design the adoption named).
  #
  # == Edge shape and grain
  #
  # from_urn = the gregobase document (the asserting side: the curated
  # transcription that cites the id to say "this chant"); to_urn = each
  # cantus record carrying the same id; score nil (a shared curated
  # identifier is not a mined similarity); detail = "the same chant —
  # Cantus ID <id>". Document grain on both sides: a chant is one document
  # in each shelf. The join is deliberately gregobase × cantus, never
  # cantus × cantus — the pairwise closure inside one id (a popular
  # antiphon sits in 200+ manuscripts) asserts nothing the shared key does
  # not already say, at quadratic cost. First-sync census (2026-11-04):
  # 2,676 keyed gregobase docs → 71,032 edges (max fan-out 232); the 196
  # docs whose id no cantus record carries mint nothing and are counted
  # (+skipped_unmatched+ — ids exist in the wider Cantus Index network
  # beyond the database's 305 inventoried sources, an honest miss).
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (loaded gregobase rows, loaded cantus
  # rows, code), so BOTH adapters register this producer on the
  # reference_producer seam and either sync re-derives the layer whole:
  # the run is pinned to the one SCOPE below regardless of the triggering
  # slug, superseding the prior run atomically (two scopes would duplicate
  # the layer). A catalog missing either side mints what it honestly can:
  # no gregobase rows → the no-op that supersedes nothing; gregobase
  # without cantus → every keyed doc counts as unmatched. Rebuild never
  # touches the journal; losing it costs one parse-only re-sync.
  class ChantIdentity
    PRODUCER = "chant-identity"
    SCOPE = "chant"
    KIND = "chant-identity"
    CODE_VERSION = "chant-identity/1 nabu/#{VERSION}".freeze

    # The LibraryReferences::Result shape (the CLI sync tail renders every
    # producer identically) plus the honesty counter from the class note.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unmatched)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive the whole layer from the catalog's keyed documents,
    # superseding the prior run. +slug+ names the triggering sync only
    # (class note: the scope is pinned); +workdir+ rides the seam unused.
    def run(_slug, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      keyed = keyed_rows("gregobase")
      return absent_result if keyed.empty?

      targets = cantus_targets
      counts = Hash.new(0)
      edges = keyed.flat_map do |urn, cantus_id|
        rows = targets.fetch(cantus_id, nil)
        if rows.nil?
          counts[:unmatched] += 1
          []
        else
          rows.map { |to_urn| { from: urn, to: to_urn, detail: "the same chant — Cantus ID #{cantus_id}" } }
        end
      end
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: SCOPE)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: SCOPE,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: SCOPE, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unmatched: counts[:unmatched])
    end

    private

    def absent_result
      Result.new(scope: SCOPE, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_unmatched: 0)
    end

    # Non-withdrawn documents of +slug+ carrying a cantus_id, urn-ordered
    # for determinism: [urn, cantus_id] pairs.
    def keyed_rows(slug)
      @catalog[:documents]
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn])
        .select_map([Sequel[:documents][:urn], Sequel[:documents][:metadata_json]])
        .filter_map do |urn, metadata_json|
          id = metadata_json && JSON.parse(metadata_json)["cantus_id"]
          [urn, id.to_s] if id && !id.to_s.empty?
        end
    end

    # cantus_id → [cantus record urns], urn-ordered inside each id.
    def cantus_targets
      keyed_rows("cantus").each_with_object({}) do |(urn, id), map|
        (map[id] ||= []) << urn
      end
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
