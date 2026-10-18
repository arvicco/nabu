# frozen_string_literal: true

require "json"
require_relative "store/links_journal"
require_relative "version"

module Nabu
  # The OpenITI works-graph producer for the links journal: the book
  # sidecars' RELATED assertions (40#BOOK#RELATED — "<book URI>
  # (<relation>)", relation codes from upstream's book_relations scheme:
  # COMM commentary, PART part-of, ABR abridgement, CONT continuation,
  # TRANSL translation …) as kind=reference edges, so `nabu links` on a
  # commentary shows the work it comments on and vice versa.
  #
  # == The join (the KitabReuse catalog-join mold)
  #
  # A relation is a WORK-grain claim; the library holds VERSIONS. The
  # parser carries each version's book-sidecar relations verbatim in
  # metadata "related_works"; this producer builds {book URI → held
  # version urns} from the catalog once and mints one edge per (asserting
  # held version, target held version) pair. A target book with no held
  # version is skipped and censused (+skipped_unheld+) — never an edge to
  # an invented work urn: OpenITI's work URIs are not catalog documents
  # (the LibraryReferences "never-had-a-row" stance).
  #
  # == Edge shape
  #
  # from_urn = the asserting version, to_urn = the target version, score
  # nil (a cataloguer's assertion, not a mined similarity), detail = the
  # relation code + the book-to-book claim verbatim. A pure function of
  # (canonical, code) re-derived after every openiti load, superseding
  # the prior (producer, scope) run.
  class OpenitiRelations
    PRODUCER = "openiti-relations"
    KIND = "reference"
    CODE_VERSION = "openiti-relations/1 nabu/#{VERSION}".freeze
    URN_PREFIX = "urn:nabu:openiti:"

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unheld)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # +workdir+ rides the producer seam signature; every input is catalog
    # metadata, so it is unused.
    def run(slug, workdir: nil) # rubocop:disable Lint/UnusedMethodArgument
      documents = held_documents(slug)
      by_book = documents.group_by { |urn, _| book_uri(urn) }.transform_values { |rows| rows.map(&:first) }
      counts = Hash.new(0)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        documents.each { |urn, metadata| write_edges(urn, metadata, by_book, run_id, counts) }
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unheld: counts[:unheld])
    end

    # "urn:nabu:openiti:<author>.<book>.<edition>-<lang>" → "<author>.<book>".
    def self.book_uri(urn)
      urn.delete_prefix(URN_PREFIX).split(".").first(2).join(".")
    end

    private

    def book_uri(urn) = self.class.book_uri(urn)

    def write_edges(urn, metadata, by_book, run_id, counts)
      Array(metadata["related_works"]).each do |relation|
        targets = by_book.fetch(relation["work"], [])
        if targets.empty?
          counts[:unheld] += 1
          next
        end
        detail = "OpenITI book relation #{relation['relation'] || '(untyped)'}: " \
                 "#{book_uri(urn)} → #{relation['work']}"
        targets.each do |target|
          outcome = Store::LinksJournal.write_edge!(@journal, from_urn: urn, to_urn: target, kind: KIND,
                                                              score: nil, run_id: run_id, detail: detail)
          counts[outcome == :inserted ? :inserted : :refreshed] += 1
        end
      end
    end

    # [[urn, metadata], …] for the source's non-withdrawn documents,
    # urn-ordered for determinism.
    def held_documents(slug)
      @catalog[:documents]
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
        .order(Sequel[:documents][:urn])
        .select_map([Sequel[:documents][:urn], Sequel[:documents][:metadata_json]])
        .map { |urn, json| [urn, json ? JSON.parse(json) : {}] }
    end
  end
end
