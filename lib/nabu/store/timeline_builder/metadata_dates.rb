# frozen_string_literal: true

require "json"

module Nabu
  module Store
    module TimelineBuilder
      # Catalog-metadata dates (P47-r2, owner live incident: `search
      # --century -5 --source elephantine` found nothing — the Judean
      # garrison's own century). The EDR (P46-4) and Elephantine (P47-1)
      # parsers both mint the SAME metadata_json shape at parse —
      # "date" => {"not_before"/"not_after"/"raw"}, "place" => {"ancient"}
      # — but neither packet wired a timeline extractor, so the lane stayed
      # dark for both. This extractor reads the CATALOG (the shape is
      # already derived and load-verified there; no canonical walk), one
      # document-grain row per dated document, place_name riding when the
      # ancient place is named. A document with a place but no date still
      # gets a place-only row (the HGV precedent: --place works on undated
      # stones). Honest absences: no date AND no place → no row.
      module MetadataDates
        # The sources whose parsers mint the shared metadata date shape.
        # census: the two metadata-shape sources, 2026-07-27 (P46-4 + P47-1)
        SLUGS = %w[edr elephantine].freeze

        BATCH = 2_000

        module_function

        # Returns {"edr" => rows, "elephantine" => rows}.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          SLUGS.to_h { |slug| [slug, build_source(catalog, slug)] }
        end

        def build_source(catalog, slug)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return 0 if source_id.nil?

          inserted = 0
          buffer = []
          catalog[:documents]
            .where(source_id: source_id, withdrawn: false)
            .exclude(Sequel.like(:metadata_json, '%"kind":"translation"%'))
            .select(:id, :metadata_json)
            .order(:id)
            .paged_each do |doc|
              row = axis_row(doc)
              next if row.nil?

              buffer << row.merge(axis_source: slug)
              if buffer.size >= BATCH
                catalog[:document_axes].multi_insert(buffer)
                inserted += buffer.size
                buffer = []
              end
            end
          catalog[:document_axes].multi_insert(buffer) unless buffer.empty?
          inserted + buffer.size
        end

        # One document's axis row, or nil when it carries neither a date
        # bound nor an ancient place name.
        def axis_row(doc)
          meta = JSON.parse(doc[:metadata_json].to_s)
          date = meta["date"] || {}
          not_before = date["not_before"]
          not_after = date["not_after"]
          place = meta.dig("place", "ancient")
          return nil if not_before.nil? && not_after.nil? && (place.nil? || place.to_s.strip.empty?)

          { document_id: doc[:id], not_before: not_before, not_after: not_after,
            date_raw: date["raw"], place_name: place }
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
