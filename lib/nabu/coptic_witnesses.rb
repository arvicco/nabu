# frozen_string_literal: true

require "json"

require_relative "library_references"

module Nabu
  # Producer #14 for the links journal: Coptic Scriptorium's upstream-
  # asserted PARALLEL WITNESSES (architecture §15). A TT header's `witness`
  # field names the other manuscript(s) carrying the same stretch of text —
  # MONB.GL vs MONB.XJ of Shenoute's I See Your Eagerness, the Budge
  # Encomium on Michael in BL Or. 6781 vs its twin — as CTS urns. Each named
  # urn becomes one kind=parallel-witness edge between the two manuscripts'
  # documents, so `nabu links` walks from one witness to the other. The
  # documents stay separate (two manuscripts, two texts); the edge only says
  # "same text, other witness", upstream's own hand-asserted claim.
  #
  # == The censused field (catalog @ v6.2.0, 482 documents, 2026-10-22)
  #
  # 89 documents carry `witness`; 12 say "none" (the survey's "77 docs carry
  # witness" = the other 77). 32 name at least one CTS urn — 34 urn refs, 18
  # distinct document pairs (most pairs are asserted from BOTH sides), every
  # one resolving to a held document (one of them a same-manuscript
  # continuation, below). The other 57 are prose: "none",
  # "unique" (the magical papyri), "no known extant parallel witnesses", or
  # notes naming MONB sigla Coptic Scriptorium has not published ("MONB.XO
  # 80-82 … not published"). A siglum is not a stable id space (the P25-1
  # edge-worthiness rule), so prose mints nothing and is counted
  # (+witness_prose+). Urns may sit inside prose ("Beginning has parallel
  # with urn:cts:…:10-18. End has parallel with …") and beside sigla
  # ("urn:cts:…monbxj_77_86, MONB.DD 219-220 (not published…)"); the
  # extraction (Adapters::CopticScriptorium.witness_targets) takes every
  # urn wherever it sits and maps it through the adapter's own frozen
  # document minting.
  #
  # == Same-manuscript continuations are not witnesses
  #
  # ONE censused urn is not a parallel at all: MONB.GL 29's note says the
  # REST of MONB.GL 29-30 "is in urn:cts:…monbgl_29_30" — the same codex,
  # continued in the next document. A named urn whose work and codex
  # siglum (the edition segment minus its page suffix: monbgl_29 →
  # monbgl) match the asserting document's is a continuation: no edge,
  # counted (+witness_same_manuscript+). Distinct codices of one work
  # (monbgl vs monbxj, Budge's ai vs al) stay witnesses. Over the v6.2.0
  # catalog: 34 named urns → 1 continuation + 33 witness assertions → 17
  # edges (16 mutual pairs + monbxl → monbya), all resolving.
  #
  # == Edge shape and the honest census
  #
  # from_urn = the asserting document, to_urn = the named witness; one edge
  # per unordered pair (a mutual assertion is one edge, detail "(asserted
  # by both)"); score nil; detail "witness <the upstream urn verbatim>". A
  # named urn the catalog does not hold STILL mints — it is upstream's own
  # stable id space, and the edge resolves the day that document loads
  # (`links` renders it "(not in catalog)" meanwhile) — and is counted in
  # +unknown_ids+ (the sync tail's "?N unknown upstream"), never dropped.
  #
  # == One producer, two edge families
  #
  # The adapter's reference producer already carried the header's
  # Trismegistos numbers as "tm:<n>" kind=reference edges (LibraryReferences
  # over metadata "related", P104-1). A source has ONE reference producer
  # and a run supersedes its whole (producer, scope), so this class extends
  # that producer rather than standing beside it: one run per sync writes
  # both families under the producer name "coptic-scriptorium". A pure
  # function of catalog rows, like its parent.
  class CopticWitnesses < LibraryReferences
    PRODUCER = "coptic-scriptorium"
    KIND = "parallel-witness"
    CODE_VERSION = "coptic-witnesses/1 nabu/#{VERSION}".freeze

    # The parent's Result plus the witness census (class note); unknown_ids
    # = named urns the catalog does not hold.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_codes,
                         :witness_documents, :witness_prose, :witness_asserted,
                         :witness_resolved, :witness_same_manuscript, :unknown_ids)

    def initialize(catalog:, journal:)
      super(catalog: catalog, journal: journal, producer: PRODUCER)
    end

    def run(slug, producer: @producer, workdir: nil)
      @census = Hash.new(0)
      base = super
      Result.new(**base.to_h,
                 witness_documents: @census[:documents], witness_prose: @census[:prose],
                 witness_asserted: @census[:asserted], witness_resolved: @census[:resolved],
                 witness_same_manuscript: @census[:same_manuscript],
                 unknown_ids: @census[:asserted] - @census[:resolved])
    end

    private

    # The parent's reference edges, then the witness edges — inside the
    # parent's one transaction and run.
    def write_edges(slug, run_id, counts)
      super
      pairs = witness_pairs(slug)
      held = held_urns(pairs.values.flat_map { |pair| [pair[:from], pair[:to]] }.uniq)
      pairs.each_value do |pair|
        pair[:targets].each { |target| @census[:resolved] += 1 if held.include?(target) }
        outcome = Store::LinksJournal.write_edge!(@journal, from_urn: pair[:from], to_urn: pair[:to],
                                                            kind: KIND, score: nil, run_id: run_id,
                                                            detail: witness_detail(pair))
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end

    # sorted pair => { from:, to:, cts: the first-seen upstream urn,
    # asserters: [documents naming the pair], targets: [the urn each
    # assertion named] }, urn order — the in-memory dedup that keeps a
    # mutual assertion one edge.
    def witness_pairs(slug)
      witness_documents(slug).each_with_object({}) do |(urn, value), pairs|
        named = Adapters::CopticScriptorium.witness_cts(value)
        if named.empty?
          @census[:prose] += 1
          next
        end
        @census[:documents] += 1
        named.each do |cts|
          target = Adapters::CopticScriptorium.cts_document_urn(cts)
          next if target == urn

          if same_manuscript?(urn, target)
            @census[:same_manuscript] += 1
            next
          end
          @census[:asserted] += 1
          pair = pairs[[urn, target].sort] ||= { from: urn, to: target, cts: cts, asserters: [], targets: [] }
          pair[:asserters] << urn
          pair[:targets] << target
        end
      end
    end

    # Same work, same codex: the edition segment with its page suffix
    # dropped ("monbgl_29" and "monbgl_29_30" are both MONB.GL; "budge_ai_ed"
    # and "budge_al_ed" stay two manuscripts). Class note.
    def same_manuscript?(urn, other)
      manuscript_key(urn) == manuscript_key(other)
    end

    def manuscript_key(urn)
      work = urn.delete_prefix(Adapters::CopticScriptorium::URN_PREFIX).sub(/\Aurn:cts:\w+:/, "").split(":").first
      *head, edition = work.split(".")
      [*head, edition.to_s.sub(/(?:_\d+)+\z/, "")].join(".")
    end

    def witness_detail(pair)
      mutual = pair[:asserters].uniq.size > 1
      "witness #{pair[:cts]}#{' (asserted by both)' if mutual}"
    end

    # Non-withdrawn documents of this source carrying a witness value, urn
    # order (determinism).
    def witness_documents(slug)
      @catalog[:documents]
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn])
        .select_map([Sequel[:documents][:urn], Sequel[:documents][:metadata_json]])
        .filter_map do |urn, json|
          value = (json ? JSON.parse(json) : {})["witness"]
          [urn, value] if value.is_a?(String) && !value.strip.empty?
        end
    end

    def held_urns(urns)
      @catalog[:documents].where(urn: urns, withdrawn: false).select_map(:urn).to_set
    end
  end
end
