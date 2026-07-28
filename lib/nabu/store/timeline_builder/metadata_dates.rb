# frozen_string_literal: true

require "json"

module Nabu
  module Store
    module TimelineBuilder
      # Catalog-metadata dates (P47-r2, generalized P47-r3 — the owner's
      # "let's find out what else could've been impacted" audit). Sources
      # whose parsers persist dating in documents.metadata_json get their
      # timeline rows projected FROM THE CATALOG (the shape is already
      # derived and load-verified there; no canonical walk) — one
      # document-grain row per dated document, place_name riding when an
      # ancient place is named, place-only rows for undated-but-placed
      # records (the HGV precedent). Translation siblings never row.
      #
      # Shapes, per the 2026-07-27 audit of every date-bearing source
      # without timeline rows:
      #   :structured — "date" => {"not_before"/"not_after"/"raw"} signed
      #     years (EDR P46-4, Elephantine P47-1, ItAnt P39 — identical).
      #   :iso_keys — top-level "date_not_before"/"date_not_after" ISO
      #     date strings (BFM P45-4: "1025-01-01" → 1025).
      #   :year_range — "date" => "1565-1650" | "1565" strings (CroALa
      #     P44): both bounds from a clean YYYY[-YYYY] parse; anything
      #     else (ca., floruit prose) is skipped honestly.
      # Audited and deliberately ABSENT: ebl (Seleucid-era day/month
      # objects — an era-conversion project, 40 docs), ogham ("date" =>
      # {"text" => "Fifth century…"} free prose, 133 docs).
      module MetadataDates
        # slug => shape (the audit roster; a new metadata-dating source
        # registers here and the health lane-drift check flags it if it
        # doesn't).
        SHAPES = {
          "edr" => :structured,
          "elephantine" => :structured,
          "itant" => :structured,
          "bfm" => :iso_keys,
          "croala" => :year_range
        }.freeze

        SLUGS = SHAPES.keys.freeze

        BATCH = 2_000

        module_function

        # Returns {slug => rows} for every registered source.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          SLUGS.to_h { |slug| [slug, build_source(catalog, slug)] }
        end

        # The per-source seam (P47-r3): drop this source's rows, re-project
        # — SyncRunner calls it post-load so the lane never lags a sync.
        def refresh_source!(catalog:, slug:)
          return 0 unless SHAPES.key?(slug)

          catalog[:document_axes].where(axis_source: slug).delete
          build_source(catalog, slug)
        end

        def build_source(catalog, slug)
          shape = SHAPES.fetch(slug)
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
              row = axis_row(doc, shape)
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
        def axis_row(doc, shape)
          meta = JSON.parse(doc[:metadata_json].to_s)
          not_before, not_after, raw = send(shape, meta)
          # "place" is a Hash ({"ancient" => …}, EDR/Elephantine) or a bare
          # string (croala — the P44-i4 shape); the string IS the name.
          place = meta["place"]
          place = place["ancient"] if place.is_a?(Hash)
          return nil if not_before.nil? && not_after.nil? && (place.nil? || place.to_s.strip.empty?)

          { document_id: doc[:id], not_before: not_before, not_after: not_after,
            date_raw: raw, place_name: place }
        rescue JSON::ParserError
          nil
        end

        def structured(meta)
          date = meta["date"]
          return [nil, nil, nil] unless date.is_a?(Hash)

          [date["not_before"], date["not_after"], date["raw"]]
        end

        def iso_keys(meta)
          not_before = iso_year(meta["date_not_before"])
          not_after = iso_year(meta["date_not_after"])
          [not_before, not_after, meta["date"]]
        end

        def iso_year(value)
          match = value.to_s.match(/\A(-?\d{1,4})-\d{2}-\d{2}\z/)
          match && Integer(match[1], 10)
        end

        def year_range(meta)
          date = meta["date"]
          return [nil, nil, nil] unless date.is_a?(String)

          case date.strip
          when /\A(\d{3,4})\s*[-–]\s*(\d{3,4})\z/
            [Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2), 10), date]
          when /\A(\d{3,4})\z/
            year = Integer(::Regexp.last_match(1), 10)
            [year, year, date]
          else
            # ca./floruit/prose datings: skipped honestly, never guessed.
            [nil, nil, nil]
          end
        end
      end
    end
  end
end
