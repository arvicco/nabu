# frozen_string_literal: true

module Nabu
  module Store
    # The proportionality law's DECLARATION side (architecture §1; the
    # incrementality review, R1): every timed indexing stage names its
    # cost class here, and the stage timers refuse an undeclared name
    # (Indexer.timed_sync_stage, IndexMaintenance.timed). A new stage
    # cannot ship without the question "what does this scale with?" being
    # asked and answered in code — RC-A of the review ("incrementality was
    # never an enforced contract") closed at the point of entry.
    #
    # The classes:
    #
    #   - DELTA: O(Δ) — the wall time scales with what the load changed,
    #     never with the source or the corpus. The suite's invariant
    #     (test/index_proportionality_test.rb) measures every DELTA stage
    #     across two source sizes under a constant delta and fails when its
    #     time follows the source.
    #   - REGISTRY: bounded by a curated registry's size (the crosswalk a
    #     dictionary sync re-walks) — neither the corpus nor the delta,
    #     declared so the exemption is visible rather than silent.
    #   - ARRIVAL: O(source)/O(corpus), but an arrival event BY
    #     CONSTRUCTION — it fires only on the size of the write that
    #     triggers it (the shadow builds past the in-place budget), once
    #     per such write, announced and ticked.
    #   - RAIL: corpus-scale work owned by the maintenance rail
    #     (`nabu index maintain`), never the sync path.
    module IndexCostClasses
      DELTA = :delta
      REGISTRY = :registry
      ARRIVAL = :arrival
      RAIL = :rail

      # The sync path's timed stages (kind "sync" in the stage ledger).
      SYNC = {
        # The fts+lemma slice unit at the delta grain — the slice rewrite
        # and the heal are its fallbacks (the full-slice path is the
        # source's own rewrite, priced by the preflight from the ledger).
        "index_slice" => DELTA,
        # The postings/coverage tail: the alignment refresh (registry-scoped)
        # and the missing-table bootstraps, which fire once per absent table.
        "postings_swaps" => DELTA,
        # ONE bounded probe chunk per governed table (Indexer::SYNC_PROBE_CHUNKS).
        "fts_merge" => DELTA,
        # The closure moved by the gold languages that crossed zero.
        "reflex_closure" => DELTA,
        # A dictionary sync's closure re-walk: O(crosswalk).
        "reflex_rewalk" => REGISTRY,
        # Past IN_PLACE_ROW_BUDGET: the append-only shadows.
        "fts_shadow" => ARRIVAL,
        "trigram_shadow" => ARRIVAL
      }.freeze

      # Every stage the maintenance rail times is rail-owned by definition.
      RAIL_KINDS = %w[maintain].freeze

      class UndeclaredStage < Nabu::Error; end

      module_function

      # The declared class of (+kind+, +stage+); raises UndeclaredStage for
      # a stage nobody declared.
      def for(kind, stage)
        return RAIL if RAIL_KINDS.include?(kind)

        SYNC.fetch(stage) do
          raise UndeclaredStage, "index stage #{stage.inspect} (kind #{kind}) declares no cost class — add it to " \
                                 "Store::IndexCostClasses with what its wall time scales with"
        end
      end

      def delta_stages = SYNC.select { |_, cost| cost == DELTA }.keys
    end
  end
end
