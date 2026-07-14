# frozen_string_literal: true

require_relative "loader"

module Nabu
  module Store
    # Persists local-language dossier output (P19-1) — the LANGUAGE-shaped
    # third loader (content_kind :language), beside Store::Loader (passages)
    # and Store::DictionaryLoader (entries), sharing their call shape and
    # LoadReport so SyncRunner/Rebuild route to it with no special casing.
    #
    # Semantics are the census's, not the corpus's: language_records is
    # temperature-1 DERIVED data (db = f(canonical/local-language)), so each
    # dossier's records REPLACE that code's rows wholesale — no revisions, no
    # provenance journal, no withdrawn flag (git and the dossier's own
    # section headers carry history; a retired dossier lives in the attic and
    # keeps loading via discover_with_attic). Counts are RECORD-grained
    # (added/updated/skipped per (code, kind) lane; withdrawn counts rows
    # swept for codes absent from a full batch) except errored, which counts
    # quarantined dossier FILES.
    class LanguageDossierLoader
      def initialize(db:, source:, ledger: nil)
        @db = db
        @source = source
        @ledger = ledger # accepted for loader-call-shape uniformity; unused
      end

      # discover → parse → load straight off the dossier adapter, attic
      # included (a retired dossier's knowledge never vanishes; live wins on
      # duplicates). Nabu::ParseError quarantines the file and the batch
      # continues.
      def load_from(adapter, workdir:, full: true, on_document: nil)
        counts = Hash.new(0)
        seen_codes = Set.new
        processed = 0
        adapter.discover_with_attic(workdir).each do |ref|
          begin
            dossier = adapter.parse(ref)
            seen_codes.add(dossier.code)
            merge_counts(counts, self.class.replace_for_code!(@db, dossier))
          rescue Nabu::ParseError
            counts[:errored] += 1
          end
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        counts[:withdrawn] = sweep_absent_codes(seen_codes) if full
        LoadReport.new(added: counts[:added], updated: counts[:updated], skipped: counts[:skipped],
                       withdrawn: counts[:withdrawn], errored: counts[:errored])
      end

      # Replace one code's derived rows from its dossier — the shared seam
      # the LanguageShelf accretion path also refreshes through (guarded: a
      # catalog predating migration 014 indexes nothing, honestly). Returns
      # {added:, updated:, skipped:} record-grained counts.
      def self.replace_for_code!(db, dossier)
        return { added: 0, updated: 0, skipped: 0 } unless db.table_exists?(:language_records)

        counts = { added: 0, updated: 0, skipped: 0 }
        db.transaction do
          existing = db[:language_records].where(lang_code: dossier.code)
                                          .to_h { |row| [row[:kind], row] }
          dossier.records.each { |record| counts[upsert_record(db, dossier.code, existing, record)] += 1 }
          stale = existing.keys - dossier.records.map(&:kind)
          db[:language_records].where(lang_code: dossier.code, kind: stale).delete unless stale.empty?
        end
        counts
      end

      def self.upsert_record(db, code, existing, record)
        row = existing[record.kind]
        if row.nil?
          db[:language_records].insert(lang_code: code, kind: record.kind,
                                       body: record.body, source: record.source)
          :added
        elsif row[:body] == record.body && row[:source] == record.source
          :skipped
        else
          db[:language_records].where(id: row[:id]).update(body: record.body, source: record.source)
          :updated
        end
      end
      private_class_method :upsert_record

      private

      def merge_counts(counts, replaced)
        replaced.each { |key, value| counts[key] += value }
      end

      # Full loads assert batch completeness: rows for codes absent from the
      # batch (dossier deleted AND not atticked) are DELETED — derived data
      # honestly follows canonical, and the vanished file itself is what the
      # fetch notes and health's pin check shout about. A batch that parsed
      # NOTHING (every dossier quarantined) asserted nothing about
      # completeness and sweeps nothing.
      def sweep_absent_codes(seen_codes)
        return 0 if seen_codes.empty?
        return 0 unless @db.table_exists?(:language_records)

        dataset = @db[:language_records].exclude(lang_code: seen_codes.to_a)
        count = dataset.count
        dataset.delete
        count
      end
    end
  end
end
