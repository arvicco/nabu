# frozen_string_literal: true

require "json"
require_relative "content_hash"

module Nabu
  module Store
    # What one load did, in document-level counts (passages are an
    # implementation detail of their document). A Data value: frozen,
    # compared by content.
    #
    # +skipped_by_rule+ (P11-7) counts discovered refs the adapter's parse
    # DELIBERATELY declined as non-documents (Nabu::DocumentSkipped — e.g. an
    # ORACC catalog-only skeleton with no transcribed lines): honest catalog-
    # only skips, NOT quarantines (+errored+). Defaults to 0 so every existing
    # construction and stored count stays valid.
    LoadReport = Data.define(:added, :updated, :skipped, :withdrawn, :errored, :skipped_by_rule) do
      def initialize(added:, updated:, skipped:, withdrawn:, errored:, skipped_by_rule: 0)
        super
      end
    end

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
    # - Retention (P5-2): a document discovered from the attic (its canonical
    #   file was scrapped upstream; Adapter#discover_with_attic flags the ref
    #   retained) loads LIVE with retired_upstream=true + provenance "retired"
    #   (params carry the upstream sha it vanished at when the attic manifest
    #   knows it; otherwise the event is journaled without params). Retired ≠
    #   withdrawn: the urn is present, so the withdrawal sweep never touches
    #   it and its passages index/search/export normally. A retired urn later
    #   discovered live again flips back (+ provenance "unretired"), and its
    #   now-stale attic duplicate is journaled "superseded" — once, not per
    #   load (steady state stays silent, like re-withdrawals).
    # - One transaction per document: a quarantined or constraint-violating
    #   document never rolls back its batch siblings. The withdrawal sweep
    #   runs in its own transaction at the end.
    #
    # Documents are looked up scoped to this loader's source: one source's
    # load can never mutate (or withdraw) another source's rows; a cross-source
    # urn collision surfaces as a unique-constraint error on that document.
    #
    # == The durable revisions ledger (P7-1)
    #
    # The provenance journal above lives in the CATALOG and therefore resets
    # with it on rebuild — it is derived-run journaling, honest but ephemeral.
    # Content TRANSITIONS of existing rows (revised, withdrawn, restored,
    # retired, unretired) are additionally journaled urn-keyed into the history
    # ledger's revisions table (Store::Ledger), which rebuild never drops.
    # Fresh INSERTS write nothing durable on purpose: a rebuild replays the
    # whole corpus as inserts into an empty catalog, so insert-path journaling
    # would spam the ledger with 60k "loaded"/"retired" rows per rebuild; the
    # transitions that matter were journaled by the sync that first saw them.
    # One extra insert per transition is loader-hot-path cheap. +ledger+ may be
    # nil (no durable journal — tests without one); every production caller
    # (SyncRunner, Rebuild) passes the open ledger.
    class Loader
      TOOL = "nabu-loader"

      # The row-aware batch cap (P37-7): in tx_batch mode a batch also flushes
      # once its buffered documents carry this many PASSAGES, so the grain is
      # bounded in rows, not just documents. Why: the P36-2 doc-count grain
      # let mega-document sources (kanripo/cbeta/diorisis/ud — thousands of
      # passages per document) pile hundreds of MBs into ONE transaction, and
      # the per-document savepoints' statement journal — held in RAM under the
      # rebuild pragmas' temp_store=MEMORY — grows with the whole transaction
      # (measured ×1.8 at fixture scale, ×1.6–3.4 live: the mega-source load
      # regression). 10k rows keeps a transaction's dirty set tens-of-MBs; the
      # extra commits are near-free under the rebuild profile's
      # synchronous=OFF, and many-docs-few-passages sources still batch by
      # document count exactly as before.
      TX_BATCH_ROWS = 10_000

      # db: the Sequel database (Store.setup! already applied);
      # source: the Store::Source row this load belongs to;
      # ledger: the history ledger db (Ledger.setup! applied) or nil.
      # profile: a Nabu::RebuildProfile (P36-0) or nil — when present, the
      #   parse call and the per-document insert transaction each fold their
      #   wall time into the source's :parse / :insert component buckets. nil on
      #   the sync path, so only `nabu rebuild` pays the (per-document) sampling.
      # tx_batch: nil (default, the sync path) keeps ONE top-level transaction
      #   per document. An Integer (rebuild only) batches up to that many parsed
      #   documents into a SINGLE transaction, each under a per-document
      #   SAVEPOINT — so a constraint-violating document still rolls back only
      #   itself while the batch's siblings commit together (P36-2). Collapsing
      #   ~N per-document commits into N/batch is the bulk-load win; the fixed
      #   batch (rather than one transaction for a whole mega-source) bounds the
      #   uncommitted WAL frames a 353k-document source would otherwise pile up.
      # tx_batch_rows (P37-7, batch mode only): the companion PASSAGE-row cap —
      #   a batch flushes when either bound fills, so mega-document sources
      #   cannot turn the document grain into a multi-GB transaction (see
      #   TX_BATCH_ROWS for the measured why).
      def initialize(db:, source:, ledger: nil, profile: nil, tx_batch: nil, tx_batch_rows: TX_BATCH_ROWS)
        @db = db
        @source = source
        @ledger = ledger
        @profile = profile
        @tx_batch = tx_batch
        @tx_batch_rows = tx_batch_rows
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

      # discover → parse → load straight off an adapter, attic included
      # (Adapter#discover_with_attic): retained refs load as retired
      # documents, attic duplicates of live urns are journaled "superseded".
      # Nabu::ParseError quarantines that document (journaled, counted as
      # errored) and the batch continues; any other Nabu::Error (fetch-level
      # trouble) propagates and aborts. +on_document+ ticks after every
      # processed OR quarantined document (see #load).
      def load_from(adapter, workdir:, full: true, on_document: nil)
        run(full: full, on_document: on_document) do |process, quarantine, skip|
          adapter.discover_with_attic(workdir, on_superseded: method(:journal_superseded)).each do |ref|
            document =
              begin
                time_parse { adapter.parse(ref) }
              rescue Nabu::DocumentSkipped => e
                skip.call(ref, e)
                next
              rescue Nabu::ParseError => e
                quarantine.call(ref, e)
                next
              end
            process.call(document, retained_params(ref))
          end
        end
      end

      private

      # P36-0 stage timers: no-op (just yield) without a profile, so the sync
      # path is untouched; under `nabu rebuild` they fold the call's wall time
      # into this source's parse / insert component buckets. Per DOCUMENT, not
      # per passage — the always-on granularity the profiler budget allows.
      def time_parse(&) = @profile ? @profile.measure(scope: @source.slug, stage: :parse, &) : yield

      def time_insert(&) = @profile ? @profile.measure(scope: @source.slug, stage: :insert, &) : yield

      def run(full:, on_document: nil)
        counts = Hash.new(0)
        seen_urns = Set.new
        processed = 0
        tick = lambda do
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        # P36-2 batch buffer: in tx_batch mode, parsed documents accumulate here
        # and #flush_batch persists up to tx_batch of them in one transaction
        # (each a savepoint). nil tx_batch never buffers — the sync path keeps
        # its per-document transaction exactly. #flush ticks per document AFTER
        # it lands, preserving the P2-6 "one running-count tick per document"
        # contract; quarantine/skip flush first so ticks stay in input order.
        buffer = []
        buffered_rows = 0
        flush = lambda do
          flush_batch(buffer, counts, tick)
          buffered_rows = 0
        end
        process = lambda do |document, retained = nil|
          # Even a document that fails to persist was present upstream, so its
          # urn still shields the existing row from the withdrawal sweep.
          seen_urns.add(document.urn)
          if @tx_batch
            buffer << [document, retained]
            buffered_rows += document.size
            flush.call if buffer.size >= @tx_batch || buffered_rows >= @tx_batch_rows
          else
            load_document(document, counts, retained)
            tick.call
          end
        end
        # A quarantined ref's document is still PRESENT upstream — only its
        # parse failed — so its urn shields any held row from the withdrawal
        # sweep (P37-r2: the KR5-wave incident withdrew 102 held kanripo
        # texts because a stricter parser quarantined them; recognition
        # getting stricter must never unserve held content). ref.id is the
        # document urn by the adapter contract (Adapter#discover_with_attic).
        quarantine = lambda do |ref, error|
          flush.call
          counts[:errored] += 1
          seen_urns.add(ref.id)
          journal(event: "quarantined", params: { "ref_id" => ref.id, "error" => error.message })
          tick.call
        end
        # A discovered ref the parser declined by rule (Nabu::DocumentSkipped):
        # counted honestly, never quarantined and never journaled per-file — the
        # steady-state catalog-only skeletons must not spam provenance every sync
        # (the 0-byte case's stance). Its urn still shields any existing row from
        # the withdrawal sweep, exactly as a quarantined ref does.
        skip = lambda do |ref, _reason|
          flush.call
          counts[:skipped_by_rule] += 1
          seen_urns.add(ref.id)
          tick.call
        end
        yield(process, quarantine, skip)
        flush.call
        sweep_withdrawn(seen_urns, counts) if full
        LoadReport.new(
          added: counts[:added], updated: counts[:updated], skipped: counts[:skipped],
          withdrawn: counts[:withdrawn], errored: counts[:errored],
          skipped_by_rule: counts[:skipped_by_rule]
        )
      end

      # Persist one buffered batch (P36-2) inside a SINGLE transaction, each
      # document under a savepoint, ticking after each lands. The whole flush
      # is timed as this source's :insert (one measure, not per document — the
      # savepoint path deliberately does not re-time, so nothing double-counts).
      # A no-op when the buffer is empty; clears it either way.
      def flush_batch(buffer, counts, tick)
        return if buffer.empty?

        time_insert do
          @db.transaction do
            buffer.each do |document, retained|
              load_document(document, counts, retained, savepoint: true)
              tick.call
            end
          end
        end
        buffer.clear
      end

      # Persist one document in its own transaction (sync path) or, when
      # +savepoint+ (rebuild batch), in a SAVEPOINT nested in the caller's batch
      # transaction. Either way a constraint violation rolls back only this
      # document (savepoint release for the batch), is journaled, and the batch
      # moves on. Only the top-level (sync) path times itself as :insert — in a
      # batch the enclosing #flush_batch already does. +retained+ is nil for live
      # documents, or the "retired" provenance params for attic rediscoveries.
      def load_document(document, counts, retained = nil, savepoint: false)
        txn = -> { @db.transaction(savepoint: savepoint) { upsert_document(document, retained) } }
        outcome = savepoint ? txn.call : time_insert(&txn)
        counts[outcome] += 1
      rescue Sequel::DatabaseError => e
        counts[:errored] += 1
        journal(event: "quarantined", params: { "urn" => document.urn, "error" => e.message })
      end

      def upsert_document(document, retained)
        passages = document.passages
        passage_shas = passages.to_h { |passage| [passage.urn, ContentHash.passage(passage)] }
        doc_sha = ContentHash.document(document, passage_shas.values)

        row = Document.first(source_id: @source.id, urn: document.urn)
        return insert_document(document, passage_shas, doc_sha, retained) if row.nil?

        if row.content_sha256 == doc_sha
          # Unchanged content: no revision bump, no passage work — only the
          # visibility flags, the license override (metadata, P10-4) and the
          # document metadata (P17-2) may need reconciling.
          restored = row.withdrawn && restore(row)
          relabeled = reconcile_license_override?(row, document)
          remetadata = reconcile_metadata?(row, document)
          return :skipped unless reconcile_retirement?(row, retained) || restored || relabeled || remetadata
        else
          revise_document(row, document, passage_shas, doc_sha, retained)
        end
        :updated
      end

      # Same-content path: bring documents.license_override into line with what
      # the adapter now declares (P10-4). A pure metadata update — no revision
      # bump, content_sha256 untouched — so a license relabel (or an override
      # removed upstream, reverting to NULL) never fakes a content change.
      # Returns whether it changed anything.
      def reconcile_license_override?(row, document)
        return false if row.license_override == document.license_override

        row.update(license_override: document.license_override)
        true
      end

      # Same-content path, P17-2: bring documents.metadata_json into line with
      # the adapter-emitted Document#metadata. Like the license override it is
      # METADATA, never content — no revision bump, content_sha256 untouched —
      # so a persons/crosswalk refresh (a corrected pers CSV) never fakes a
      # content revision. Returns whether it changed anything.
      def reconcile_metadata?(row, document)
        json = ContentHash.canonical_json(document.metadata)
        return false if row.metadata_json == json

        row.update(metadata_json: json)
        true
      end

      def insert_document(document, passage_shas, doc_sha, retained)
        row = Document.create(
          source_id: @source.id, urn: document.urn, title: document.title,
          language: document.language, canonical_path: document.canonical_path,
          license_override: document.license_override,
          metadata_json: ContentHash.canonical_json(document.metadata),
          content_sha256: doc_sha, revision: 1, withdrawn: false, retired_upstream: !retained.nil?
        )
        journal(event: "loaded", document_id: row.id)
        # durable: false — an insert is not a transition (see class comment).
        journal_retirement_flip(row, false, retained, durable: false)
        document.passages.each { |passage| insert_passage(row.id, passage, passage_shas.fetch(passage.urn)) }
        :added
      end

      def revise_document(row, document, passage_shas, doc_sha, retained)
        old_sha = row.content_sha256
        was_withdrawn = row.withdrawn
        was_retired = row.retired_upstream
        row.update(
          title: document.title, language: document.language, canonical_path: document.canonical_path,
          license_override: document.license_override,
          metadata_json: ContentHash.canonical_json(document.metadata),
          content_sha256: doc_sha, revision: row.revision + 1, withdrawn: false,
          retired_upstream: !retained.nil?
        )
        journal(event: "revised", document_id: row.id, params: { "old_sha" => old_sha, "new_sha" => doc_sha })
        durable(event: "revised", urn: row.urn, old_sha: old_sha, new_sha: doc_sha)
        if was_withdrawn
          journal(event: "restored", document_id: row.id)
          durable(event: "restored", urn: row.urn, new_sha: doc_sha)
        end
        journal_retirement_flip(row, was_retired, retained)
        upsert_passages(row, document, passage_shas)
      end

      # -- retention (P5-2) ----------------------------------------------------

      # The "retired" provenance params for an attic ref, or nil for a live
      # one. The upstream sha the file vanished at rides in the ref metadata
      # when the fetch layer's attic manifest recorded it (GitFetch); without
      # it the retirement is journaled without params — a documented decision:
      # the loader stays fetch-independent, so rebuilds replay identically.
      def retained_params(ref)
        return nil unless ref.metadata[Nabu::Adapter::RETAINED_KEY]

        sha = ref.metadata[Nabu::Adapter::RETIRED_SHA_KEY]
        sha ? { "upstream_sha" => sha } : {}
      end

      # Same-content path: flip retired_upstream when where-we-found-it
      # (attic vs live) disagrees with the row. Returns whether it changed.
      def reconcile_retirement?(row, retained)
        return false if row.retired_upstream == !retained.nil?

        was_retired = row.retired_upstream
        row.update(retired_upstream: !retained.nil?)
        journal_retirement_flip(row, was_retired, retained)
        true
      end

      def journal_retirement_flip(row, was_retired, retained, durable: true)
        return if was_retired == !retained.nil?

        if retained
          journal(event: "retired", document_id: row.id, params: retained.empty? ? nil : retained)
          durable(event: "retired", urn: row.urn) if durable
        else
          journal(event: "unretired", document_id: row.id)
          durable(event: "unretired", urn: row.urn) if durable
        end
      end

      # An attic duplicate of a urn that is also live (Adapter's live-wins
      # dedup): journal it once so restructures are visible, then stay silent
      # — a steady live+attic pair must not grow provenance every sync.
      def journal_superseded(ref)
        row = Document.first(source_id: @source.id, urn: ref.id)
        params = { "ref_id" => ref.id, "attic_path" => ref.path }
        return if row && already_superseded?(row.id, params)

        journal(event: "superseded", document_id: row&.id, params: params)
      end

      def already_superseded?(document_id, params)
        !Provenance.where(document_id: document_id, event: "superseded",
                          params_json: JSON.generate(params)).empty?
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
        durable(event: "revised", urn: row.urn, old_sha: old_sha, new_sha: sha)
        return unless was_withdrawn

        journal(event: "restored", passage_id: row.id)
        durable(event: "restored", urn: row.urn, new_sha: sha)
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
            durable(event: "withdrawn", urn: row.urn, old_sha: row.content_sha256)
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
        durable(event: "restored", urn: row.urn, new_sha: row.content_sha256)
      end

      # Full loads assert completeness: this source's active documents whose
      # urns the batch never produced are withdrawn (never hard-deleted), in
      # one final transaction of their own.
      def sweep_withdrawn(seen_urns, counts)
        @db.transaction do
          Document.where(source_id: @source.id, withdrawn: false)
                  .select_map(%i[id urn content_sha256]).each do |id, urn, sha|
            next if seen_urns.include?(urn)

            Document.where(id: id).update(withdrawn: true)
            journal(event: "withdrawn", document_id: id)
            durable(event: "withdrawn", urn: urn, old_sha: sha)
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

      # One urn-keyed row in the history ledger's revisions table (see class
      # comment). No-op without a ledger.
      def durable(event:, urn:, old_sha: nil, new_sha: nil)
        return unless @ledger

        Revision.create(urn: urn, event: event, old_sha: old_sha, new_sha: new_sha, at: Time.now)
      end
    end
  end
end
