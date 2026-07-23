# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # The source_stats DERIVED table (P42-0, migration 019): per-source
    # holdings counts maintained AT WRITE TIME so the read surfaces (status /
    # list / axis / language cards) stop re-aggregating 60M+ passages per
    # invocation. The architecture doctrine this implements: anything
    # O(corpus) runs at write time; read time is for probes.
    #
    # Two lifecycles, one truth:
    #
    # - INCREMENTAL: the Loader applies each document's contribution delta in
    #   the SAME transaction as the document write (Maintainer below) — a
    #   crashed sync leaves stats exactly as consistent as the documents it
    #   committed. An idempotent re-load (all same-content skips) touches
    #   nothing.
    # - WHOLESALE: `nabu rebuild` (and an incremental rebuild that replayed
    #   anything) re-derives the whole table from the loaded catalog
    #   (.derive!) — the rebuildability invariant, and the reference the
    #   incremental path is test-pinned against (the equivalence test).
    #
    # `nabu health` (D42-a) holds the table against a rotating live sample:
    # stats are derived, so a write path that bypasses the loader is a bug
    # the drift probe catches loudly.
    #
    # == Counting semantics (the census rules, shared with Query::List)
    #
    # live_documents excludes withdrawn; live_passages is live-on-live
    # (neither the passage nor its document withdrawn); retired_documents is
    # retired_upstream AND not withdrawn; per-language rows carry live
    # documents by documents.language and live passages by passages.language
    # (independent groupings — a grc document can hold eng passages), NULL
    # languages riding only in the parent totals. license_overrides_json is
    # {override class => live doc count} for docs WITH an override — never
    # effective classes, because sources.license_class can be relabeled
    # without touching documents; readers compose the effective mix.
    #
    # There is no stored global roll-up: the global census is SUM over the
    # per-source rows (O(#sources)) — see .rollup.
    module SourceStats
      TABLE = :source_stats
      LANG_TABLE = :source_stats_languages

      # The zero contribution (a document that is not there).
      EMPTY = { live: 0, withdrawn: 0, retired: 0, passages: 0,
                doc_languages: {}.freeze, passage_languages: {}.freeze,
                overrides: {}.freeze }.freeze

      module_function

      # Feature detection: a live catalog predating migration 019 has no
      # table — every caller (loader hooks, readers) degrades to the
      # pre-P42-0 behavior when this is false.
      def available?(db)
        !db.nil? && db.table_exists?(TABLE)
      end

      # A loader-side Maintainer for +source+, or nil when the catalog
      # predates the table (the loader then skips stats entirely).
      def maintainer(db:, source:)
        available?(db) ? Maintainer.new(db: db, source_id: source.id) : nil
      end

      # -- readers -------------------------------------------------------------

      # One source's stats row as a plain hash (zeros when the source has no
      # row — it holds no documents).
      def fetch(db, source_id)
        db[TABLE].first(source_id: source_id) ||
          { source_id: source_id, live_documents: 0, live_passages: 0,
            withdrawn_documents: 0, retired_documents: 0, license_overrides_json: "{}" }
      end

      # -- D42-a truth probes (O(one source), riding the source_id index) ----

      # The document-grain truth for one source, straight off the documents
      # table — what the stats row MUST say.
      def document_truth(db, source_id)
        rows = db[:documents].where(source_id: source_id)
        { live_documents: rows.where(withdrawn: false).count,
          withdrawn_documents: rows.where(withdrawn: true).count,
          retired_documents: rows.where(withdrawn: false, retired_upstream: true).count }
      end

      # The live-on-live passage count for one source.
      def passage_truth(db, source_id)
        db[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
          .count
      end

      # The global roll-up, summed over the per-source rows.
      def rollup(db)
        row = db[TABLE].select(
          Sequel.function(:coalesce, Sequel.function(:sum, :live_documents), 0).as(:live_documents),
          Sequel.function(:coalesce, Sequel.function(:sum, :live_passages), 0).as(:live_passages),
          Sequel.function(:coalesce, Sequel.function(:sum, :withdrawn_documents), 0).as(:withdrawn_documents),
          Sequel.function(:coalesce, Sequel.function(:sum, :retired_documents), 0).as(:retired_documents)
        ).first
        row.transform_values(&:to_i)
      end

      # -- wholesale derivation ------------------------------------------------

      # Re-derive the whole table from the loaded catalog (rebuild, and the
      # reference for the incremental path). One documents scan + one
      # passages-join scan; sources with no document rows get no row (the
      # incremental path never minted one either). No-op without the table.
      def derive!(db, note:)
        return unless available?(db)

        stats = aggregate(db)
        now = Time.now
        db.transaction do
          db[LANG_TABLE].delete
          db[TABLE].delete
          stats.each do |source_id, source|
            db[TABLE].insert(
              source_id: source_id, live_documents: source[:live], live_passages: source[:passages],
              withdrawn_documents: source[:withdrawn], retired_documents: source[:retired],
              license_overrides_json: encode_json(source[:overrides]),
              updated_at: now, note: note
            )
            source[:langs].sort.each do |language, counts|
              db[LANG_TABLE].insert(source_id: source_id, language: language,
                                    documents: counts[:documents], passages: counts[:passages])
            end
          end
        end
      end

      # The full-catalog aggregation the wholesale path (and the D42-a truth
      # probe, per source) rests on: {source_id => {live:, withdrawn:,
      # retired:, passages:, langs: {code => {documents:, passages:}},
      # overrides: {class => n}}}. +source_id+ scopes to one source.
      def aggregate(db, source_id: nil)
        stats = Hash.new do |hash, id|
          hash[id] = { live: 0, withdrawn: 0, retired: 0, passages: 0,
                       langs: Hash.new { |langs, code| langs[code] = { documents: 0, passages: 0 } },
                       overrides: Hash.new(0) }
        end
        aggregate_documents(db, stats, source_id)
        aggregate_passages(db, stats, source_id)
        stats
      end

      def aggregate_documents(db, stats, source_id)
        dataset = db[:documents]
        dataset = dataset.where(source_id: source_id) if source_id
        dataset
          .group(:source_id, :language, :withdrawn, :retired_upstream, :license_override)
          .select(:source_id, :language, :withdrawn, :retired_upstream, :license_override,
                  Sequel.function(:count).*.as(:n))
          .each do |row|
            source = stats[row[:source_id]]
            next source[:withdrawn] += row[:n] if row[:withdrawn]

            source[:live] += row[:n]
            source[:retired] += row[:n] if row[:retired_upstream]
            source[:langs][row[:language]][:documents] += row[:n] if row[:language]
            source[:overrides][row[:license_override]] += row[:n] if row[:license_override]
          end
      end

      def aggregate_passages(db, stats, source_id)
        dataset = db[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:documents][:source_id] => source_id) if source_id
        dataset
          .group(Sequel[:documents][:source_id], Sequel[:passages][:language])
          .select(Sequel[:documents][:source_id].as(:source_id), Sequel[:passages][:language].as(:language),
                  Sequel.function(:count).*.as(:n))
          .each do |row|
            source = stats[row[:source_id]]
            source[:passages] += row[:n]
            source[:langs][row[:language]][:passages] += row[:n] if row[:language]
          end
      end

      # Sorted keys so incremental and wholesale writes are byte-comparable.
      def encode_json(counts)
        JSON.generate(counts.sort.to_h)
      end

      # Applies per-document contribution deltas inside the loader's own
      # transactions. Contributions are the EMPTY-shaped hashes above; the
      # Loader computes before/after around each mutation and this class
      # writes the difference. Reads-modify-writes are safe: SQLite is
      # single-writer and every call sits inside the document's transaction.
      class Maintainer
        NOTE = "loader (incremental)"

        def initialize(db:, source_id:)
          @db = db
          @source_id = source_id
        end

        # The contribution a stored document row currently makes (queries the
        # doc's live passages when the doc is live). +row+ is a
        # Store::Document model instance or nil.
        def contribution_of(row)
          return EMPTY if row.nil?
          return EMPTY.merge(withdrawn: 1) if row.withdrawn

          live_contribution(id: row.id, language: row.language,
                            license_override: row.license_override, retired: row.retired_upstream)
        end

        # The contribution of a live document from columns (the withdrawal
        # sweep reads columns, not models) — one grouped passage query.
        def live_contribution(id:, language:, license_override:, retired:)
          by_language = @db[:passages].where(document_id: id, withdrawn: false)
                                      .group(:language)
                                      .select(:language, Sequel.function(:count).*.as(:n))
                                      .to_hash(:language, :n)
          { live: 1, withdrawn: 0, retired: retired ? 1 : 0,
            passages: by_language.values.sum,
            doc_languages: language ? { language => 1 } : {},
            passage_languages: by_language.except(nil),
            overrides: license_override ? { license_override => 1 } : {} }
        end

        # The contribution a freshly inserted document makes — computed from
        # the in-memory Nabu::Document (every parsed passage is live), so the
        # rebuild's bulk-insert path pays no extra query.
        def contribution_for(document, retained:)
          languages = document.passages.map(&:language).compact.tally
          { live: 1, withdrawn: 0, retired: retained ? 1 : 0,
            passages: document.passages.size,
            doc_languages: document.language ? { document.language => 1 } : {},
            passage_languages: languages,
            overrides: document.license_override ? { document.license_override => 1 } : {} }
        end

        def added(document, retained:)
          apply(EMPTY, contribution_for(document, retained: retained))
        end

        # Snapshot around a mutation of an existing row (revision, restore,
        # retirement flip, license relabel): before, yield, after, apply.
        def around(row)
          before = contribution_of(row)
          result = yield
          apply(before, contribution_of(row))
          result
        end

        # The withdrawal sweep's delta: the doc WAS this live contribution
        # and is now one withdrawn document.
        def swept(id:, language:, license_override:, retired:)
          apply(live_contribution(id: id, language: language,
                                  license_override: license_override, retired: retired),
                EMPTY.merge(withdrawn: 1))
        end

        private

        def apply(before, after)
          return if before == after

          apply_totals(before, after)
          apply_languages(before, after)
        end

        def apply_totals(before, after)
          row = @db[TABLE].first(source_id: @source_id)
          overrides = row ? JSON.parse(row[:license_overrides_json]) : {}
          merge_counts(overrides, before[:overrides], after[:overrides])
          values = {
            live_documents: (row ? row[:live_documents] : 0) + after[:live] - before[:live],
            live_passages: (row ? row[:live_passages] : 0) + after[:passages] - before[:passages],
            withdrawn_documents: (row ? row[:withdrawn_documents] : 0) + after[:withdrawn] - before[:withdrawn],
            retired_documents: (row ? row[:retired_documents] : 0) + after[:retired] - before[:retired],
            license_overrides_json: SourceStats.encode_json(overrides),
            updated_at: Time.now, note: NOTE
          }
          if row
            @db[TABLE].where(source_id: @source_id).update(values)
          else
            @db[TABLE].insert(values.merge(source_id: @source_id))
          end
        end

        def apply_languages(before, after)
          changed = (before[:doc_languages].keys + after[:doc_languages].keys +
                     before[:passage_languages].keys + after[:passage_languages].keys).uniq
          changed.each do |language|
            delta_docs = after[:doc_languages].fetch(language, 0) - before[:doc_languages].fetch(language, 0)
            delta_pass = after[:passage_languages].fetch(language, 0) - before[:passage_languages].fetch(language, 0)
            next if delta_docs.zero? && delta_pass.zero?

            upsert_language(language, delta_docs, delta_pass)
          end
        end

        # Rows that reach zero on both grains are pruned so the incremental
        # table stays row-identical to a wholesale derivation.
        def upsert_language(language, delta_docs, delta_pass)
          scope = @db[LANG_TABLE].where(source_id: @source_id, language: language)
          row = scope.first
          documents = (row ? row[:documents] : 0) + delta_docs
          passages = (row ? row[:passages] : 0) + delta_pass
          if documents.zero? && passages.zero?
            scope.delete
          elsif row
            scope.update(documents: documents, passages: passages)
          else
            @db[LANG_TABLE].insert(source_id: @source_id, language: language,
                                   documents: documents, passages: passages)
          end
        end

        # counts += after - before, dropping keys that reach zero (so the
        # JSON stays identical to a wholesale derivation's).
        def merge_counts(counts, before, after)
          (before.keys + after.keys).uniq.each do |key|
            value = counts.fetch(key, 0) + after.fetch(key, 0) - before.fetch(key, 0)
            value.zero? ? counts.delete(key) : counts[key] = value
          end
        end
      end
    end
  end
end
