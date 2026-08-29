# frozen_string_literal: true

module Nabu
  module Store
    # P87-2 (Q51, under №R-51-B) — the silver-lemma PROJECTION CACHE.
    #
    # The 2026-08-29 lesson ([[rebuildable-is-not-recomputed]]): the
    # derivability law requires the projection to be REGENERABLE, not
    # re-paid every time. The deterministic per-record work — JSON parse
    # of the 3.9GB shelf, ~150M Normalize.search_form folds, grouping,
    # the identity-lemma check — runs ONCE per shelf state and lands here
    # in load-ready form: one row per (urn, folded lemma), everything
    # catalog-independent (urns, never passage ids — ids change per
    # rebuild). The apply pass then only resolves urns, checks coverage,
    # applies the dictionary filter (index-time POLICY, a set lookup over
    # the cached folded values + the precomputed identity bit) and
    # inserts.
    #
    # DERIVED AND DISPOSABLE: delete the file and the next apply
    # regenerates it — an optimization OVER the derivability invariant
    # (the --incremental posture), never a relaxation. Validity is keyed
    # by the shelf's content fingerprint + PROJECTION_VERSION; a fold- or
    # grouping-rule change bumps the version and invalidates every cache.
    class SilverLemmaCache
      # const: the projection-rules version — bump whenever
      # Normalize.search_form, the grouping rule, or the identity-lemma
      # rule changes semantics; a stale version invalidates the cache.
      PROJECTION_VERSION = "v1"

      FILENAME = "silver-lemmas.sqlite3"
      BATCH = 5_000

      def self.default_path(config)
        File.join(config.local_dir, "cache", FILENAME)
      end

      attr_reader :path

      def initialize(path:)
        @path = path
      end

      def db
        @db ||= begin
          FileUtils.mkdir_p(File.dirname(path))
          # Through the ONE Sequel gate (the derivability-writers guard):
          # the cache is its own sqlite file, but connection discipline
          # (WAL, timeouts) is Store's to own everywhere.
          Store.connect(path)
        end
      end

      # True when the cache was built from exactly this shelf state under
      # the current projection rules.
      def valid_for?(fingerprint)
        return false unless File.file?(path) && db.table_exists?(:meta)

        meta = db[:meta].first
        !meta.nil? && meta[:shelf_fingerprint] == fingerprint &&
          meta[:projection_version] == PROJECTION_VERSION
      end

      # Rebuild the cache from the shelf — the ONE run of the expensive
      # deterministic work. Replaces any prior content wholesale.
      def build!(shelf:, progress: nil)
        fingerprint = shelf.fingerprint
        db.drop_table?(:rows)
        db.drop_table?(:meta)
        db.create_table(:rows) do
          String :urn, null: false
          String :language, null: false
          String :lemma_folded, null: false
          String :lemma_raw, null: false
          String :surface_forms
          Integer :identity, null: false
        end
        db.create_table(:meta) do
          String :shelf_fingerprint, null: false
          String :projection_version, null: false
          String :built_at, null: false
        end
        count = 0
        batch = []
        shelf.languages.sort.each do |language|
          progress&.stage("silver cache: folding + grouping the #{language} shelf")
          shelf.each_record(language: language) do |record|
            project(record).each { |row| batch << row }
            next if batch.size < BATCH

            db[:rows].multi_insert(batch)
            count += batch.size
            progress&.load_tick(count, 0)
            batch = []
          end
        end
        unless batch.empty?
          db[:rows].multi_insert(batch)
          count += batch.size
        end
        db.add_index(:rows, :urn)
        db[:meta].insert(shelf_fingerprint: fingerprint,
                         projection_version: PROJECTION_VERSION,
                         built_at: Time.now.utc.iso8601)
        count
      end

      def stamp_version!(version)
        db[:meta].update(projection_version: version)
      end

      def rows_dataset = db[:rows]

      # Stream the cached rows in urn-batches of +size+ distinct urns —
      # the apply pass's unit (coverage checks and passage resolution are
      # urn-keyed).
      def each_urn_batch(size: 1_000)
        batch_urns = []
        rows = []
        db[:rows].order(:urn).each do |row|
          if batch_urns.last != row[:urn]
            if batch_urns.size >= size
              yield rows
              batch_urns = []
              rows = []
            end
            batch_urns << row[:urn]
          end
          rows << row
        end
        yield rows unless rows.empty?
      end

      private

      # One shelf record → its cache rows: the SilverLemmaIndexer grouping
      # contract verbatim (group by folded lemma, distinct surface forms in
      # first-seen order, lemma-less tokens contribute nothing), plus the
      # precomputed identity bit (folds to one of its own surfaces).
      def project(record)
        grouped = record.tokens.each_with_object({}) do |(form, lemma, _upos), acc|
          next if lemma.nil? || lemma.empty?

          folded = Normalize.search_form(lemma, language: record.language)
          entry = acc[folded] ||= { raw: lemma, forms: [] }
          entry[:forms] << form if form && !form.empty? && !entry[:forms].include?(form)
        end
        grouped.map do |folded, entry|
          identity = entry[:forms].any? do |form|
            Normalize.search_form(form, language: record.language) == folded
          end
          { urn: record.urn, language: record.language, lemma_folded: folded,
            lemma_raw: entry[:raw], surface_forms: entry[:forms].join(", "),
            identity: identity ? 1 : 0 }
        end
      end
    end
  end
end
