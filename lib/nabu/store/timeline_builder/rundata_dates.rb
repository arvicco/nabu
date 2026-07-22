# frozen_string_literal: true

require_relative "../../adapters/rundata"
require_relative "../../adapters/rundata_sqlite_parser"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # Rundata inscription dates and find-spots (P40-6): SRDB carries a
      # parsed year envelope per inscription (meta_information.year_from/
      # year_to, integer CE bounds, either nullable) beside the verbatim
      # scholarly dating string ("V", "V Jelling", "U 650-700 (Grønvik)")
      # — no period mapping is needed or invented. Place is the verbatim
      # found_location (Plats), falling back to the parish — the EDH
      # verbatim-place stance, no gazetteer.
      #
      # The urn mint rides Adapters::Rundata.urn_for (FROZEN — the
      # Django-slugify agreement the adapter test pins against upstream's
      # own canonical_slug), so extractor and adapter can never drift.
      # Only the bare inscription urn joins; lane siblings (-fvn/-rsv/
      # -eng/-swe) carry no timeline row of their own. Inscriptions with
      # neither a year bound nor a place are counted undated, never
      # guessed.
      module RundataDates
        SLUG = "rundata"

        module_function

        # Walk the current canonical artifact and insert one row per
        # dated-or-placed inscription we hold. Returns
        # { documents:, undated: }.
        def build(catalog:, canonical_dir:)
          workdir = File.join(canonical_dir, SLUG)
          artifact = Adapters::Rundata.current_artifact(workdir)
          return { documents: 0, undated: 0 } if artifact.nil?

          prefix = "#{Adapters::Rundata::URN_PREFIX}%"
          ids = catalog[:documents].where(Sequel.like(:urn, prefix)).select_hash(:urn, :id)
          rows = 0
          undated = 0
          parser = Adapters::RundataSqliteParser.new(artifact)
          parser.each_inscription do |inscription|
            document_id = ids[Adapters::Rundata.urn_for(inscription.signum)] or next
            timeline = extract(parser.record(inscription.signature_id).meta)
            if timeline.nil?
              undated += 1
              next
            end

            insert(catalog, document_id, timeline)
            rows += 1
          end
          { documents: rows, undated: undated }
        end

        # The timeline fields, or nil when the inscription has neither a
        # year bound nor a place (the honest undated case). Either bound
        # may be NULL alone (open-ended); equal bounds are exact.
        def extract(meta)
          not_before = meta["year_from"]
          not_after = meta["year_to"]
          place = place_of(meta)
          return nil if not_before.nil? && not_after.nil? && place.nil?

          dated = !(not_before.nil? && not_after.nil?)
          {
            not_before: not_before, not_after: not_after,
            precision: dated ? precision_of(not_before, not_after) : nil,
            date_raw: dated ? presence(meta["dating"]) : nil,
            place_name: place
          }
        end

        def precision_of(not_before, not_after)
          not_before == not_after ? "exact" : "range"
        end

        def place_of(meta)
          presence(meta["found_location"]) || presence(meta["parish"])
        end

        def presence(value)
          folded = Nabu::Normalize.nfc(value.to_s.strip)
          folded.empty? ? nil : folded
        end

        def insert(catalog, document_id, timeline)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: timeline[:not_before], not_after: timeline[:not_after],
            precision: timeline[:precision], date_raw: timeline[:date_raw],
            place_name: timeline[:place_name], axis_source: SLUG
          )
        end
      end
    end
  end
end
