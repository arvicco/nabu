# frozen_string_literal: true

require "json"

require_relative "store/links_journal_bulk"

module Nabu
  # EDH's bibliography and calendar-date identities as kind=reference edges
  # (a slug-scoped reference producer, architecture §15). Every EDH record
  # carries the corpus citations of its inscription (edh_data_text.csv
  # `literatur`, " # "-separated, riding each document's metadata as
  # "literature") and, for 1,579 records, the GODOT calendar-date record
  # (`godot_uris`, the Graph of Dated Objects and Texts — metadata
  # "godot_uris"). Both name stable external id spaces, so both become
  # edges from the EDH document urn — the LibraryReferences concordance
  # precedent: the target renders "(not in catalog)" honestly until the
  # library holds that side, and `nabu links <edh urn>` lists them.
  #
  # == The two corpora (the citation edges)
  #
  # Only the two standard corpora that key the field are edged — L'Année
  # épigraphique and the Corpus Inscriptionum Latinarum — in compact ids
  # built from EDH's own zero-padded numbering (no renumbering, no
  # roman-numeral guess):
  #
  #   "AE 1983, 0192."            → ae:1983,0192
  #   "AE 1917/18, 0064. (B)"     → ae:1917/18,0064
  #   "AE 1975, 0141a."           → ae:1975,0141a      (item letter / "bis" kept)
  #   "CIL 06, 41026; Foto."      → cil:06,41026
  #   "CIL 13, 04, 06548 add. …"  → cil:13,04,06548    (volume, part, item)
  #   "CIL 02 (2. Aufl.) 05, 00274." → cil:02(2),05,00274 (the second edition)
  #   "CIL 03, 04496 a. (B)"      → cil:03,04496a
  #   "CIL 10, 01243*."           → cil:10,01243*      (the falsae star kept)
  #
  # A citation to a PAGE rather than an item ("AE 1948, p. 44 s. n. 112.",
  # "CIL 02, p. 1054.") names no inscription number and mints nothing — it is
  # counted (+skipped_cites+), never guessed. Trailing sub-numbers of the
  # instrumentum volumes ("CIL 03, 14188, 1") stay in the edge detail, which
  # carries the citation verbatim; the id is the item.
  #
  # Census (canonical/edh/text/edh_data_text.csv, the frozen 2021 dump,
  # 2026-10-22): 82,450 rows, 81,937 with literature (192,806 citations);
  # 50,411 AE and 35,061 CIL citations on 65,344 rows (65,321 of them held
  # documents — the rest are the text-less stubs discover skips).
  #
  # == GODOT
  #
  # The `godot_uris` value is the GODOT record's URI verbatim
  # (https://godot.date/id/…) — the place_ref doctrine, upstream bytes kept.
  # GODOT identifies the CALENDAR date (a consular year, a dated day) the
  # inscription carries; the year/day bounds themselves ride the timeline
  # (Store::TimelineBuilder::EdhDates), the GODOT identity rides here.
  #
  # == Refresh mechanics
  #
  # A pure function of the loaded EDH documents' metadata: run after every
  # edh sync (Adapters::Edh.reference_producer, composed beside the EDH↔EDR
  # same-artifact producer by Nabu::EdhReferences) and by rebuild's links
  # stage; supersedes its one (producer, scope) run atomically.
  class EdhCitations
    PRODUCER = "edh-citations"
    SCOPE = "edh"
    KIND = "reference"
    SLUG = "edh"
    CODE_VERSION = "edh-citations/1 nabu/#{VERSION}".freeze

    AE = %r{\AAE (?<year>\d{4}(?:/\d{2})?), (?<item>\d{4})(?<suffix>bis|[a-z]{1,2})?\b}
    CIL = Regexp.new('\ACIL (?<volume>\d{2})(?<second> \(2\. Aufl\.\))?,? (?:(?<part>\d{2}), )?' \
                     '(?<item>\d{5})(?:(?<suffix>[a-z]{1,2})\b|\s(?<spaced>[a-z])(?![a-z]))?(?<star>\*)?')
    GODOT = %r{\Ahttps?://godot\.date/id/\S+\z}

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :citations, :skipped_cites, :godot)

    # The compact corpus id of one verbatim citation, or nil (a page
    # citation, or neither corpus).
    def self.citation_id(cite)
      text = cite.to_s.strip
      if (m = AE.match(text))
        "ae:#{m[:year]},#{m[:item]}#{m[:suffix]}"
      elsif (m = CIL.match(text))
        volume = m[:second] ? "#{m[:volume]}(2)" : m[:volume]
        [["cil:#{volume}", m[:part]].compact.join(","), "#{m[:item]}#{m[:suffix] || m[:spaced]}#{m[:star]}"]
          .join(",")
      end
    end

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every edge, superseding the one prior run. The slug and
    # workdir ride the producer seam; the edges derive from catalog rows.
    def run(_slug = SLUG, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      edges, census = collect
      counts = run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: SCOPE)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: SCOPE,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        counts = Store::LinksJournal.write_edges!(@journal, edges, kind: KIND, run_id: run_id)
      end
      Result.new(scope: SCOPE, run_id: run_id, edges_written: counts[:inserted],
                 edges_refreshed: counts[:refreshed], superseded_runs: superseded[0],
                 superseded_edges: superseded[1], **census)
    end

    private

    # [[from, to, score, detail] …, census] over the live EDH documents,
    # urn-ordered for determinism.
    def collect
      census = { citations: 0, skipped_cites: 0, godot: 0 }
      edges = documents.flat_map do |urn, metadata|
        citation_edges(urn, metadata, census) + godot_edges(urn, metadata, census)
      end
      [edges, census]
    end

    def citation_edges(urn, metadata, census)
      Array(metadata["literature"]).filter_map do |cite|
        next unless cite.start_with?("AE ", "CIL ")

        id = self.class.citation_id(cite)
        unless id
          census[:skipped_cites] += 1
          next
        end
        census[:citations] += 1
        [urn, id, nil, "EDH bibliography: #{cite}"]
      end
    end

    def godot_edges(urn, metadata, census)
      metadata["godot_uris"].to_s.split.grep(GODOT).map do |uri|
        census[:godot] += 1
        [urn, uri, nil, "EDH dating: GODOT calendar-date record"]
      end
    end

    def documents
      @catalog[:documents].join(:sources, id: :source_id)
                          .where(Sequel[:sources][:slug] => SLUG, Sequel[:documents][:withdrawn] => false)
                          .order(Sequel[:documents][:urn])
                          .select_map([Sequel[:documents][:urn], Sequel[:documents][:metadata_json]])
                          .map { |urn, json| [urn, json ? JSON.parse(json) : {}] }
    end
  end

  # The EDH adapter's reference producer: the EDH↔EDR same-artifact
  # concordance (shared with edr) and the EDH citation/GODOT edges, run in
  # that order on one journal handle. The sync tail and rebuild read one
  # LibraryReferences::Result-shaped value, so the counts sum; +parts+ keeps
  # each producer's own result.
  class EdhReferences
    Result = Data.define(:parts) do
      def edges_written = parts.sum(&:edges_written)
      def edges_refreshed = parts.sum(&:edges_refreshed)
      def superseded_runs = parts.sum(&:superseded_runs)
      def superseded_edges = parts.sum(&:superseded_edges)
    end

    def initialize(catalog:, journal:)
      @producers = [EdhEdrSameArtifact.new(catalog: catalog, journal: journal),
                    EdhCitations.new(catalog: catalog, journal: journal)]
    end

    def run(slug = EdhCitations::SLUG, workdir: nil)
      Result.new(parts: @producers.map { |producer| producer.run(slug, workdir: workdir) })
    end
  end
end
