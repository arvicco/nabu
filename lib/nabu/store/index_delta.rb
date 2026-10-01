# frozen_string_literal: true

module Nabu
  module Store
    # The per-load index delta (P112-1, Q112). The loader already decides
    # every passage's fate by content sha; this collector captures those
    # fates as id/urn sets so the indexer can refresh exactly what changed
    # instead of rewriting the source's whole slice (the measured
    # pathology: an 8.9M-row cbeta rewrite serving a 35-document heal).
    #
    # Semantics — the sets describe movement in and out of the LIVE
    # passage set (the two-level visibility rule):
    # - +upserted+: rows whose indexed form must be (re)written — inserts,
    #   content revisions, restores, and EVERY live passage of a document
    #   re-entering the live set (its unchanged passages left the index at
    #   withdrawal, so re-entry re-indexes them all).
    # - +removed+: rows leaving the live set — passage withdrawals and the
    #   full-load document sweep.
    # Metadata/license/retirement reconciles move nothing and never land
    # here (retired documents stay indexed — architecture §8).
    #
    # Staging: per-document mutations run inside a transaction (or
    # savepoint) that can roll back while the batch continues, so call
    # sites stage first and the loader commits on success / discards on
    # the rescued constraint error. Mutations outside the per-document
    # grain (the withdrawal sweep — its own transaction; a failure there
    # aborts the whole load, so no report escapes with a half-recorded
    # sweep) commit immediately via the bang-less public pair.
    #
    # Overflow: past +cap+ total entries the delta frees its sets and
    # reports overflowed? — the indexer falls back to the slice rewrite,
    # which at that volume costs the same. A rebuild-scale load through
    # Store::Loader therefore carries a few hundred KB at worst, never
    # millions of ids.
    class IndexDelta
      CAP = 250_000

      attr_reader :upserted_ids, :removed_ids, :upserted_urns, :removed_urns

      def initialize(cap: CAP)
        @cap = cap
        @upserted_ids = Set.new
        @removed_ids = Set.new
        @upserted_urns = Set.new
        @removed_urns = Set.new
        @staged = []
        @overflowed = false
      end

      def stage_upsert(id, urn) = stage(:upsert, id, urn)
      def stage_remove(id, urn) = stage(:remove, id, urn)

      def upsert(id, urn) = apply(:upsert, id, urn)
      def remove(id, urn) = apply(:remove, id, urn)

      def commit!
        @staged.each { |kind, id, urn| apply(kind, id, urn) }
        @staged.clear
      end

      def discard! = @staged.clear

      def overflowed? = @overflowed

      # Empty means NOTHING moved — distinct from overflowed, where the
      # movement is real but uncounted (a skip on overflow would freeze
      # real staleness in place).
      def empty? = !@overflowed && @upserted_ids.empty? && @removed_ids.empty?

      def size = @upserted_ids.size + @removed_ids.size

      # The union views the indexer deletes by (every touched row's old
      # index entry goes) and scopes lemma work with.
      def changed_ids = @upserted_ids | @removed_ids
      def changed_urns = @upserted_urns | @removed_urns

      # The report is a frozen value; freezing the delta deep-freezes the
      # sets so nothing mutates what a refresh will read.
      def freeze
        [@upserted_ids, @removed_ids, @upserted_urns, @removed_urns, @staged].each(&:freeze)
        super
      end

      private

      def stage(kind, id, urn)
        return if @overflowed

        @staged << [kind, id, urn]
      end

      def apply(kind, id, urn)
        return if @overflowed

        if kind == :upsert
          @upserted_ids << id
          @upserted_urns << urn
        else
          @removed_ids << id
          @removed_urns << urn
        end
        overflow! if size > @cap
      end

      def overflow!
        @overflowed = true
        [@upserted_ids, @removed_ids, @upserted_urns, @removed_urns, @staged].each(&:clear)
      end
    end
  end
end
