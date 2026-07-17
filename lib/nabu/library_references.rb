# frozen_string_literal: true

require "json"

module Nabu
  # Producer #4 for the links journal (P19-4, architecture §15/§16): the
  # local-library manifests' `related:` urns as kind=reference edges — a
  # scholarly article becomes a navigable neighbor of the passages (or
  # documents) it discusses, so `nabu links <urn>` shows it beside them.
  #
  # == Why the links journal (and not catalog metadata alone)
  #
  # The related targets DO ride in Document#metadata (the manifest is the
  # record), but metadata is only findable from the article's side. An edge
  # is bidirectional journal truth: `links` on the DISCUSSED passage
  # surfaces the article too. Like every producer, edges here are a pure
  # function of (canonical, code): re-derived from the loaded documents'
  # metadata after every local-library sync, superseding the prior run —
  # the journal always holds the current manifests' assertions. Rebuild
  # never touches the journal (§15); a lost journal costs one no-network
  # re-sync of the shelf.
  #
  # == Urns only — the language-code verdict
  #
  # `related:` also admits language codes ("chu"). P19-1 minted NO urns for
  # language dossiers (language_records are (code, kind) rows, not
  # documents), so a code has no journal-addressable target: minting an
  # edge to an invented urn would sit permanently "(not in catalog)" — the
  # unresolved-counterpart state exists for edges that OUTLIVED catalog
  # rows, not ones that never had any. Codes therefore stay document
  # metadata (searchable, shown by `show`); if a later packet mints dossier
  # documents, codes upgrade here. They are counted (+skipped_codes+) so
  # the summary stays honest. The edge-worthiness rule (P25-1, generalized
  # for the concordance sources): a target carrying a scheme — an ":" —
  # names a stable id space (urn:, https://dil.ie/…, rig:G593) and mints
  # an edge; a bare ":"-less string is a code and stays metadata.
  #
  # == Edge shape
  #
  # from_urn = the asserting document urn; to_urn = the related target
  # verbatim (document/passage urn or external stable id — Query::Links
  # resolves catalog urns; an external id renders "(not in catalog)"
  # honestly); score nil (a curated assertion is not a mined similarity —
  # no fake number); detail carries the provenance: the collection
  # manifest (or source slug, for the P25-1 concordance producers) that
  # asserted the edge.
  class LibraryReferences
    PRODUCER = "library"
    KIND = "reference"
    CODE_VERSION = "library-references/1 nabu/#{VERSION}".freeze

    # What one refresh did. +edges_written+/+edges_refreshed+ mirror the
    # batch producers; +skipped_codes+ counts related language codes (kept
    # as metadata, never edges — class comment).
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_codes)

    # +producer+ names the links-journal producer this instance records
    # under — "library" (the P19-4 manifests) by default; the concordance
    # sources (riig/ogham) construct with their own name via their
    # Adapter.reference_producer override (the P25-0 object seam).
    def initialize(catalog:, journal:, producer: PRODUCER)
      @catalog = catalog
      @journal = journal
      @producer = producer
    end

    # The name this instance records under (test-inspectable).
    attr_reader :producer

    # Re-derive every reference edge for the source at +slug+ from its
    # loaded documents' metadata, recorded under +producer+ (the adapter's
    # Adapter.reference_producer — "library" for the P19-4 manifests, the
    # source's own name for the P25-1 concordance sources). Supersedes the
    # prior (producer, scope) run atomically — deleted assertions drop
    # their edges.
    def run(slug, producer: @producer)
      counts = { inserted: 0, refreshed: 0, codes: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: producer, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: producer, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(slug, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_codes: counts[:codes])
    end

    private

    def write_edges(slug, run_id, counts)
      related_documents(slug).each do |urn, metadata|
        detail = provenance_detail(slug, metadata)
        Array(metadata["related"]).each do |target|
          unless target.include?(":") # scheme-less = a bare code (class note)
            counts[:codes] += 1
            next
          end
          outcome = Store::LinksJournal.write_edge!(@journal, from_urn: urn, to_urn: target,
                                                              kind: KIND, score: nil, run_id: run_id, detail: detail)
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end
    end

    # Non-withdrawn documents of this source whose metadata carries related
    # targets, urn-ordered for determinism.
    def related_documents(slug)
      @catalog[:documents]
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn])
        .select_map([Sequel[:documents][:urn], Sequel[:documents][:metadata_json]])
        .filter_map do |urn, json|
          metadata = json ? JSON.parse(json) : {}
          [urn, metadata] unless Array(metadata["related"]).empty?
        end
    end

    # "canonical/local-library/<collection>/manifest.yml" — the manifest
    # that asserted the edge (provenance = the manifest).
    def provenance_detail(slug, metadata)
      collection = metadata["collection"]
      collection ? "manifest #{slug}/#{collection}/manifest.yml" : "manifest #{slug}"
    end
  end
end
