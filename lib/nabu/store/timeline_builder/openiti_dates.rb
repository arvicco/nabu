# frozen_string_literal: true

require_relative "../../adapters/openiti"

module Nabu
  module Store
    module TimelineBuilder
      # OpenITI author death years (P41-2): every in-scope OpenITI urn opens
      # with the author's 4-digit hijrī death year (upstream's own URI
      # grammar; the TSV `date` column equals the prefix with 0 mismatches
      # across 14,107 rows — P41-g groundwork), so the extractor reads urns
      # alone — urn = f(canonical), the goo300k/imp shape, no canonical
      # re-parse and no join to drift.
      #
      # AH → CE by the standard tabular conversion
      #
      #   CE = round(AH × 0.970225 + 621.5716)
      #
      # (0.970225 ≈ 354.36707/365.25 — the mean lunar year in Julian years;
      # 621.5716 anchors 1 Muharram AH 1 = 622-07-16 CE). The envelope is a
      # POINT year that is a TERMINUS, not a composition date: the author
      # died that year, so the work was composed on-or-before it — precision
      # "year", date_raw "d. AH NNNN" naming the source honestly. Urns
      # without the prefix (the MS* documentary shapes — out of scope by
      # D41-e, guarded here anyway) are counted undated, never guessed.
      # No place lane: the corpus carries no findspots.
      module OpenitiDates
        SLUG = "openiti"

        AH_TO_CE_FACTOR = 0.970225
        AH_TO_CE_OFFSET = 621.5716

        DEATH_AH = /\A(\d{4})/

        module_function

        # One row per held OpenITI document whose urn carries the AH prefix.
        # Returns { documents:, undated: }. +canonical_dir+ is unused (urn =
        # f(canonical)) but kept for the uniform lane signature.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          rows = 0
          undated = 0
          prefix = Adapters::Openiti::URN_PREFIX
          catalog[:documents].where(Sequel.like(:urn, "#{prefix}%"))
                             .select_map(%i[id urn]).each do |id, urn|
            ah = urn.delete_prefix(prefix)[DEATH_AH, 1]
            if ah.nil?
              undated += 1
              next
            end

            insert(catalog, id, ah)
            rows += 1
          end
          { documents: rows, undated: undated }
        end

        def ce_year(death_ah)
          ((death_ah * AH_TO_CE_FACTOR) + AH_TO_CE_OFFSET).round
        end

        def insert(catalog, document_id, death_ah)
          year = ce_year(death_ah.to_i)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: year, not_after: year,
            precision: "year", date_raw: "d. AH #{death_ah}",
            axis_source: SLUG
          )
        end
      end
    end
  end
end
