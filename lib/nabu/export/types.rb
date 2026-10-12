# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Export
    # The exporter's shared vocabulary (P121-1) — loaded before the frame
    # and the tables, which build their column lists from it at class-body
    # time. The table contract itself is stated in lib/nabu/export.rb.
    class Error < Nabu::Error; end

    FORMATS = %w[csv jsonl].freeze

    # One documented column of a table.
    Column = Data.define(:name, :description)

    # One output row: +values+ aligned with the table's columns, +draws+
    # the [source slug, effective license class] pairs the row draws on
    # (one for a document, one per endpoint for an edge; [nil, nil] for an
    # endpoint the catalog cannot resolve).
    Row = Data.define(:values, :draws)

    # A finished export: both paths, the row total, elapsed seconds.
    Result = Data.define(:table, :data_path, :manifest_path, :rows, :seconds)
  end
end
