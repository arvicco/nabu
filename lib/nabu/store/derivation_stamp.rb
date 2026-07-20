# frozen_string_literal: true

module Nabu
  module Store
    # Read/write seam for the `derivation_stamps` table (P36-1, migration
    # 017): one row per replayed source recording the DerivationFingerprint
    # the replay satisfied. Operates on an explicit db handle (like
    # Indexer/RunRecorder) rather than a bound model: both writers (full
    # rebuild, incremental re-derive) hold their own catalog connection.
    #
    # Contract: a WEAK fingerprint (no honest canonical identity) is never
    # stored — the write clears any stale row instead, so absence keeps
    # meaning "dirty, re-derive" and a weak source can never be skipped.
    module DerivationStamp
      module_function

      # Upsert the stamp for +slug+ from a DerivationFingerprint::Fingerprint.
      def stamp!(db, slug:, fingerprint:, now: Time.now)
        db[:derivation_stamps].where(slug: slug).delete
        return if fingerprint.weak?

        db[:derivation_stamps].insert(
          slug: slug, fingerprint: fingerprint.combined,
          canonical_identity: fingerprint.canonical_identity,
          parser_digest: fingerprint.parser_digest,
          fold_digest: fingerprint.fold_digest,
          migration_level: fingerprint.migration_level,
          config_json: fingerprint.config_json,
          stamped_at: now
        )
      end

      # The stamp row for +slug+ (symbol-keyed hash) or nil. A catalog
      # predating migration 017 has no table — every source reads unstamped,
      # which is the safe verdict (dirty).
      def fetch(db, slug)
        return nil unless db.table_exists?(:derivation_stamps)

        db[:derivation_stamps].where(slug: slug).first
      end

      # Every stamped slug (for the incremental orphan guard).
      def slugs(db)
        return [] unless db.table_exists?(:derivation_stamps)

        db[:derivation_stamps].select_order_map(:slug)
      end
    end
  end
end
