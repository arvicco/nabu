# frozen_string_literal: true

module Nabu
  # The post-sync staging census (P99-5 — the P59-4 front-door bullet):
  # for ONE source, how many live documents of STAGEABLE languages
  # (registry anchors carrying minted stages) still resolve to bare
  # identity — no lect facet row, the LectFacets "no row means identity"
  # invariant. The sync report prints it as one line, so lect-staging
  # progress is visible at exactly the moment new documents arrive.
  #
  # Honesty gates (the Q71 lesson — silence over noise): languages with
  # no minted stages never count (0-unstaged there is the healthy steady
  # state, not a gap); a source holding nothing stageable returns nil,
  # never a zero line; nil registry = lane off.
  module LectStaging
    Census = Data.define(:unstaged, :stageable, :codes)

    module_function

    def census(catalog:, lects:, slug:)
      return nil if lects.nil?

      anchors = lects.ladders.reject { |ladder| ladder.stages.empty? }.map(&:anchor)
      return nil if anchors.empty?

      source_id = catalog[:sources].where(slug: slug).get(:id)
      return nil if source_id.nil?

      docs = catalog[:documents].where(source_id: source_id, withdrawn: false)
      codes = docs.where(language: anchors).distinct.select_map(:language).sort
      return nil if codes.empty?

      scope = docs.where(language: codes)
      stageable = scope.count
      staged = scope.where(staged_exists(catalog)).count
      Census.new(unstaged: stageable - staged, stageable: stageable, codes: codes)
    end

    # A document counts as staged when ANY lect facet row exists for it —
    # a stage, a register, or a journal ruling all mean "someone resolved
    # this beyond the bare code".
    def staged_exists(catalog)
      facets = Sequel[:document_facets]
      catalog[:document_facets]
        .where(facets[:document_id] => Sequel[:documents][:id], facets[:facet] => "lect")
        .exists
    end
  end
end
