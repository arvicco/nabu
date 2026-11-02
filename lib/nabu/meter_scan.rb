# frozen_string_literal: true

module Nabu
  # The scansion CAMPAIGN (P152): Nabu::Scansion over the catalog's live
  # Latin/Greek passages, its verdicts landed on the local-meter shelf
  # through the Nabu::MeterShelf gateway — driven only by `nabu scan-meter
  # --run` (heavy-derived under the cost law: never a rebuild stage; the
  # architecture §16 shelf-eight note carries the measured reasoning).
  # Reads the catalog, never writes it.
  #
  # == The verse gate (why prose never reaches the shelf)
  #
  # The library does not say which documents are verse, and a short prose
  # sentence can fit a hexameter template by accident. So the unit of
  # admission is the DOCUMENT: its passages are scanned in order, and only
  # a document where at least VERSE_GATE of the passages scan is verse —
  # its passage records (scanned and unscanned alike) are shelved. Any
  # other document shelves ONE document record with its counts (the gate's
  # verdict, which a resumed campaign skips), and the first PROBE passages
  # all failing ends the document early (prose costs a probe, not a pass).
  # Passages over Scansion::MAX_LINE_CHARS are not lines and never reach
  # the syllabifier.
  #
  # == Resumable, delta-only
  #
  # A passage whose latest shelf record carries the current scanner
  # version AND its current content_sha256 is done; a document whose gate
  # record carries the current version is done. Re-firing the same command
  # after an interruption — or after a sync moved some texts — scans only
  # what is new or stale. Records flush to the shelf every FLUSH records,
  # so an interruption loses at most one unflushed batch.
  class MeterScan
    VERSE_GATE = 0.5
    PROBE = 50
    FLUSH = 5_000

    Report = Data.define(:documents, :verse_documents, :gated_documents, :current_documents, :passages,
                         :scanned, :records, :shards, :seconds)

    def initialize(catalog:, shelf:, now: -> { Time.now })
      @catalog = catalog
      @shelf = shelf
      @now = now
    end

    # Scan the scope: +language+ (lat/grc, default both), +source+ (a
    # registry slug), +urn_prefix+ (a document urn prefix). +progress+ is
    # called with (documents_done, documents_total) after each document.
    def run(language: nil, source: nil, urn_prefix: nil, progress: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      done_passages, done_documents = current_state
      documents = candidate_documents(language, source, urn_prefix)
      counts = Hash.new(0)
      @buffer = []
      @shards = 0
      documents.each_with_index do |document, i|
        counts[:documents] += 1
        if done_documents[document[:urn]]
          counts[:current_documents] += 1
        else
          scan_document(document, language, done_passages, counts)
        end
        progress&.call(i + 1, documents.size)
      end
      flush!
      Report.new(documents: counts[:documents], verse_documents: counts[:verse], gated_documents: counts[:gated],
                 current_documents: counts[:current_documents], passages: counts[:passages],
                 scanned: counts[:scanned], records: counts[:records], shards: @shards,
                 seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    # The candidate passage census for a scope (the cost estimate's
    # numerator): live lat/grc passages of live documents.
    def candidate_passages(language: nil, source: nil, urn_prefix: nil)
      ids = candidate_documents(language, source, urn_prefix).map { |d| d[:id] }
      ids.each_slice(5_000).sum do |slice|
        @catalog[:passages].where(document_id: slice, withdrawn: false, language: languages(language)).count
      end
    end

    private

    def languages(language) = language ? [language] : Scansion::LANGUAGES

    # [{ urn => sha } for current passage records, { urn => true } for
    # current document gate records] — the resume state.
    def current_state
      passages = {}
      documents = {}
      @shelf.latest_by_urn.each_value do |record|
        next unless record.scanner_version == Scansion::VERSION

        record.passage? ? passages[record.urn] = record.content_sha256 : documents[record.urn] = true
      end
      [passages, documents]
    end

    def candidate_documents(language, source, urn_prefix)
      dataset = @catalog[:documents].where(Sequel[:documents][:withdrawn] => false,
                                           Sequel[:documents][:language] => languages(language))
      if source
        dataset = dataset.join(:sources, id: Sequel[:documents][:source_id]).where(Sequel[:sources][:slug] => source)
      end
      dataset = dataset.where(Sequel.like(Sequel[:documents][:urn], "#{urn_prefix}%")) if urn_prefix
      dataset.order(Sequel[:documents][:urn]).select(Sequel[:documents][:id], Sequel[:documents][:urn]).all
    end

    def scan_document(document, language, done_passages, counts)
      dataset = @catalog[:passages].where(document_id: document[:id], withdrawn: false,
                                          language: languages(language))
                                   .order(:sequence).select(:urn, :text, :language, :content_sha256)
      # The probe reads only PROBE rows: a prose document never streams
      # its whole text through the campaign.
      results = scan_rows(dataset.limit(PROBE).all)
      return if results.empty?

      if results.size == PROBE && results.none? { |(_, r)| r.scanned? }
        counts[:passages] += results.size
        counts[:gated] += 1
        shelve(document_record(document, dataset.count, 0), counts)
        return
      end

      results.concat(scan_rows(dataset.offset(PROBE).all)) if results.size == PROBE
      scanned = results.count { |(_, r)| r.scanned? }
      counts[:passages] += results.size
      if scanned < VERSE_GATE * results.size
        counts[:gated] += 1
        shelve(document_record(document, results.size, scanned), counts)
        return
      end

      counts[:verse] += 1
      counts[:scanned] += scanned
      results.each do |passage, result|
        next if done_passages[passage[:urn]] == passage[:content_sha256]

        shelve(passage_record(passage, result), counts)
      end
    end

    def scan_rows(rows)
      rows.map { |passage| [passage, Scansion.scan(passage[:text], language: passage[:language])] }
    end

    def passage_record(passage, result)
      fields = { kind: "passage", urn: passage[:urn], language: passage[:language],
                 content_sha256: passage[:content_sha256], scanner: Scansion::SCANNER,
                 scanner_version: Scansion::VERSION }
      if result.scanned?
        MeterShelf::Record.new(**fields, status: "scanned", meter: result.meter.to_s, feet: result.feet,
                                         quantities: result.quantities, word_pattern: result.word_pattern,
                                         basis: result.basis.to_s)
      else
        MeterShelf::Record.new(**fields, status: "unscanned", reason: result.reason.to_s)
      end
    end

    def document_record(document, passages, scanned)
      MeterShelf::Record.new(kind: "document", urn: document[:urn], passages: passages, scanned: scanned,
                             scanner: Scansion::SCANNER, scanner_version: Scansion::VERSION)
    end

    def shelve(record, counts)
      @buffer << record
      counts[:records] += 1
      flush! if @buffer.size >= FLUSH
    end

    def flush!
      return if @buffer.empty?

      @shelf.append_batch!(records: @buffer, now: @now.call)
      @shards += 1
      @buffer = []
    end
  end
end
