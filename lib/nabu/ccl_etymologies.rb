# frozen_string_literal: true

module Nabu
  # Producer #6 for the links journal (P28-3): the egy↔cop diachronic
  # bridge. The ccl adapter parses ORAEC's CC0 coptic_etymologies crosswalk
  # (2,177 rows: CDO/CCL C-id ↔ TLA hieroglyphic lemma id ↔ TLA demotic
  # word id) into ancestor DictionaryCitations on the CCL entries; this
  # producer re-derives those rows into kind=etymology edges after every
  # ccl sync — from urn:nabu:dict:ccl:<C-id> to:
  #
  # - urn:nabu:dict:aed:<TLA lemma id> — the P28-1 sibling shelf's minted
  #   urn space (ids verbatim from the crosswalk, the same ids AES tokens
  #   carry). Dangling until that shelf lands is the established honest
  #   pattern (P25-0): edges mint regardless of sibling merge order.
  # - urn:nabu:dict:tla-demotic:<word id> — verbatim TLA demotic word
  #   numbers (220 of them negative). NO bulk demotic lemma list exists
  #   anywhere (egyptian-survey §10 risk 6: AED is hieroglyphic-hieratic,
  #   CDD is ©-reserved, Erichsen blocked), so these are deliberate
  #   forward edges into a STABLE external id space, the dil.ie doctrine —
  #   thesaurus-linguae-aegyptiae.de/lemma/d<id> resolves every one today
  #   (verified live incl. d-1427). If a future shelf keys the modern
  #   "d<id>" spelling instead, this prefix is the one-line change and a
  #   rerun re-mints.
  #
  # == Edge kind: etymology, not reference
  #
  # The journal's kind vocabulary is open by design (intertext-design §7:
  # "{parallel, formula, cognate, …}"). "reference" (P19-4/P25-0/P25-1)
  # asserts CITATION — a manifest's related urn, a corpus document's
  # dictionary headwords, a print-corpus concordance. A crosswalk row
  # asserts diachronic DESCENT of one lemma across ~3,000 years — a
  # different claim that must not blur into the citation render; "cognate"
  # is likewise taken (aligned witness passages meeting at a
  # reconstruction). New honest kind: etymology.
  #
  # == Grain: one edge per (entry, ancestor id) — the crosswalk's own grain
  #
  # Like every producer, edges are a pure function of (canonical, code):
  # re-derived from the loaded entries' ancestor citations (the
  # urn:nabu:dict:-prefixed DictionaryCitation rows the ccl parser mints —
  # the TEI's own print bibls never become citation rows), reruns
  # supersede, rebuild never touches the journal, losing the journal costs
  # one re-run. Expected full-corpus yield: 3,522 edges (1,695
  # hieroglyphic + 1,827 demotic; censused 2026-07-18).
  class CclEtymologies
    PRODUCER = "ccl"
    KIND = "etymology"
    ANCESTOR_URN_PREFIX = "urn:nabu:dict:"
    CODE_VERSION = "ccl-etymologies/1 nabu/#{VERSION}".freeze

    # What one refresh did — the LibraryReferences::Result shape, so the
    # CLI sync summary renders every producer identically.
    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every etymology edge for the source at +slug+ from its
    # live entries' ancestor citations, superseding the prior
    # (producer, scope) run atomically. +workdir+ rides the P32-6 producer
    # seam; this producer derives everything from the catalog and ignores it.
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
      ancestor_citations(slug).each do |row|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: row[:entry_urn], to_urn: row[:urn_raw], kind: KIND,
                    score: nil, run_id: run_id, detail: "#{row[:headword]} ← #{row[:label]}"
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end

    # The urn:nabu:dict:-targeted citation rows of the live entries of the
    # live dictionaries of +slug+, urn-ordered and streamed — the exact
    # rows the ccl parser minted from the crosswalk.
    def ancestor_citations(slug)
      @catalog[:dictionary_citations]
        .join(:dictionary_entries, id: Sequel[:dictionary_citations][:dictionary_entry_id])
        .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
        .join(:sources, id: Sequel[:dictionaries][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:dictionary_entries][:withdrawn] => false)
        .where(Sequel.like(Sequel[:dictionary_citations][:urn_raw], "#{ANCESTOR_URN_PREFIX}%"))
        .order(Sequel[:dictionary_entries][:urn], Sequel[:dictionary_citations][:seq])
        .select(Sequel[:dictionary_entries][:urn].as(:entry_urn),
                Sequel[:dictionary_entries][:headword],
                Sequel[:dictionary_citations][:urn_raw],
                Sequel[:dictionary_citations][:label])
    end
  end
end
