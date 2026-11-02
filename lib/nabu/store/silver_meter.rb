# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # P152 — the silver-METER projection: the local-meter shelf
    # (Nabu::MeterShelf — the scansion lane's machine output) into the
    # catalog's `enrichments` table as kind "meter" rows beside the held
    # gold (pedecerto, hypotactic), the SilverDates mold at passage grain.
    #
    # == The flag (how every surface tells silver from gold)
    #
    # model "nabu-scan" (the producer column every meter reader already
    # shows) AND payload "grade" => "silver", plus the scan's basis
    # (unique / laws / defaults) and scanner version. The payload speaks
    # each language's GOLD vocabulary so one filter reaches both: Latin
    # meter "H"/"P" with a pedecerto-style pattern ("DSDS", "DS-|DD-"),
    # Greek "dactylic hexameter"/"dactylic pentameter" with a hypotactic-
    # style quantity pattern ("-uu -- -uu …"). Readers rank gold first
    # (Query::Show) and label silver at render.
    #
    # == Never over gold, never stale
    #
    # A passage carrying ANY gold meter row is skipped (counted
    # gold_covered) — the never-overwrite-gold rule. A record whose
    # content_sha256 no longer matches the live passage is skipped
    # (counted stale): the text it scanned is not the text held. Unscanned
    # records never project. drop_stale! applies the same sha test to
    # already-projected rows after a sync re-parses a source.
    #
    # == The gate and the replay rails
    #
    # Wholesale supersede (delete the lane, re-insert) — projecting twice
    # is the same rows. Nothing reaches db/ until the owner fires `nabu
    # scan-meter --project` (MeterShelf#arm!); from then on .replay!
    # re-projects in every builder pass — full and incremental rebuild,
    # builders:refresh — so the lane survives `nabu rebuild` as a pure
    # function of local/ (a shelf-sized pass: one JSON line per scanned
    # verse passage, batched urn lookups).
    module SilverMeter
      KIND = "meter"
      MODEL = "nabu-scan"
      GRADE = "silver"
      BATCH = 2_000

      LATIN_CODES = { "hexameter" => "H", "pentameter" => "P" }.freeze
      GREEK_NAMES = { "hexameter" => "dactylic hexameter", "pentameter" => "dactylic pentameter" }.freeze

      # What one projection did.
      Report = Data.define(:projected, :stale, :gold_covered, :unresolved, :unscanned, :superseded)

      module_function

      def project!(catalog:, shelf:)
        retract!(catalog: catalog)
        counts = Hash.new(0)
        latest = {}
        shelf.each_record do |record|
          next unless record.passage?

          counts[:passage_records] += 1
          latest[record.urn] = record
        end
        counts[:unscanned] = latest.count { |_, record| !record.scanned? }
        latest.values.select(&:scanned?).each_slice(BATCH) { |slice| project_slice(catalog, slice, counts) }
        Report.new(projected: counts[:projected], stale: counts[:stale], gold_covered: counts[:gold_covered],
                   unresolved: counts[:unresolved], unscanned: counts[:unscanned],
                   superseded: counts[:passage_records] - latest.size)
      end

      def replay!(catalog:, shelf:)
        return nil unless shelf&.armed?
        return nil unless catalog.table_exists?(:enrichments)

        project!(catalog: catalog, shelf: shelf)
      end

      def retract!(catalog:)
        catalog[:enrichments].where(kind: KIND, model: MODEL).delete
      end

      # Drop projected rows of source +slug+ whose passage text moved since
      # the scan (a re-parse changed it) — the sync-time staleness guard.
      # Returns the rows removed.
      def drop_stale!(catalog:, slug:)
        return 0 unless catalog.table_exists?(:enrichments)

        scanned_sha = Sequel.function(:json_extract, Sequel[:enrichments][:payload_json], "$.content_sha256")
        moved = Sequel.~({ scanned_sha => Sequel[:passages][:content_sha256] })
        ids = catalog[:enrichments]
              .join(:passages, id: Sequel[:enrichments][:passage_id])
              .join(:documents, id: Sequel[:passages][:document_id])
              .join(:sources, id: Sequel[:documents][:source_id])
              .where(Sequel[:enrichments][:kind] => KIND, Sequel[:enrichments][:model] => MODEL,
                     Sequel[:sources][:slug] => slug)
              .where(Sequel.|({ Sequel[:passages][:withdrawn] => true }, moved))
              .select_map(Sequel[:enrichments][:id])
        ids.each_slice(BATCH).sum { |slice| catalog[:enrichments].where(id: slice).delete }
      end

      def silver?(model) = model == MODEL

      # The enrichment payload for one scanned record (module note).
      def payload(record)
        latin = record.language == "lat"
        {
          "meter" => latin ? LATIN_CODES.fetch(record.meter) : GREEK_NAMES.fetch(record.meter),
          "pattern" => latin ? latin_pattern(record) : record.word_pattern,
          "feet" => record.feet, "quantities" => record.quantities,
          "grade" => GRADE, "basis" => record.basis,
          "scanner" => "#{record.scanner} #{record.scanner_version}",
          "content_sha256" => record.content_sha256
        }
      end

      # pedecerto's pattern shapes: hexameter feet 1-4 (a fifth-foot
      # dactyl implied, a spondeiazon spelled out as five letters);
      # pentameter "XY-|DD-".
      def latin_pattern(record)
        if record.meter == "pentameter"
          "#{record.feet}-|DD-"
        else
          record.feet.end_with?("D") ? record.feet[0, 4] : record.feet
        end
      end

      def project_slice(catalog, slice, counts)
        live = catalog[:passages].where(urn: slice.map(&:urn), withdrawn: false)
                                 .select_hash(:urn, %i[id content_sha256])
        gold = gold_covered(catalog, live.values.map(&:first))
        rows = slice.filter_map do |record|
          id, sha = live[record.urn]
          verdict = if id.nil? then :unresolved
                    elsif sha != record.content_sha256 then :stale
                    elsif gold.include?(id) then :gold_covered
                    end
          if verdict
            counts[verdict] += 1
            next
          end

          { passage_id: id, kind: KIND, model: MODEL, model_version: record.scanner_version,
            payload_json: JSON.generate(payload(record)), at: Time.now }
        end
        catalog[:enrichments].multi_insert(rows) unless rows.empty?
        counts[:projected] += rows.size
      end

      def gold_covered(catalog, ids)
        return {} if ids.empty?

        catalog[:enrichments].where(kind: KIND, passage_id: ids).exclude(model: MODEL)
                             .select_map(:passage_id).to_h { |id| [id, true] }
      end
      private_class_method :project_slice, :gold_covered
    end
  end
end
