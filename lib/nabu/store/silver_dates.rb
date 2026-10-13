# frozen_string_literal: true

module Nabu
  module Store
    # P122-1 — the silver-DATE projection: the local-dates shelf
    # (Nabu::DateShelf — model/tool date estimates, non-derivable) into
    # document_axes as SILVER-grade dated rows, the silver-lemma mold at
    # document grain.
    #
    # == The flag (how every surface tells silver from upstream)
    #
    # Each projected row carries axis_source "silver-dates" (the lane) AND
    # date_class "silver" (the basis — what `--date-basis`, the documents
    # export and the lemma rollups read), precision "estimate", and a
    # date_raw that names the estimate's basis label, estimator + version
    # and confidence — the provenance a reader sees on the card. Upstream-
    # promising consumers (the any-row --from/--to filter, the century
    # histogram, source date coverage, lect date inference, the published
    # nabu-data document dates, the health checks that read lanes) exclude
    # the lane through .upstream; surfaces that pick a document's PRIMARY
    # date rank silver LAST (an upstream date always wins) and render the
    # class.
    #
    # == The gate and the replay rails
    #
    # The projection is wholesale supersede (delete the lane, re-insert the
    # latest estimate per urn for every LIVE document) — so projecting twice
    # is the same rows, and rebuild and re-project are the same operation.
    # Nothing reaches db/ until the owner fires `nabu silver-dates
    # --project`, which records the ruling on the shelf (DateShelf#arm!);
    # from then on .replay! re-projects behind the timeline at every full
    # and incremental rebuild, `builders:refresh` and sync — the timeline
    # builder drops every axis row, so the replay must follow it.
    module SilverDates
      AXIS_SOURCE = "silver-dates"
      DATE_CLASS = "silver"
      PRECISION = "estimate"
      BATCH = 1_000

      # What one projection did: rows minted, estimates whose urn names no
      # live document (shelved for material not held, or withdrawn), and
      # estimates superseded by a later one for the same urn.
      Report = Data.define(:projected, :unresolved, :superseded)

      module_function

      # Re-project the shelf wholesale (class note). Returns a Report.
      def project!(catalog:, shelf:)
        catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
        records = 0
        shelf.each_record { records += 1 }
        latest = shelf.latest_by_urn
        projected = 0
        latest.values.each_slice(BATCH) do |slice|
          ids = live_document_ids(catalog, slice.map(&:urn))
          rows = slice.filter_map { |record| (id = ids[record.urn]) && row(id, record) }
          catalog[:document_axes].multi_insert(rows) unless rows.empty?
          projected += rows.size
        end
        Report.new(projected: projected, unresolved: latest.size - projected,
                   superseded: records - latest.size)
      end

      # The replay rail: re-project when the owner has armed the shelf; nil
      # (nothing touched) when the shelf is absent or unarmed.
      def replay!(catalog:, shelf:)
        return nil unless shelf&.armed?

        project!(catalog: catalog, shelf: shelf)
      end

      # Drop the lane (the --retract half). Returns the rows removed.
      def retract!(catalog:)
        catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
      end

      # +dataset+ without the silver lane — the one exclusion every
      # upstream-promising axis consumer applies (+axes+ names the table
      # when it is joined or aliased).
      def upstream(dataset, axes: Sequel[:document_axes])
        dataset.exclude(axes[:axis_source] => AXIS_SOURCE)
      end

      # The primary-date rank: upstream rows 0, silver rows 1 — sorted
      # first, it makes any upstream date outrank every estimate.
      def rank_expr(axes = Sequel[:document_axes])
        Sequel.case([[{ axes[:axis_source] => AXIS_SOURCE }, 1]], 0)
      end

      def silver?(row) = row[:axis_source] == AXIS_SOURCE

      def live_document_ids(catalog, urns)
        catalog[:documents].where(urn: urns, withdrawn: false).select_hash(:urn, :id)
      end

      def row(document_id, record)
        { document_id: document_id, not_before: record.not_before, not_after: record.not_after,
          precision: PRECISION, date_raw: provenance(record), axis_source: AXIS_SOURCE,
          date_class: DATE_CLASS }
      end

      # The estimate's provenance as the card shows it:
      # "model estimate — chronos 0.3, confidence 0.8: note".
      def provenance(record)
        text = "#{record.basis} estimate — #{record.estimator} #{record.estimator_version}"
        text += ", confidence #{record.confidence}" unless record.confidence.nil?
        text += ": #{record.note}" unless record.note.to_s.strip.empty?
        text
      end
      private_class_method :live_document_ids, :row, :provenance
    end
  end
end
