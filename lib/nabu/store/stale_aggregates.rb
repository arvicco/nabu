# frozen_string_literal: true

module Nabu
  module Store
    # The stale-aggregate flags (the incrementality review, R2): the
    # visible record that a derived aggregate in fulltext.sqlite3 no longer
    # matches its inputs, and is waiting for the maintenance rail.
    #
    # == Why a flag, not an inline recompute
    #
    # The proportionality law (architecture §1): online sync/refresh stages
    # cost O(Δ). Some aggregates are exactly decomposable at the delta grain
    # only where the grain can vouch for the rows' OLD contribution (char
    # postings: a revised passage's replaced text is gone by refresh time;
    # the reflex closure: a language newly entering the gold set needs the
    # whole crosswalk walk). Where it cannot, the honest moves are two —
    # pay O(source)/O(corpus) inline (the measured multi-hour class this
    # law forbids) or record the debt. This table records it: one row per
    # (aggregate, scope), scope a source slug or "corpus", with the reason
    # and the moment. `nabu index maintain` recomputes each flagged
    # aggregate and clears its row; `index doctor` lists them; a full
    # rebuild drops the table (everything is fresh by construction), and a
    # whole-slice refresh that re-derives a source's aggregate outright
    # clears that source's row.
    #
    # While flagged, the aggregate serves its last exact state plus
    # whatever sound deltas did not touch it — a delta NEVER applies its
    # arithmetic over a stale base (a decrement against an already-wrong
    # count compounds the error), so a flagged scope stays flagged until a
    # recompute.
    #
    # Same lifecycle as everything else in fulltext.sqlite3: derived,
    # disposable, never migrated (the Indexer class note).
    module StaleAggregates
      TABLE = :stale_aggregates

      module_function

      def create_table(fulltext)
        fulltext.create_table?(TABLE) do
          String :aggregate, null: false
          String :scope, null: false
          String :reason, null: false
          String :marked_at, null: false
          primary_key %i[aggregate scope]
        end
      end

      # Flag (+aggregate+, +scope+) stale — idempotent; a re-mark keeps the
      # FIRST moment (the debt's age is what the doctor reports).
      def mark!(fulltext, aggregate:, scope:, reason:)
        create_table(fulltext)
        fulltext[TABLE].insert_conflict(target: %i[aggregate scope])
                       .insert(aggregate: aggregate, scope: scope, reason: reason,
                               marked_at: Time.now.utc.iso8601)
      end

      def clear!(fulltext, aggregate:, scope:)
        return unless fulltext.table_exists?(TABLE)

        fulltext[TABLE].where(aggregate: aggregate, scope: scope).delete
      end

      def stale?(fulltext, aggregate:, scope:)
        fulltext.table_exists?(TABLE) && !fulltext[TABLE].where(aggregate: aggregate, scope: scope).empty?
      end

      # Every flag, oldest first ([] when the table is absent).
      def all(fulltext)
        return [] unless fulltext.table_exists?(TABLE)

        fulltext[TABLE].order(:marked_at, :aggregate, :scope).all
      end

      def drop!(fulltext)
        fulltext.drop_table?(TABLE)
        nil
      end
    end
  end
end
