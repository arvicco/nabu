# frozen_string_literal: true

require "json"
require_relative "loader"

module Nabu
  module Store
    # Persists local-notes output (P24-1) — the NOTES-shaped fourth loader
    # (content_kind :notes), beside Store::Loader (passages),
    # Store::DictionaryLoader (entries) and Store::LanguageDossierLoader
    # (language records), sharing their call shape and LoadReport so
    # SyncRunner/Rebuild route to it with no special casing.
    #
    # Semantics are the dossier loader's: urn_notes is temperature-1 DERIVED
    # data (db = f(canonical/local-notes)), so each topic file's records
    # REPLACE that topic's rows wholesale — no revisions, no provenance
    # journal, no withdrawn flag (git and the topic files carry history; a
    # retired topic lives in the attic and keeps loading via
    # discover_with_attic). Counts are RECORD-grained: a byte-identical
    # topic skips whole (idempotent replays), a changed topic re-adds whole
    # (notes have no per-record key — the file is the record); withdrawn
    # counts rows swept for topics absent from a full batch; errored counts
    # quarantined topic FILES.
    class NoteLoader
      def initialize(db:, source:, ledger: nil)
        @db = db
        @source = source
        @ledger = ledger # accepted for loader-call-shape uniformity; unused
      end

      # discover → parse → load straight off the notes adapter, attic
      # included. Nabu::ParseError quarantines the file and the batch
      # continues.
      def load_from(adapter, workdir:, full: true, on_document: nil)
        counts = Hash.new(0)
        seen_topics = Set.new
        processed = 0
        adapter.discover_with_attic(workdir).each do |ref|
          begin
            note_file = adapter.parse(ref)
            seen_topics.add(note_file.topic)
            merge_counts(counts, self.class.replace_for_topic!(@db, note_file))
          rescue Nabu::ParseError
            counts[:errored] += 1
          end
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        counts[:withdrawn] = sweep_absent_topics(seen_topics) if full
        LoadReport.new(added: counts[:added], updated: counts[:updated], skipped: counts[:skipped],
                       withdrawn: counts[:withdrawn], errored: counts[:errored])
      end

      # Replace one topic's derived rows from its file — guarded: a catalog
      # predating migration 015 indexes nothing, honestly. A byte-identical
      # topic is a no-op (rows and ids untouched); anything else replaces
      # the topic wholesale. Returns {added:, updated:, skipped:} counts.
      def self.replace_for_topic!(db, note_file)
        return { added: 0, updated: 0, skipped: 0 } unless db.table_exists?(:urn_notes)

        rows = rows_for(note_file)
        db.transaction do
          existing = db[:urn_notes].where(topic: note_file.topic).order(:id)
                                   .select(:urn, :note, :topic, :tags, :added, :provenance).all
          next { added: 0, updated: 0, skipped: rows.size } if existing == rows

          db[:urn_notes].where(topic: note_file.topic).delete
          db[:urn_notes].multi_insert(rows)
          { added: rows.size, updated: 0, skipped: 0 }
        end
      end

      # The derived row set one NoteFile yields, in record order — shared
      # with Verify so the load and the check can never drift.
      def self.rows_for(note_file)
        provenance = "local-notes/#{note_file.topic}.yml"
        note_file.records.map do |record|
          { urn: record.urn, note: record.note, topic: note_file.topic,
            tags: record.tags.empty? ? nil : JSON.generate(record.tags),
            added: record.added, provenance: provenance }
        end
      end

      private

      def merge_counts(counts, replaced)
        replaced.each { |key, value| counts[key] += value }
      end

      # Full loads assert batch completeness: rows for topics absent from
      # the batch (file deleted AND not atticked) are DELETED — derived data
      # honestly follows canonical; the vanished file itself is what fetch
      # notes and health's pin check shout about. A batch that parsed
      # NOTHING asserted nothing about completeness and sweeps nothing.
      def sweep_absent_topics(seen_topics)
        return 0 if seen_topics.empty?
        return 0 unless @db.table_exists?(:urn_notes)

        dataset = @db[:urn_notes].exclude(topic: seen_topics.to_a)
        count = dataset.count
        dataset.delete
        count
      end
    end
  end
end
