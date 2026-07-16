# frozen_string_literal: true

require "json"

module Nabu
  module Query
    # Reader over the derived urn_notes index (P24-1): the owner's
    # annotations, keyed by any urn the corpus knows. Three read grains —
    # the notes ON one urn (the show/define footer), the count of
    # passage-note CHILDREN under a document urn (the document footer's
    # honest pointer), and the bounded enumeration (`nabu note --list`).
    # Reads the catalog through raw datasets (the Show/Search stance) and
    # degrades to silence on a catalog predating migration 015 — the notes
    # lane is an absence there, never a crash.
    class Notes
      # One note row. +tags+ is a (possibly empty) Array of Strings.
      Note = Data.define(:urn, :note, :topic, :tags, :added, :provenance)

      # One enumeration page: rows shown plus the honest total (the
      # Query::List pattern) so the renderer can say "… N more".
      Page = Data.define(:rows, :total)

      DEFAULT_LIMIT = 20

      def initialize(catalog:)
        @catalog = catalog
      end

      def available?
        @catalog.table_exists?(:urn_notes)
      end

      # Every note on exactly +urn+, oldest first (accretion order).
      def for_urn(urn, topic: nil)
        return [] unless available?

        dataset = @catalog[:urn_notes].where(urn: urn)
        dataset = dataset.where(topic: topic) if topic
        dataset.order(:added, :id).all.map { |row| build(row) }
      end

      # How many notes sit on CHILDREN of +urn+ (passage notes under a
      # document, page notes under an article): urns extending it by a
      # citation suffix.
      def child_count(urn)
        return 0 unless available?

        escaped = urn.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
        @catalog[:urn_notes].where(Sequel.like(:urn, "#{escaped}:%")).count
      end

      # The bounded enumeration, oldest first; +topic+ narrows.
      def list(topic: nil, limit: DEFAULT_LIMIT)
        return Page.new(rows: [], total: 0) unless available?

        dataset = @catalog[:urn_notes]
        dataset = dataset.where(topic: topic) if topic
        Page.new(rows: dataset.order(:added, :id).limit(limit).all.map { |row| build(row) },
                 total: dataset.count)
      end

      private

      def build(row)
        Note.new(
          urn: row.fetch(:urn), note: row.fetch(:note), topic: row.fetch(:topic),
          tags: row[:tags] ? JSON.parse(row[:tags]) : [],
          added: row.fetch(:added), provenance: row.fetch(:provenance)
        )
      end
    end
  end
end
