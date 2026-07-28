# frozen_string_literal: true

require "json"

require_relative "adapters/e84000_tei_parser"

module Nabu
  # Producer #10 for the links journal (P48-6): the Kangyur↔84000 translation
  # crosswalk. Every published 84000 English translation names the Derge
  # text(s) it translates by Tohoku number — the P48-2 parser mines the
  # sourceDesc <bibl @key> list into document metadata ("toh" verbatim,
  # part-suffix-stripped bases in "toh_base", the pinned P48-6 join key) —
  # so each (publication, toh base) pair becomes a kind=translation edge
  # urn:nabu:e84000:toh<slug> ↔ urn:nabu:derge-(kangyur|tengyur):toh<base>,
  # and `nabu links` serves the Kangyur↔English hop from either side.
  #
  # == The join, stated exactly (the frozen P48 crosswalk contract)
  #
  # The derge shelves mint documents by Toh number in the SAME slug grammar
  # (toh1, toh846a — P48-1), including {D1}{D1-1} CONTAINER documents for
  # every base number, so each toh_base resolves to a real derge document
  # once its shelf is synced: a part publication (e84000:toh1-1) joins the
  # toh1 container; a multi-Toh file (94 upstream) fans out one edge per
  # base. The shelf is routed by the publication's own "collection" metadata
  # (kangyur → derge-kangyur, tengyur → derge-tengyur) — never guessed from
  # number ranges. Documents without toh_base metadata or with a collection
  # outside the map mint nothing and are counted (+skipped_unmapped+, the
  # honesty counter).
  #
  # == Edge shape
  #
  # from_urn = the 84000 publication (the side carrying the Toh keys — the
  # ud-kanripo asserting-side rule); to_urn = the derge document; score nil
  # (a curated translation record is not a mined similarity — no fake
  # number); detail = "translates toh846a — The Threefold Ritual" (the base,
  # the part key that carried the join when it differs, and the 84000 title
  # — readable while the derge side is still unsynced). Edges mint whether
  # or not the derge shelves are in the catalog (the P32-6
  # dangling-but-stable precedent): `nabu links` renders unminted
  # counterparts "(not in catalog)" honestly and they resolve the day the
  # owner syncs the Kangyur.
  #
  # == Why the ref grain stops at documents (the honest limit)
  #
  # 84000 passages cite the Reading Room's own section.paragraph labels
  # (s.1 / i.3 / 1.5); the Derge shelves cite woodblock folio page.line.
  # The two citation systems share no vocabulary and upstream publishes no
  # token- or folio-level alignment, so document grain is the strongest
  # claim the data supports — a passage-grain edge here would be invented.
  #
  # == Refresh mechanics (the standing producer contract)
  #
  # Edges are a pure function of (loaded e84000 catalog rows, code):
  # SyncRunner re-runs this producer after every e84000 sync via the
  # reference_producer seam, superseding the prior (producer, scope) run
  # atomically. A catalog without e84000 documents — every parse-only sync
  # before the first fetch — is a no-op that supersedes NOTHING, so
  # standing edges survive. A later derge sync needs no re-run: resolution
  # is read-time (Query::Links). Rebuild never touches the journal; losing
  # it costs one parse-only re-sync.
  class E84000Translations
    PRODUCER = "e84000"
    KIND = "translation"
    CODE_VERSION = "e84000-translations/1 nabu/#{VERSION}".freeze

    # The publication's "collection" metadata → the derge shelf it joins
    # (class note: routed by upstream's own cone, never by number ranges).
    SHELF_PREFIXES = {
      "kangyur" => "urn:nabu:derge-kangyur:",
      "tengyur" => "urn:nabu:derge-tengyur:"
    }.freeze

    # What one refresh did — the LibraryReferences::Result shape (so the
    # CLI sync tail renders every producer identically) plus the honesty
    # counter from the class note (unmapped DOCUMENTS, one count each).
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unmapped)

    # +catalog+ supplies the loaded e84000 rows (this producer is
    # catalog-derived — the LibraryReferences posture, not the file-reading
    # P32-6 one); edges mint for unsynced derge texts too (class note).
    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every translation edge from the catalog's e84000 documents,
    # superseding the prior (producer, scope) run. A catalog without e84000
    # rows is the honest no-op (class note). +workdir+ rides the producer
    # seam; everything here derives from the catalog, so it is ignored.
    def run(slug, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      rows = publication_rows(slug)
      return absent_result(slug) if rows.empty?

      counts = Hash.new(0)
      edges = rows.flat_map { |row| row_edges(row, counts) }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unmapped: counts[:unmapped])
    end

    private

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_unmapped: 0)
    end

    # Non-withdrawn e84000 documents, urn-ordered for determinism.
    def publication_rows(slug)
      @catalog[:documents]
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn])
        .select_map([Sequel[:documents][:urn], Sequel[:documents][:title],
                     Sequel[:documents][:metadata_json]])
    end

    # One edge per (publication, toh base). A document the map cannot route
    # — no toh_base metadata, or an unknown collection — counts once and
    # mints nothing (class note).
    def row_edges((urn, title, metadata_json), counts)
      metadata = metadata_json ? JSON.parse(metadata_json) : {}
      bases = Array(metadata["toh_base"])
      prefix = SHELF_PREFIXES[metadata["collection"]]
      if bases.empty? || prefix.nil?
        counts[:unmapped] += 1
        return []
      end

      keys = Array(metadata["toh"])
      bases.map do |base|
        { from: urn, to: "#{prefix}#{base}", detail: detail_for(base, keys, title) }
      end
    end

    # "translates toh1 (via toh1-1) — The Chapter on Going Forth": the base,
    # the part key(s) that carried the join when they differ from it, and
    # the 84000 title (class note).
    def detail_for(base, keys, title)
      via = keys.select { |key| key != base && Adapters::E84000TeiParser.toh_base(key) == base }
      detail = "translates #{base}"
      detail << " (via #{via.join(', ')})" unless via.empty?
      detail << " — #{title}" if title && !title.empty?
      detail
    end

    def write_edges(edges, run_id, counts)
      edges.each do |edge|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: edge[:from], to_urn: edge[:to],
                    kind: KIND, score: nil, run_id: run_id, detail: edge[:detail]
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end
