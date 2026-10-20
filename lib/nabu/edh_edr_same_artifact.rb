# frozen_string_literal: true

require "json"

require_relative "place_refs"

module Nabu
  # The EDH ↔ EDR same-artifact concordance (a slug-scoped reference
  # producer, architecture §15). EDH (the provinces) and EDR (Italy) overlap
  # where an Italian inscription was edited by both projects: the two
  # records are two EDITIONS of one physical object. Both upstreams record
  # the object's Trismegistos text number — EDH in edh_data_text.csv
  # `tm_nr`, EDR in `<idno type="TM">` — and both parsers carry it as the
  # top-level `tm_nr` document metadata. Joining on it, this producer mints
  # one kind=same-artifact edge per (EDH document, EDR document) pair
  # sharing a TM number, edh → edr. Documents are NEVER merged: each edition
  # stays its own document with its own text; the edge says "same stone".
  #
  # Measured on the live catalog 2026-10-20 (read-only, json_extract over
  # documents.metadata_json, withdrawn excluded): EDH 81,881 documents,
  # 76,861 with a TM number (76,425 distinct); EDR 115,590 documents, 60,477
  # with one (59,765 distinct); 10,238 TM numbers shared → 10,420 document
  # pairs (a TM number may sit on more than one record per side — 368 EDH /
  # 569 EDR numbers do — and every cross pair is an edge).
  #
  # == The per-field preferred-witness hint (rides each edge's detail)
  #
  # "Trismegistos <tm> · prefer text=<slug> date=<slug> findspot=<slug>":
  #
  #   text     — the LOWER supplied share wins (Leiden supplied_chars over the
  #              edition's letters/digits — restorations are editorial, not
  #              read); tie → the FULLER text (more letters); tie → edh. A
  #              letterless witness never wins.
  #   date     — the NARROWER range wins (document_axes not_before..not_after;
  #              an undated or open-ended witness is unbounded); tie → edh.
  #   findspot — the witness whose findspot carries a Pleiades id wins
  #              (document_axes.place_ref through Nabu::PlaceRefs, or the
  #              parser's place.pleiades); else — and between two Pleiades
  #              ids — the LONGER findspot description (place.ancient +
  #              findspot) wins; tie → edh.
  #
  # == Refresh mechanics
  #
  # A pure function of catalog rows (documents, passages, document_axes):
  # both adapters declare it (reference_edges?), so a sync of EITHER side
  # re-derives it, and it records ONE (producer, scope) run — the scope is
  # the fixed SCOPE, never the triggering slug — so either sync supersedes
  # the same run. Rebuild's links stage replays it after every load and the
  # timeline/place-apply lanes, so the axes it reads are current.
  class EdhEdrSameArtifact
    PRODUCER = "edh-edr-same-artifact"
    SCOPE = "edh+edr"
    KIND = "same-artifact"
    EDH = "edh"
    EDR = "edr"
    CODE_VERSION = "edh-edr-same-artifact/1 nabu/#{VERSION}".freeze

    # Lookup batch for the per-document reads (well under SQLite's
    # host-parameter limit).
    BATCH = 500

    # The LibraryReferences::Result shape (the sync tail renders every
    # producer alike) plus the join census.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :shared_tm_ids, :pairs)

    # What one edition brings to the preference rule (module note).
    Witness = Data.define(:urn, :slug, :letters, :supplied, :not_before, :not_after, :pleiades, :findspot)

    # The per-field winner (a slug) for text, date and findspot.
    Preference = Data.define(:text, :date, :findspot) do
      def to_s = "prefer text=#{text} date=#{date} findspot=#{findspot}"
    end

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every edge, superseding the one prior run. +slug+ (edh or
    # edr — whichever sync triggered) does not scope anything (module note).
    def run(_slug = nil, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      edh = tm_index(EDH)
      edr = tm_index(EDR)
      shared = (edh.keys & edr.keys).sort_by(&:to_i)
      pairs = shared.flat_map { |tm| edh[tm].product(edr[tm]).map { |a, b| [tm, a, b] } }
      witnesses = witnesses_for(pairs.flat_map { |_, a, b| [a, b] }.uniq)
      write(pairs, witnesses, shared.size)
    end

    # The preference rule over two witnesses (module note), EDH first.
    def self.preference(edh, edr)
      Preference.new(text: text_winner(edh, edr), date: date_winner(edh, edr),
                     findspot: findspot_winner(edh, edr))
    end

    def self.text_winner(edh, edr)
      return edr.slug if edh.letters.zero? && edr.letters.positive?
      return edh.slug if edr.letters.zero?

      # supplied share compared exactly: a/b < c/d ⇔ a·d < c·b
      lhs = edh.supplied * edr.letters
      rhs = edr.supplied * edh.letters
      return edh.slug if lhs < rhs
      return edr.slug if rhs < lhs

      edr.letters > edh.letters ? edr.slug : edh.slug
    end

    def self.date_winner(edh, edr)
      a = width(edh)
      b = width(edr)
      return edh.slug if b.nil? || (a && a <= b)

      edr.slug
    end

    def self.width(witness)
      return nil if witness.not_before.nil? || witness.not_after.nil?

      witness.not_after - witness.not_before
    end

    def self.findspot_winner(edh, edr)
      return edh.slug if edh.pleiades && !edr.pleiades
      return edr.slug if edr.pleiades && !edh.pleiades

      edr.findspot.length > edh.findspot.length ? edr.slug : edh.slug
    end

    private

    # tm number → [urn, …] for one source's live documents.
    def tm_index(slug)
      tm = Sequel.function(:json_extract, :metadata_json, "$.tm_nr")
      @catalog[:documents].join(:sources, id: :source_id)
                          .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
                          .exclude(tm => nil)
                          .select_map([Sequel[:documents][:urn], tm.as(:tm)])
                          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(urn, number), index|
        index[number.to_s.strip] << urn unless number.to_s.strip.empty?
      end
    end

    # urn → Witness for every paired document, read in batches.
    def witnesses_for(urns)
      urns.each_slice(BATCH).with_object({}) do |batch, witnesses|
        docs = @catalog[:documents].join(:sources, id: :source_id)
                                   .where(Sequel[:documents][:urn] => batch)
                                   .select_map([Sequel[:documents][:id], Sequel[:documents][:urn],
                                                Sequel[:documents][:metadata_json], Sequel[:sources][:slug]])
        ids = docs.map(&:first)
        texts = text_stats(ids)
        axes = axes_by_document(ids)
        docs.each do |id, urn, metadata_json, slug|
          witnesses[urn] = build_witness(urn, slug, JSON.parse(metadata_json || "{}"), texts[id], axes[id])
        end
      end
    end

    def build_witness(urn, slug, metadata, text, axes)
      letters, supplied = text || [0, 0]
      bounds = axes || []
      place = metadata["place"].is_a?(Hash) ? metadata["place"] : {}
      pleiades = !place["pleiades"].to_s.empty? ||
                 bounds.any? { |row| !PlaceRefs.ids_in(row[:place_ref], "pleiades").empty? }
      Witness.new(urn: urn, slug: slug, letters: letters, supplied: supplied,
                  not_before: bounds.filter_map { |row| row[:not_before] }.min,
                  not_after: bounds.filter_map { |row| row[:not_after] }.max,
                  pleiades: pleiades,
                  findspot: [place["ancient"], metadata["findspot"]].compact.map(&:to_s)
                                                                    .reject(&:empty?).uniq.join(", "))
    end

    # document id → [letters, supplied chars] over its live passages.
    def text_stats(ids)
      @catalog[:passages].where(document_id: ids, withdrawn: false)
                         .select_map(%i[document_id text annotations_json])
                         .each_with_object(Hash.new { |hash, key| hash[key] = [0, 0] }) do |(id, text, ann), stats|
        stats[id][0] += text.to_s.scan(/[\p{L}\p{N}]/).size
        stats[id][1] += supplied_chars(ann)
      end
    end

    def supplied_chars(annotations_json)
      return 0 if annotations_json.nil? || annotations_json.empty?

      JSON.parse(annotations_json).dig("leiden", "supplied_chars").to_i
    end

    # document id → its axis rows (bounds + place_ref).
    def axes_by_document(ids)
      @catalog[:document_axes].where(document_id: ids)
                              .select(:document_id, :not_before, :not_after, :place_ref)
                              .all.group_by { |row| row[:document_id] }
    end

    def write(pairs, witnesses, shared)
      counts = Hash.new(0)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: SCOPE)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: SCOPE,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        pairs.each do |tm, edh_urn, edr_urn|
          preference = self.class.preference(witnesses.fetch(edh_urn), witnesses.fetch(edr_urn))
          outcome = Store::LinksJournal.write_edge!(@journal, from_urn: edh_urn, to_urn: edr_urn, kind: KIND,
                                                              score: nil, run_id: run_id,
                                                              detail: "Trismegistos #{tm} · #{preference}")
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end
      Result.new(scope: SCOPE, run_id: run_id, edges_written: counts[:inserted],
                 edges_refreshed: counts[:refreshed], superseded_runs: superseded[0],
                 superseded_edges: superseded[1], shared_tm_ids: shared, pairs: pairs.size)
    end
  end
end
