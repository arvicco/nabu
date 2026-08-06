# frozen_string_literal: true

require "json"
require_relative "script_check"

module Nabu
  # `nabu lect suggest <source>` (P59-4): the front-door census — inspect
  # one source's held metadata against the lect registry and report what
  # COULD refine it, so a new source's lect posture is decided at arrival
  # instead of waiting for a later sweep. REPORT-ONLY by design: adapters
  # never write the journal; the owner (or a ruled rule) applies. The
  # machine half of what the P58 census probes did by hand.
  #
  # Three grains, mirroring the assignment machinery:
  # - codes: each held language code, its doc count, its CURRENT resolution
  #   (overlay-free — the source-grain truth), and whether the anchor
  #   carries stages at all (no stages = nothing to refine into).
  # - facets: the source's facet vocabulary (name, distinct values, top
  #   values with counts) — small-vocabulary facets over staged anchors are
  #   rule candidates; the render sketches a stanza for the best one.
  # - dating: LectDates.census scoped to the source — how many documents
  #   date-band inference could stage today.
  class LectSuggest
    CodeRow = Data.define(:code, :docs, :resolution, :stages)
    FacetRow = Data.define(:facet, :distinct, :docs, :top)
    # P61-2, the layer sections: dating (bounds coverage + the pending
    # sniff — date-shaped metadata keys on UNDATED docs), places (the
    # ref/name split + the latent-ref sniff — gazetteer URLs in raw
    # metadata on unlinked docs), script (suffixed-code census with the
    # ScriptCheck byte verdict on the held surface).
    DatingLayer = Data.define(:dated, :total, :candidates)
    PlacesLayer = Data.define(:linked, :named, :total, :latent)
    ScriptRow = Data.define(:code, :docs, :surface, :share)
    Report = Data.define(:slug, :codes, :facets, :dating,
                         :dating_layer, :places_layer, :script_layer)

    # Facet-vocabulary render caps (announced, never silent).
    TOP_VALUES = 12
    # A facet with more distinct values than this is dating-or-id-shaped,
    # not a rule candidate (rules map an enumerable label vocabulary).
    RULE_CANDIDATE_DISTINCT = 40
    # The metadata sniffs read raw JSON per doc — capped, announced in
    # the render, so a 100k-doc source reports in seconds not minutes.
    SNIFF_SAMPLE = 2_000
    # Passages byte-checked per suffixed code.
    SURFACE_SAMPLE = 20
    DATE_KEY = /date|period|year|century|dynast|reign|era\b/i
    GAZETTEER_URL = %r{pleiades\.stoa\.org|geonames\.org|trismegistos\.org/place}

    def initialize(catalog:, registry:)
      @catalog = catalog
      @registry = registry
    end

    # nil when the source is unknown or holds no documents.
    def run(slug)
      source_id = @catalog[:sources].where(slug: slug).get(:id)
      return nil if source_id.nil?

      docs = live_docs(source_id)
      return nil if docs.none?

      Report.new(slug: slug, codes: code_rows(source_id, slug),
                 facets: facet_rows(source_id), dating: dating_census(slug),
                 dating_layer: dating_layer(source_id), places_layer: places_layer(source_id),
                 script_layer: script_layer(source_id))
    end

    private

    def live_docs(source_id)
      @catalog[:documents].where(source_id: source_id, withdrawn: false)
    end

    def code_rows(source_id, slug)
      live_docs(source_id)
        .group_and_count(:language)
        .sort_by { |row| -row[:count] }
        .map do |row|
          code = row[:language].to_s
          resolution = @registry.resolve(code, source: slug)
          anchor = Nabu::Lects.parse_id(resolution)&.[](:anchor)
          stages = anchor ? @registry.stages_of(anchor).map(&:stage) : []
          CodeRow.new(code: code, docs: row[:count], resolution: resolution, stages: stages)
        end
    end

    def facet_rows(source_id)
      doc_ids = live_docs(source_id).select(:id)
      counted = @catalog[:document_facets]
                .where(document_id: doc_ids)
                .exclude(facet: "lect")
                .group_and_count(:facet, :value)
                .all
      rows = counted.group_by { |row| row[:facet] }.map do |facet, values|
        FacetRow.new(facet: facet, distinct: values.size,
                     docs: values.sum { |r| r[:count] },
                     top: values.sort_by { |r| -r[:count] }
                                .first(TOP_VALUES).map { |r| [r[:value], r[:count]] })
      end
      rows.sort_by { |row| -row.docs }
    end

    def dating_census(slug)
      Nabu::LectDates.new(registry: @registry).census(catalog: @catalog, source: slug)
    rescue Nabu::Error, Sequel::DatabaseError => e
      # The dating lane is optional context — a catalog without axes (or a
      # pre-P58 shape) reports the absence rather than sinking the census.
      e.message
    end

    # Docs carrying at least one bound, and the pending sniff: date-shaped
    # metadata keys on the docs the axes lane does NOT cover — "upstream
    # carries dates no extractor reads" made visible per source.
    def dating_layer(source_id)
      dated_ids = bounded_doc_ids(source_id)
      candidates = Hash.new(0)
      sniff_metadata(live_docs(source_id).exclude(id: dated_ids)) do |metadata|
        metadata.each_key { |key| candidates[key] += 1 if key.match?(DATE_KEY) }
      end
      DatingLayer.new(dated: live_docs(source_id).where(id: dated_ids).count,
                      total: live_docs(source_id).count,
                      candidates: candidates.sort_by { |_, count| -count })
    end

    def places_layer(source_id)
      doc_ids = live_docs(source_id).select(:id)
      axes = @catalog[:document_axes].where(document_id: doc_ids)
      linked_ids = axes.exclude(place_ref: nil).select(:document_id)
      latent = 0
      sniff_metadata(live_docs(source_id).exclude(id: linked_ids)) do |metadata|
        latent += 1 if metadata.to_s.match?(GAZETTEER_URL)
      end
      PlacesLayer.new(linked: axes.exclude(place_ref: nil).select(:document_id).distinct.count,
                      named: axes.exclude(place_name: nil).select(:document_id).distinct.count,
                      total: live_docs(source_id).count, latent: latent)
    end

    # One row per script-suffixed language code (the BCP-47 shape the
    # P60-1 census walked), with the ScriptCheck byte verdict on a sample
    # of the held passages — what the surface ACTUALLY is, not what the
    # suffix claims.
    def script_layer(source_id)
      live_docs(source_id)
        .group_and_count(:language)
        .map { |row| [row[:language].to_s, row[:count]] }
        .select { |code, _| code.match?(/-\p{Upper}/) }
        .sort_by { |_, docs| -docs }
        .map do |code, docs|
          texts = @catalog[:passages]
                  .where(document_id: live_docs(source_id).where(language: code).select(:id))
                  .limit(SURFACE_SAMPLE).select_map(:text)
          surface, share = Nabu::ScriptCheck.dominant(texts)
          ScriptRow.new(code: code, docs: docs, surface: surface, share: share)
        end
    end

    def bounded_doc_ids(source_id)
      @catalog[:document_axes]
        .where(document_id: live_docs(source_id).select(:id))
        .where(Sequel.~(not_before: nil) | Sequel.~(not_after: nil))
        .select(:document_id)
    end

    # Yields parsed metadata_json for up to SNIFF_SAMPLE docs of +dataset+
    # that carry a non-trivial payload; unparseable JSON is skipped (the
    # sniff is advisory, never load-bearing).
    def sniff_metadata(dataset)
      # Two excludes, deliberately: a NOT IN list containing NULL is NULL
      # for every row (the SQL three-valued trap) — it would sniff nothing.
      dataset.exclude(metadata_json: nil).exclude(metadata_json: "{}").limit(SNIFF_SAMPLE)
             .select_map(:metadata_json).each do |raw|
        metadata = JSON.parse(raw)
        yield metadata if metadata.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
    end
  end
end
