# frozen_string_literal: true

require_relative "certainty"
require_relative "places"

module Nabu
  # `nabu place apply` (P63-7): project the nabu-places registry's MATCHED
  # decisions into document_axes.place_ref. The precedence ladder is
  # structural: only rows whose place_ref is NULL are touched — an
  # adapter-asserted upstream ref ALWAYS wins over a registry mint, and a
  # registry mint is never stacked onto another mint (idempotent: a second
  # apply updates zero rows). Multi-ref decisions join space-separated (the
  # multi-URL precedent, read back by Nabu::PlaceRefs). Rebuild-safe: the
  # rebuild pipeline re-runs this after the timeline lanes, so db/ stays a
  # pure function of canonical/ (the registry lives under canonical/).
  module PlaceApply
    module_function

    # Census: {source => {rows_updated:, names_applied:}} plus :total.
    # P81 U-3 (the A1 dies-at-apply defect): a source whose APPLIED names
    # carry a below-certain registry certainty additionally reports them
    # under :uncertain ({name => {rows:, certainty:}}, the upstream word
    # verbatim) — the key merges only when non-empty (the empty-hash
    # idiom), so certainty:low no longer dies at the seam.
    # Returns nil when no registry is synced (the lane-off posture).
    def run(catalog:, canonical_dir:)
      registry = Nabu::Places.load_default(canonical_dir: canonical_dir)
      return nil if registry.nil?

      census = {}
      total = 0
      registry.sources.each do |slug|
        source_id = catalog[:sources].where(slug: slug).get(:id) or next
        matched = registry.decisions_for(slug).select { |_, d| d.matched? }
        updated = 0
        names = 0
        uncertain = {}
        catalog.transaction do
          matched.each do |name, decision|
            n = catalog[:document_axes]
                .where(place_ref: nil, place_name: name)
                .where(document_id: catalog[:documents].where(source_id: source_id).select(:id))
                .update(place_ref: decision.refs.join(" "))
            updated += n
            next unless n.positive?

            names += 1
            tier = Nabu::Certainty.tier(:places_certainty, decision.certainty)
            uncertain[name] = { rows: n, certainty: decision.certainty } if tier && tier != "certain"
          end
        end
        census[slug] = { rows_updated: updated, names_applied: names }
        census[slug][:uncertain] = uncertain unless uncertain.empty?
        total += updated
      end
      census.merge(total: total)
    end
  end
end
