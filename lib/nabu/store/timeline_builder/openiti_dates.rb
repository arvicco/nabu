# frozen_string_literal: true

require "json"

require_relative "../../adapters/openiti"
require_relative "../../althurayya_index"

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
      #
      # == The place lane: the author's place of activity
      #
      # The corpus carries no findspots, but its authors are placed: the
      # parse-time "author_places" metadata (the TSV tags' role@URI bag
      # unioned with the author sidecar's DIED/RESIDED lists) names
      # al-Ṯurayyā gazetteer ids. The row's place_ref mints the author's
      # DEATH and RESIDENCE settlements as thurayya: claims (death place
      # first, deduped) — where the author worked, the honest place of a
      # text composed on-or-before that death. Only settlement-shaped ids
      # (AlthurayyaIndex::ID_PATTERN) mint: region ids (Iraq_RE, the
      # "_Auto" guesses) are not place-index rows, unfinished ids
      # (SAFADXXXYYY) resolve nowhere, and born/visited are biography,
      # never the work's place — all four stay document metadata. No
      # place_name: the claim is an id, the gazetteer names it.
      module OpenitiDates
        SLUG = "openiti"

        AH_TO_CE_FACTOR = 0.970225
        AH_TO_CE_OFFSET = 621.5716

        DEATH_AH = /\A(\d{4})/

        PLACING_ROLES = %w[died resided].freeze

        module_function

        # One row per held OpenITI document whose urn carries the AH prefix.
        # Returns { documents:, undated: }. +canonical_dir+ is unused (urn =
        # f(canonical); places ride the catalog metadata) but kept for the
        # uniform lane signature.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          undated = 0
          prefix = Adapters::Openiti::URN_PREFIX
          documents = catalog[:documents].where(Sequel.like(:urn, "#{prefix}%")).select_map(%i[id urn metadata_json])
          rows = TimelineBuilder.writing_axes(catalog) do |axes|
            documents.each do |id, urn, json|
              ah = urn.delete_prefix(prefix)[DEATH_AH, 1]
              if ah.nil?
                undated += 1
                next
              end

              insert(axes, id, ah, place_ref: place_ref(json))
            end
          end
          { documents: rows, undated: undated }
        end

        def ce_year(death_ah)
          ((death_ah * AH_TO_CE_FACTOR) + AH_TO_CE_OFFSET).round
        end

        # "thurayya:<id> thurayya:<id>" from the metadata's author_places
        # (died, then resided; settlements only), or nil.
        def place_ref(json)
          places = JSON.parse(json.to_s)["author_places"]
          return nil unless places.is_a?(Hash)

          ids = PLACING_ROLES.flat_map { |role| Array(places[role]) }
                             .select { |id| AlthurayyaIndex::ID_PATTERN.match?(id.to_s) }.uniq
          ids.empty? ? nil : ids.map { |id| "#{AlthurayyaIndex::GAZETTEER}:#{id}" }.join(" ")
        rescue JSON::ParserError
          nil
        end

        def insert(axes, document_id, death_ah, place_ref: nil)
          year = ce_year(death_ah.to_i)
          axes.insert(
            document_id: document_id,
            not_before: year, not_after: year,
            precision: "year", date_raw: "d. AH #{death_ah}",
            place_ref: place_ref, axis_source: SLUG
          )
        end
      end
    end
  end
end
