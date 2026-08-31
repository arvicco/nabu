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

      # The corpus-builders sentinel row (P89-1, №R-54 (c)): the builders
      # digest rides the same table under a slug no source can carry, so
      # migration 017's schema needs no change. Excluded from slugs() —
      # and thereby from the incremental orphan guard — by design.
      BUILDERS_SLUG = "__corpus-builders__"

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

      # Every stamped SOURCE slug (for the incremental orphan guard) — the
      # builders sentinel is bookkeeping, not a source, and never orphans.
      def slugs(db)
        return [] unless db.table_exists?(:derivation_stamps)

        db[:derivation_stamps].exclude(slug: BUILDERS_SLUG).select_order_map(:slug)
      end

      # Mint the builders sentinel (P89-1) after the corpus builders ran.
      # The digest doubles as fingerprint and parser_digest; the canonical/
      # fold columns are NOT NULL so they carry an honest filler.
      def stamp_builders!(db, digest:, migration_level:, now: Time.now)
        db[:derivation_stamps].where(slug: BUILDERS_SLUG).delete
        db[:derivation_stamps].insert(
          slug: BUILDERS_SLUG, fingerprint: digest, canonical_identity: "-",
          parser_digest: digest, fold_digest: "-",
          migration_level: migration_level, config_json: "{}", stamped_at: now
        )
      end

      # The stamped builders digest, or nil (absent table or sentinel —
      # which reads as dirty: the builders re-run and the sentinel self-
      # heals, the safe direction).
      def builders_digest(db)
        return nil unless db.table_exists?(:derivation_stamps)

        db[:derivation_stamps].where(slug: BUILDERS_SLUG).get(:fingerprint)
      end

      # The eldest per-source stamp time — the `--trust-derivations` code
      # horizon (P89-1): no run whose stamps survive can have loaded its
      # code later than this. nil when nothing is stamped.
      def oldest_stamped_at(db)
        return nil unless db.table_exists?(:derivation_stamps)

        db[:derivation_stamps].exclude(slug: BUILDERS_SLUG).min(:stamped_at)
      end

      # The language-bearing derived tables the census below unions. ALL of
      # them or nothing: fold application (Normalize.search_form) is keyed by
      # the language stored on the row it shaped, so a census missing one
      # table could miss the one language that consults a fold module —
      # silent under-rebuild, the sin.
      CENSUS_TABLES = %i[sources documents passages
                         dictionaries dictionary_entries dictionary_reflexes].freeze

      # The distinct language tags across +slug+'s derived rows (documents,
      # passages, dictionary headword languages, reflex languages), sorted —
      # the honest per-source language set behind the fold-digest granularity
      # (P39-1). There is no static declaration to read instead: the registry
      # has no language key and adapters mint languages per passage (often
      # from upstream data), so the catalog's own rows are the census.
      # Withdrawn rows are deliberately included (dirty-more). Returns nil —
      # "unknowable", which makes the fingerprint consult EVERY fold module —
      # when the catalog cannot answer (pre-migration tables).
      def derived_languages(db, slug)
        return nil unless CENSUS_TABLES.all? { |table| db.table_exists?(table) }

        source_id = db[:sources].where(slug: slug).get(:id)
        return [] if source_id.nil?

        documents = db[:documents].where(source_id: source_id)
        dictionaries = db[:dictionaries].where(source_id: source_id)
        entries = db[:dictionary_entries].where(dictionary_id: dictionaries.select(:id))
        reflexes = db[:dictionary_reflexes].where(dictionary_entry_id: entries.select(:id))
        [documents, db[:passages].where(document_id: documents.select(:id)), dictionaries, reflexes]
          .flat_map { |dataset| dataset.exclude(language: nil).distinct.select_map(:language) }
          .uniq.sort
      end
    end
  end
end
