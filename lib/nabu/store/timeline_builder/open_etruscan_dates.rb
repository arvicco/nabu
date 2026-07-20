# frozen_string_literal: true

require_relative "../../adapters/flat_csv_parser"
require_relative "../../adapters/open_etruscan"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # OpenEtruscan dating + the Larth findspot side-join → the date/place
      # timeline (P29-0) — the RiigDates shape over the two canonical flat-csv
      # artifacts instead of per-record EpiDoc:
      #
      # - corpus/openetruscan_clean.csv `year_from`/`year_to` are
      #   BCE-POSITIVE upstream ("675.0" = 675 BCE, from ≥ to, 307 dated
      #   rows) → SIGN-FLIPPED to signed historical years (-675/-650), the
      #   fixture-pinned regression. Upstream also writes "0.0" for the
      #   turn of era (3 rows); no year 0 exists (the Timeline doctrine) —
      #   such a bound is counted invalid and mints NO date, but a row
      #   carrying a real findspot keeps its place-only row (unlike riig,
      #   whose invalid dates and places live in the same XML node — here
      #   they are independent columns).
      # - findspots/Etruscan.csv (Larth Data/Etruscan.csv @ the pinned
      #   commit) carries the 456 city-tagged rows OpenEtruscan dropped in
      #   cleaning; the side-join key is the shared inscription id
      #   (whitespace-stripped — upstream pads them), first row wins on
      #   the one duplicate-id conflict (ETP 285: Clusium / Ager
      #   Clusinus). place_name = the City string verbatim, place_ref nil
      #   (no gazetteer resolution — the §1.4 stance).
      #
      # Join: row id → Adapters::OpenEtruscan.urn_for (ONE mint rule, no
      # drift) → document_id; -en siblings never join. Returns
      # { documents:, undated:, invalid: } — riig's counting: +undated+ is
      # joined rows with a place-only row or no row, +invalid+ the year-0
      # tripwire bounds.
      module OpenEtruscanDates
        SLUG = "open-etruscan"
        CORPUS_GLOB = File.join(SLUG, Adapters::OpenEtruscan::CORPUS_DIRNAME,
                                Adapters::OpenEtruscan::CORPUS_FILENAME)
        FINDSPOTS_PATH = File.join(SLUG, Adapters::OpenEtruscan::FINDSPOTS_DIRNAME,
                                   Adapters::OpenEtruscan::FINDSPOTS_FILENAME)
        URN_PREFIX = Adapters::OpenEtruscan::URN_PREFIX

        module_function

        # Walk the corpus rows, insert one timeline row per dated/placed
        # document the catalog holds.
        def build(catalog:, canonical_dir:)
          counts = { documents: 0, undated: 0, invalid: 0 }
          corpus = Dir.glob(File.join(canonical_dir, CORPUS_GLOB)).first
          return counts if corpus.nil?

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          places = findspot_places(canonical_dir)
          Adapters::FlatCsvParser.new.each_row(corpus) do |row|
            document_id = urn_ids[Adapters::OpenEtruscan.urn_for(row.fetch("id"))] or next

            insert_row(catalog, document_id, row, places, counts)
          end
          counts
        end

        # Inscription id (stripped) → City, first row wins (the one
        # conflicting duplicate resolves deterministically). Empty when the
        # findspots artifact is absent.
        def findspot_places(canonical_dir)
          path = File.join(canonical_dir, FINDSPOTS_PATH)
          return {} unless File.file?(path)

          places = {}
          Adapters::FlatCsvParser.new.each_row(path) do |row|
            id = row["ID"].to_s.strip
            city = row["City"].to_s.strip
            next if id.empty? || city.empty?

            places[id] ||= Nabu::Normalize.nfc(city)
          end
          places
        end

        def insert_row(catalog, document_id, row, places, counts)
          bounds = signed_bounds(row, counts)
          place_name = places[row.fetch("id").to_s.strip]
          counts[:undated] += 1 if bounds.nil?
          return if bounds.nil? && place_name.nil?

          timeline = (bounds || { not_before: nil, not_after: nil, precision: nil, date_raw: nil })
                     .merge(place_name: place_name, place_ref: nil)
          TimelineBuilder.insert_timeline(catalog, document_id, timeline, SLUG)
          counts[:documents] += 1
        end

        # The sign flip (class note): BCE-positive bounds → negative signed
        # years. nil for undated rows; a 0.0 bound is counted invalid and
        # dates nothing.
        def signed_bounds(row, counts)
          from = year(row["year_from"])
          to = year(row["year_to"])
          return nil if from.nil? && to.nil?

          if [from, to].compact.any?(&:zero?)
            counts[:invalid] += 1
            return nil
          end

          {
            # Censused always paired upstream; a one-sided pair (defensive)
            # keeps its one honest bound open-ended.
            not_before: from && -from, not_after: to && -to,
            precision: from == to ? "exact" : "range",
            date_raw: from == to ? "#{from} BCE" : "#{[from, to].compact.join('–')} BCE"
          }
        end

        def year(value)
          text = value.to_s.strip
          return nil if text.empty?

          Integer(Float(text))
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
