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
    #     per such write, announced and ticked. Not O(Δ) for being
    #     triggered by a delta: an `index refresh` forecasts the shadow it
    #     will pay and prices it before the writer starts
    #     (Indexer.fts_shadow_forecasts, IndexPreflight's shadow note).
    #   - RAIL: corpus-scale work owned by the maintenance rail
    #     (`nabu index maintain`), never the sync path.
    #   - SOURCE: O(source) — a lane with no delta grain re-derives the
    #     refreshed source's WHOLE slice on every refresh (bounded by that
    #     one source, never the corpus). Not O(Δ): declared so the
    #     exemption is visible rather than silent, and outside the
    #     empirical O(Δ) suite by construction.
    module IndexCostClasses
      DELTA = :delta
      REGISTRY = :registry
      ARRIVAL = :arrival
      RAIL = :rail
      SOURCE = :source

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
        # The passages_fts in-place write paths (Indexer::REWRITE_CEILING
        # note): the append-only tail write of a run that deletes nothing,
        # and the delete + append of one at or under the ceiling — each
        # with its eager consolidation, sized by the rows the run touches.
        "fts_append" => DELTA,
        "fts_rewrite" => DELTA,
        # Past REWRITE_CEILING (passages_fts) / IN_PLACE_ROW_BUDGET
        # (trigram): the append-only shadows.
        "fts_shadow" => ARRIVAL,
        "trigram_shadow" => ARRIVAL,
        # The merge governor's relief (Indexer::FtsGovernor): fires only
        # when a level (or the total) crosses the governor's line, once
        # per crossing, sized by that level's pages — recorded with them
        # so the ledger prices a big write's relief debt.
        "fts_relief" => ARRIVAL,
        # A bulk slice's final WAL reclaim (TRUNCATE checkpoint): fires only
        # on a run past BULK_SLICE_THRESHOLD, sized by the WAL that write
        # left — rows = the frames it checkpointed.
        "wal_checkpoint" => ARRIVAL,
        # The tail lanes' slices (refresh_source!), recorded only when the
        # lane did work (a source outside its registry is hands-off). The
        # clarify slice rewrites the source's names whole; the token-gloss
        # lane aggregates word rows across the source's passages, so it has
        # no delta grain either. Translations / annotations / gloss lines
        # ride the load's delta (their whole-slice rewrite is the fallback,
        # as index_slice's is).
        "clarify_slice" => SOURCE,
        "glosses_slice" => SOURCE,
        "translations_slice" => DELTA,
        "annotations_slice" => DELTA,
        "gloss_lines_slice" => DELTA
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
