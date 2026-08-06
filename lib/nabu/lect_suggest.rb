# frozen_string_literal: true

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
    Report = Data.define(:slug, :codes, :facets, :dating)

    # Facet-vocabulary render caps (announced, never silent).
    TOP_VALUES = 12
    # A facet with more distinct values than this is dating-or-id-shaped,
    # not a rule candidate (rules map an enumerable label vocabulary).
    RULE_CANDIDATE_DISTINCT = 40

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
                 facets: facet_rows(source_id), dating: dating_census(slug))
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
  end
end
