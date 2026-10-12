# frozen_string_literal: true

module Nabu
  module Export
    # The per-page axis read every table shares (P121-1): one indexed
    # document_axes query for a page of document ids, folded into one
    # summary per document.
    #
    # == The date envelope (one row's bounds, never a fabricated hull)
    #
    # A document may carry several timeline rows (several dating lanes, a
    # chronicle's passage-grain annals, a place-only or artifact-script
    # lane). The exported envelope is the PRIMARY dated row — document
    # grain only (passage_seq_from NULL), at least one bound present, the
    # earliest by coalesce(not_before, not_after), then row id — the rule
    # `nabu show` renders, so an export never disagrees with the card. Its
    # bounds ship verbatim (signed historical years, no year 0; a NULL
    # bound is open-ended), with the precision, the minting lane
    # (axis_source) and the upstream date string beside them. date_class
    # NULL on a dated row means the source's own artifact/typed date
    # (migration 034) and exports as "artifact"; "composition" stays as
    # stored. Place is the first document-grain row carrying any place
    # field; artifact_script the first carrying one.
    module Axes
      Summary = Data.define(:not_before, :not_after, :precision, :date_class, :date_basis, :date_raw,
                            :place_name, :place_ref, :place_lat, :place_lon, :artifact_script)

      EMPTY = Summary.new(**Summary.members.to_h { |member| [member, nil] })

      ARTIFACT_CLASS = "artifact"

      UNDATED = { not_before: nil, not_after: nil, precision: nil, date_class: nil, date_basis: nil,
                  date_raw: nil }.freeze

      COLUMNS = %i[document_id id not_before not_after precision date_class axis_source date_raw
                   place_name place_ref place_lat place_lon artifact_script].freeze

      module_function

      # { document_id => Summary } for +ids+; documents without a
      # document-grain axis row are absent (callers fall back to EMPTY).
      def by_document(catalog, ids)
        return {} if ids.empty? || !catalog.table_exists?(:document_axes)

        rows = catalog[:document_axes].where(document_id: ids, passage_seq_from: nil)
                                      .order(:document_id, :id).select(*COLUMNS).all
        rows.group_by { |row| row[:document_id] }.transform_values { |group| summarize(group) }
      end

      def summarize(rows)
        dated = rows.select { |row| row[:not_before] || row[:not_after] }
                    .min_by { |row| [row[:not_before] || row[:not_after], row[:id]] }
        place = rows.find { |row| row[:place_name] || row[:place_ref] || row[:place_lat] }
        Summary.new(**date_fields(dated), **place_fields(place),
                    artifact_script: rows.filter_map { |row| row[:artifact_script] }.first)
      end

      def date_fields(row)
        return UNDATED unless row

        { not_before: row[:not_before], not_after: row[:not_after], precision: row[:precision],
          date_class: row[:date_class] || ARTIFACT_CLASS, date_basis: row[:axis_source], date_raw: row[:date_raw] }
      end

      def place_fields(row)
        { place_name: row&.dig(:place_name), place_ref: row&.dig(:place_ref),
          place_lat: row&.dig(:place_lat), place_lon: row&.dig(:place_lon) }
      end
      private_class_method :summarize, :date_fields, :place_fields
    end
  end
end
