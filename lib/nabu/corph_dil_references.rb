# frozen_string_literal: true

require "json"

module Nabu
  # Producer #5 for the links journal (P25-0): the eDIL bridge. CorPH's
  # LEMMATA table keys 6,232 of its 10,485 lemmas into dil.ie's stable id
  # space (DIL_Headword — "www.dil.ie/8406"); the corph adapter carries those
  # ids on every gold token ("dil"). This producer re-derives them into
  # kind=reference edges after every corph load: from each corph DOCUMENT urn
  # to urn:nabu:dict:edil:<id> — the urn an ingested eDIL dictionary shelf
  # will mint under the urn:nabu:dict:<slug>:<entry id> convention, so the
  # edges resolve the day eDIL itself unblocks (unlock email pending). Until
  # then `nabu links` shows them honestly "(not in catalog)": deliberate
  # forward edges into a STABLE external id space, not invented urns (the
  # P19-4 language-code verdict bars ids that never had a target space;
  # dil.ie ids have one).
  #
  # == Grain: one edge per distinct (document, dil id) pair
  #
  # Passage-grain edges would mint ~100k+ rows for a navigation payoff the
  # document grain already delivers (~12,300 pairs across the 78 texts,
  # censused 2026-07-17); the detail names the first-seen lemma so the edge
  # is legible. Like every producer, edges are a pure function of (canonical,
  # code): re-derived from the loaded passages' token annotations, reruns
  # supersede, rebuild never touches the journal, losing the journal costs
  # one re-run.
  class CorphDilReferences
    PRODUCER = "corph"
    KIND = "reference"
    TO_URN_PREFIX = "urn:nabu:dict:edil:"
    CODE_VERSION = "corph-dil-references/1 nabu/#{VERSION}".freeze

    # What one refresh did — the LibraryReferences::Result shape, so the CLI
    # sync summary renders both producers identically.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every DIL edge for the source at +slug+ from its live
    # passages' token annotations, superseding the prior (producer, scope)
    # run atomically. +workdir+ rides the P32-6 producer seam; this
    # producer derives everything from the catalog and ignores it.
    def run(slug, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      counts = { inserted: 0, refreshed: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(slug, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1])
    end

    private

    def write_edges(slug, run_id, counts)
      document_pairs(slug).each do |urn, pairs|
        pairs.each do |id, lemma|
          outcome = Store::LinksJournal.write_edge!(
            @journal, from_urn: urn, to_urn: "#{TO_URN_PREFIX}#{id}", kind: KIND,
                      score: nil, run_id: run_id, detail: "lemma #{lemma} (dil.ie/#{id})"
          )
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end
    end

    # { document urn => { dil id => first-seen lemma } } over the live
    # passages of the live documents of +slug+, urn-ordered and streamed —
    # one pass over annotations_json, the same JSON the gold lemma index
    # reads.
    def document_pairs(slug)
      pairs = Hash.new { |hash, key| hash[key] = {} }
      live_passages(slug).each do |document_urn, json|
        next if json.nil? || !json.include?('"dil"')

        tokens = JSON.parse(json)["tokens"]
        next unless tokens.is_a?(Array)

        tokens.each do |token|
          next unless token.is_a?(Hash) && token["dil"].is_a?(Array)

          token["dil"].each { |id| pairs[document_urn][id.to_s] ||= token["lemma"] || token["form"] || "?" }
        end
      end
      pairs
    end

    def live_passages(slug)
      @catalog[:passages]
        .join(:documents, id: Sequel[:passages][:document_id])
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug,
               Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn], Sequel[:passages][:sequence])
        .select_map([Sequel[:documents][:urn], Sequel[:passages][:annotations_json]])
    end
  end
end
