# frozen_string_literal: true

require "json"
require_relative "content_hash"

module Nabu
  module Store
    # What one load did, in document-level counts (passages are an
    # implementation detail of their document). A Data value: frozen,
    # compared by content.
    LoadReport = Data.define(:added, :updated, :skipped, :withdrawn, :errored)

    # Persists adapter output into the catalog with the idempotency /
    # revision / withdrawal semantics of architecture §3. `nabu rebuild`
    # rests on these rules:
    #
    # - Upsert on urn, for documents and passages alike. New urn → insert at
    #   revision 1 + provenance "loaded". Same urn, same content_sha256 →
    #   skipped entirely (no writes at all, so loading a corpus twice leaves
    #   rows byte-identical). Same urn, different sha → fields updated,
    #   revision += 1, provenance "revised" journaling {old_sha, new_sha}.
    # - Nothing is ever hard-deleted. A full load (full: true) asserts batch
    #   completeness: this source's documents absent from the batch are marked
    #   withdrawn (+ provenance); partial loads never infer deletions. Within
    #   a revised document, passages missing from the new parse are withdrawn
    #   the same way. Withdrawn rows that reappear are restored (+ provenance
    #   "restored"), bumping revision only if content also changed.
    # - One transaction per document: a quarantined or constraint-violating
    #   document never rolls back its batch siblings. The withdrawal sweep
    #   runs in its own transaction at the end.
    #
    # Documents are looked up scoped to this loader's source: one source's
    # load can never mutate (or withdraw) another source's rows; a cross-source
    # urn collision surfaces as a unique-constraint error on that document.
    class Loader
      TOOL = "nabu-loader"

      # db: the Sequel database (Store.setup! already applied);
      # source: the Store::Source row this load belongs to.
      def initialize(db:, source:)
        @db = db
        @source = source
      end

      # Load an enumerable of Nabu::Document. Streams: only urns are retained
      # across documents (for withdrawal detection). +on_document+, when given,
      # is called after each processed document with (processed_count,
      # errored_count) — a live-progress hook, nil-safe (no behaviour change).
      def load(documents, full: true, on_document: nil)
        run(full: full, on_document: on_document) do |process, _quarantine|
          documents.each { |document| process.call(document) }
        end
      end

      # discover → parse → load straight off an adapter. Nabu::ParseError
      # quarantines that document (journaled, counted as errored) and the
      # batch continues; any other Nabu::Error (fetch-level trouble)
      # propagates and aborts. +on_document+ ticks after every processed OR
      # quarantined document (see #load).
      def load_from(adapter, workdir:, full: true, on_document: nil)
        run(full: full, on_document: on_document) do |process, quarantine|
          adapter.discover(workdir).each do |ref|
            document =
              begin
                adapter.parse(ref)
              rescue Nabu::ParseError => e
                quarantine.call(ref, e)
                next
              end
            process.call(document)
          end
        end
      end

      private

      def run(full:, on_document: nil)
        counts = Hash.new(0)
        seen_urns = Set.new
        processed = 0
        tick = lambda do
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        process = lambda do |document|
          # Even a document that fails to persist was present upstream, so its
          # urn still shields the existing row from the withdrawal sweep.
          seen_urns.add(document.urn)
          load_document(document, counts)
          tick.call
        end
        quarantine = lambda do |ref, error|
          counts[:errored] += 1
          journal(event: "quarantined", params: { "ref_id" => ref.id, "error" => error.message })
          tick.call
        end
        yield(process, quarantine)
        sweep_withdrawn(seen_urns, counts) if full
        LoadReport.new(
          added: counts[:added], updated: counts[:updated], skipped: counts[:skipped],
          withdrawn: counts[:withdrawn], errored: counts[:errored]
        )
      end

      # One transaction per document; a constraint violation rolls back only
      # this document, is journaled, and the batch moves on.
      def load_document(document, counts)
        outcome = @db.transaction { upsert_document(document) }
        counts[outcome] += 1
      rescue Sequel::DatabaseError => e
        counts[:errored] += 1
        journal(event: "quarantined", params: { "urn" => document.urn, "error" => e.message })
      end

      def upsert_document(document)
        passages = document.passages
        passage_shas = passages.to_h { |passage| [passage.urn, ContentHash.passage(passage)] }
        doc_sha = ContentHash.document(document, passage_shas.values)

        row = Document.first(source_id: @source.id, urn: document.urn)
        return insert_document(document, passage_shas, doc_sha) if row.nil?

        if row.content_sha256 == doc_sha
          return :skipped unless row.withdrawn

          restore(row) # unchanged content: no revision bump, no passage work
        else
          revise_document(row, document, passage_shas, doc_sha)
        end
        :updated
      end

      def insert_document(document, passage_shas, doc_sha)
        row = Document.create(
          source_id: @source.id, urn: document.urn, title: document.title,
          language: document.language, canonical_path: document.canonical_path,
          content_sha256: doc_sha, revision: 1, withdrawn: false
        )
        journal(event: "loaded", document_id: row.id)
        document.passages.each { |passage| insert_passage(row.id, passage, passage_shas.fetch(passage.urn)) }
        :added
      end

      def revise_document(row, document, passage_shas, doc_sha)
        old_sha = row.content_sha256
        was_withdrawn = row.withdrawn
        row.update(
          title: document.title, language: document.language, canonical_path: document.canonical_path,
          content_sha256: doc_sha, revision: row.revision + 1, withdrawn: false
        )
        journal(event: "revised", document_id: row.id, params: { "old_sha" => old_sha, "new_sha" => doc_sha })
        journal(event: "restored", document_id: row.id) if was_withdrawn
        upsert_passages(row, document, passage_shas)
      end

      def upsert_passages(doc_row, document, passage_shas)
        existing = Passage.where(document_id: doc_row.id).all.to_h { |passage| [passage.urn, passage] }
        withdraw_vanished_passages(existing, document)
        park_resequenced_passages(existing, document)

        document.passages.each do |passage|
          upsert_passage(doc_row, passage, existing[passage.urn], passage_shas.fetch(passage.urn))
        end
      end

      def upsert_passage(doc_row, passage, row, sha)
        return insert_passage(doc_row.id, passage, sha) if row.nil?

        if row.content_sha256 == sha
          restore(row) if row.withdrawn # identical content: restore only
        else
          revise_passage(row, passage, sha)
        end
      end

      def revise_passage(row, passage, sha)
        old_sha = row.content_sha256
        was_withdrawn = row.withdrawn
        row.update(
          sequence: passage.sequence, language: passage.language,
          text: passage.text, text_normalized: passage.text_normalized,
          annotations_json: ContentHash.canonical_json(passage.annotations),
          content_sha256: sha, revision: row.revision + 1, withdrawn: false
        )
        journal(event: "revised", passage_id: row.id, params: { "old_sha" => old_sha, "new_sha" => sha })
        journal(event: "restored", passage_id: row.id) if was_withdrawn
      end

      # Passages whose urns vanished from the new parse: withdraw (journaled;
      # already-withdrawn rows stay silent). If a vanished row still occupies
      # a (document_id, sequence) slot the new layout needs, park it at a
      # unique negative sequence so upserts can't collide with a ghost.
      def withdraw_vanished_passages(existing, document)
        live_urns = document.passages.map(&:urn)
        occupied = document.passages.map(&:sequence)
        existing.each_value do |row|
          next if live_urns.include?(row.urn)

          updates = {}
          updates[:sequence] = -row.id if occupied.include?(row.sequence)
          if row.withdrawn
            row.update(updates) unless updates.empty?
          else
            row.update(updates.merge(withdrawn: true))
            journal(event: "withdrawn", passage_id: row.id)
          end
        end
      end

      # Surviving passages that are moving to a different sequence get parked
      # at a unique negative sequence first, so reorders (e.g. two passages
      # swapping places) can't trip the (document_id, sequence) unique index
      # mid-update. Their real sequence lands with the content update.
      def park_resequenced_passages(existing, document)
        document.passages.each do |passage|
          row = existing[passage.urn]
          row.update(sequence: -row.id) if row && row.sequence != passage.sequence
        end
      end

      def insert_passage(document_id, passage, sha)
        row = Passage.create(
          document_id: document_id, urn: passage.urn, sequence: passage.sequence,
          language: passage.language, text: passage.text, text_normalized: passage.text_normalized,
          annotations_json: ContentHash.canonical_json(passage.annotations),
          content_sha256: sha, revision: 1, withdrawn: false
        )
        journal(event: "loaded", passage_id: row.id)
      end

      # Withdrawn row present again with unchanged content: clear the flag,
      # journal "restored", leave revision alone. Works for documents and
      # passages (the model tells us which id column to journal).
      def restore(row)
        row.update(withdrawn: false)
        id_column = row.is_a?(Document) ? :document_id : :passage_id
        journal(event: "restored", id_column => row.id)
      end

      # Full loads assert completeness: this source's active documents whose
      # urns the batch never produced are withdrawn (never hard-deleted), in
      # one final transaction of their own.
      def sweep_withdrawn(seen_urns, counts)
        @db.transaction do
          Document.where(source_id: @source.id, withdrawn: false).select_map(%i[id urn]).each do |id, urn|
            next if seen_urns.include?(urn)

            Document.where(id: id).update(withdrawn: true)
            journal(event: "withdrawn", document_id: id)
            counts[:withdrawn] += 1
          end
        end
      end

      def journal(event:, document_id: nil, passage_id: nil, params: nil)
        Provenance.create(
          event: event, document_id: document_id, passage_id: passage_id,
          tool: TOOL, tool_version: Nabu::VERSION,
          params_json: params && JSON.generate(params),
          at: Time.now
        )
      end
    end
  end
end
