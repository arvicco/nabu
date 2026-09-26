# frozen_string_literal: true

require_relative "places"

module Nabu
  # The place-link promotion (P105-4 — Q86's apply lane): project the
  # nabu-places registry's MATCHED kanripo-style decisions onto the mined
  # candidate edges — for each matched name, the place-candidate edges
  # citing the RULED identity promote to kind "place" attestation edges
  # under producer "place-link" (supersede on rerun; `nabu links` reads
  # them back). A homonym candidate the decision does not cite gets
  # nothing; region/rejected/unlocatable decisions promote nothing (they
  # exist to drain the review board, not to claim links).
  #
  # The materialization deliberately stays in the links journal at the
  # passage grain: a text MENTIONING 江北 is not FROM 江北, so
  # document_axes.place_ref (the provenance axis) is never touched —
  # that ladder remains adapter-asserted upstream refs + PlaceApply's
  # place_name projections.
  class PlaceLink
    PRODUCER = "place-link"
    KIND = "place"
    MINE_PRODUCER = Nabu::PlaceMine::PRODUCER
    CANDIDATE_KIND = Nabu::PlaceMine::KIND
    TO_PREFIX = Nabu::PlaceMine::TO_PREFIX
    CODE_VERSION = "place-link/1 nabu/#{VERSION}".freeze

    PAGE = 1_000

    Result = Data.define(:source, :gazetteer, :names, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :run_id, :seconds)

    # +registry+ answers #decisions_for(source) (Nabu::Places or a stub).
    def initialize(catalog:, journal:, registry:, gazetteer:, progress: nil)
      @catalog = catalog
      @journal = journal
      @registry = registry
      @gazetteer = gazetteer
      @progress = progress
    end

    # Promote the current mine's edges for every matched decision whose
    # refs cite this gazetteer. Reruns supersede (the producer discipline).
    def apply!(source:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ruled = ruled_names(source)
      scope = "#{source}:#{@gazetteer}"
      mine_run_ids = @journal[:link_runs]
                     .where(producer: MINE_PRODUCER, scope: scope).select_map(:id)
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @progress&.stage("place-link: promoting #{ruled.size} ruled names for #{scope}")
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: scope)
        run_id = Store::LinksJournal.record_run!(
          @journal, producer: PRODUCER, scope: scope,
                    params: { kind: KIND, gazetteer: @gazetteer }, code_version: CODE_VERSION
        )
        ruled.each do |name, ref|
          promote(name, ref, mine_run_ids, run_id, counts)
        end
      end
      Result.new(source: source, gazetteer: @gazetteer, names: ruled.size,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 run_id: run_id,
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    private

    # {verbatim name => "namespace:id"} for matched decisions citing this
    # gazetteer (a matched decision citing only other namespaces has no
    # candidate edges here — skipped, honestly).
    def ruled_names(source)
      @registry.decisions_for(source).filter_map do |name, decision|
        next unless decision.matched?

        ref = decision.refs.find { |r| r.start_with?("#{@gazetteer}:") }
        [name, ref] if ref
      end.to_h
    end

    def promote(name, ref, mine_run_ids, run_id, counts)
      return if mine_run_ids.empty?

      to_urn = "#{TO_PREFIX}#{ref}"
      written = 0
      @journal[:links]
        .where(kind: CANDIDATE_KIND, run_id: mine_run_ids, to_urn: to_urn,
               detail: "mined 「#{name}」 (#{@gazetteer})")
        .select_map(:from_urn).uniq.each do |from_urn|
          outcome = Store::LinksJournal.write_edge!(
            @journal, from_urn: from_urn, to_urn: to_urn, kind: KIND,
                      score: nil, run_id: run_id,
                      detail: "linked 「#{name}」 → #{ref} (registry decision)"
          )
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
          written += 1
          @progress&.load_tick(written, 0) if (written % PAGE).zero?
        end
    end
  end
end
