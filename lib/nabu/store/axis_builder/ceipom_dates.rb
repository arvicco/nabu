# frozen_string_literal: true

require "csv"

require_relative "../../adapters/ceipom"
require_relative "../../normalize"

module Nabu
  module Store
    module AxisBuilder
      # CEIPoM text dates and findspots (P29-1): the corpus dates 3,872 of
      # its 3,875 texts with SIGNED-YEAR float strings ("-675.0", both
      # bounds always present together — censused 2026-07-18) and places
      # every text with a Provenance findspot name (10 degenerate values:
      # "?", "0", "Provenance unknown [found & written]" — not places) plus
      # WGS84 coordinates on 3,815 (the coordinates stay document metadata,
      # the EDH decision — the axis has no coordinate columns). GeoID
      # (1,036 texts, a bare float-formatted number of undocumented id
      # space) rides verbatim as place_ref, never resolved.
      #
      # Honest residues: +undated+ counts held texts without a date (3
      # upstream), +unplaced+ held texts whose Provenance is degenerate
      # (10 upstream — the axis-honest notion; the 60 coordinate-less texts
      # are a metadata fact, docs/02-sources.md), +invalid+ the year-0/
      # inverted-range tripwire (1 upstream: text 819's -100 → -51300
      # typo) — skipped, counted, never stored.
      #
      # The urn mint mirrors Adapters::Ceipom#discover (FROZEN):
      # urn:nabu:ceipom:<Text_ID>; the test pins the two against each other
      # via the shared fixture set.
      module CeipomDates
        SLUG = "ceipom"
        URN_PREFIX = "urn:nabu:ceipom:"
        TEXTS_CSV = File.join(SLUG, "texts", "texts.csv")

        # Provenance values that are honestly not places (censused exact
        # set).
        DEGENERATE_PROVENANCE = ["?", "0", "Provenance unknown [found & written]"].freeze

        module_function

        # Walk canonical/ceipom's texts.csv and insert one row per
        # dated-or-placed text we hold. Returns
        # { documents:, undated:, unplaced:, invalid: }.
        def build(catalog:, canonical_dir:)
          path = File.join(canonical_dir, TEXTS_CSV)
          counts = { documents: 0, undated: 0, unplaced: 0, invalid: 0 }
          return counts unless File.file?(path)

          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          each_text(path) do |urn, row|
            document_id = ids[urn] or next

            insert_row(catalog, document_id, row, counts)
          end
          counts
        end

        # Yields [document urn, text row] per texts.csv row (the boundary
        # decode shared with the adapter: BOM|UTF-16LE).
        def each_text(path)
          CSV.foreach(path, headers: true, encoding: "BOM|UTF-16LE:UTF-8") do |row|
            yield "#{URN_PREFIX}#{row['Text_ID']}", row
          end
        end

        # Every urn the extractor would mint from +workdir+'s texts.csv —
        # the drift-pin hook the axis test compares against the adapter's
        # discover.
        def text_urns(workdir)
          urns = []
          each_text(File.join(workdir, "texts", "texts.csv")) { |urn, _row| urns << urn }
          urns
        end

        def insert_row(catalog, document_id, row, counts)
          axis = extract(row)
          if axis == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if axis.nil? || axis[:not_before].nil?
          counts[:unplaced] += 1 if axis.nil? || axis[:place_name].nil?
          return if axis.nil?

          AxisBuilder.insert_axis(catalog, document_id, axis, SLUG)
          counts[:documents] += 1
        end

        # One text's axis fields; nil when it carries neither date nor
        # place, :invalid on the year-0/inverted tripwire.
        def extract(row)
          bounds = year_bounds(row)
          return :invalid if bounds == :invalid

          place_name, place_ref = extract_place(row)
          return nil if bounds.nil? && place_name.nil?

          {
            not_before: bounds&.first, not_after: bounds&.last,
            precision: bounds && (bounds.first == bounds.last ? "year" : "range"),
            date_raw: bounds && date_raw(row),
            place_name: place_name, place_ref: place_ref
          }
        end

        # Both bounds parse together (censused: never one-sided). A year 0
        # or an inverted range is :invalid — skipped, counted, never
        # stored.
        def year_bounds(row)
          not_before = signed_year(row["Date_after"])
          not_after = signed_year(row["Date_before"])
          return nil if not_before.nil? && not_after.nil?
          return :invalid if not_before.nil? || not_after.nil? || not_before.zero? ||
                             not_after.zero? || not_before > not_after

          [not_before, not_after]
        end

        # "-675.0" → -675. Base-10 on the float string's integer part; nil
        # for blank, nil for anything unparseable (never guessed).
        def signed_year(raw)
          m = raw.to_s.strip.match(/\A(-?)(\d+)(?:\.\d+)?\z/) or return nil

          year = m[2].to_i
          m[1].empty? ? year : -year
        end

        def date_raw(row)
          after = row["Date_after"].to_s.strip
          before = row["Date_before"].to_s.strip
          after == before ? after : "#{after} – #{before}"
        end

        def extract_place(row)
          name = row["Provenance"].to_s.strip
          return [nil, nil] if name.empty? || DEGENERATE_PROVENANCE.include?(name)

          ref = row["GeoID"].to_s.strip
          [Nabu::Normalize.nfc(name), ref.empty? ? nil : ref]
        end
      end
    end
  end
end
