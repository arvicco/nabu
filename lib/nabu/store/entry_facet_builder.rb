# frozen_string_literal: true

require "json"
require_relative "passage_facet_builder"

module Nabu
  module Store
    # Populates the dictionary-entry grain of the facet surface (migration
    # 046: entry_facet_values + entry_facets) from the loaded entries'
    # annotations_json under config/facet_map.yml's entry_fields — the
    # PassageFacetBuilder mold at entry grain. A pure catalog projection:
    # the DictionaryLoader already persisted every entry's adapter-emitted
    # annotations (f(canonical)), so the pass re-reads the catalog, never
    # canonical, and `nabu rebuild` regenerates both tables.
    #
    # Projection rules are PassageFacetBuilder's, shared verbatim (one
    # implementation of "what a facet value is"): a String/Numeric, an
    # Array of them, or {"value", "ref"} objects; values verbatim, deduped
    # per (entry, facet, value, ref); withdrawn entries contribute nothing.
    #
    # Scale: the shelves this lane serves run to hundreds of thousands of
    # entries (JMdict 218k) and the kaikki shelves to millions, so the walk
    # never holds a shelf's payloads at once — it reads the annotated live
    # entry ids (NULL annotations_json, the common case, is never fetched),
    # then their JSON in id slices by primary key.
    #
    # Lifecycle: wholesale per source (every value row belongs to one
    # source) — #refresh_source! is SyncRunner's post-load seam, #rebuild!
    # clears both tables and re-projects every ruled source.
    module EntryFacetBuilder
      # What one rebuild projected: entries carrying ≥1 facet pair, total
      # pairs, distinct dictionary values.
      Summary = Data.define(:entries, :rows, :values)

      # Entries whose JSON is fetched per primary-key slice, and pairs per
      # multi-row insert.
      PAGE = 2_000
      INSERT_SLICE = 5_000

      module_function

      def rebuild!(catalog:, facet_map: nil, page: PAGE)
        catalog.transaction do
          catalog[:entry_facets].delete
          catalog[:entry_facet_values].delete
          totals = [0, 0, 0]
          (facet_map&.entry_sources || []).each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            next if source_id.nil?

            project_source(catalog, source_id, facet_map.entry_fields_for(slug), page)
              .each_with_index { |count, i| totals[i] += count }
          end
          Summary.new(entries: totals[0], rows: totals[1], values: totals[2])
        end
      end

      # Drop +slug+'s slice and re-project it when ruled; returns the pairs
      # written (0 for an unknown or unruled source).
      def refresh_source!(catalog:, slug:, facet_map: nil, page: PAGE)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        catalog.transaction do
          drop_source(catalog, source_id)
          fields = facet_map&.entry_fields_for(slug)
          fields ? project_source(catalog, source_id, fields, page)[1] : 0
        end
      end

      def drop_source(catalog, source_id)
        value_ids = catalog[:entry_facet_values].where(source_id: source_id).select(:id)
        catalog[:entry_facets].where(value_id: value_ids).delete
        catalog[:entry_facet_values].where(source_id: source_id).delete
      end

      # One source's ruled fields → dictionary values + pairs. Returns
      # [entries, rows, values].
      def project_source(catalog, source_id, fields, page)
        dictionary = {}
        buffer = []
        entries = 0
        rows = 0
        annotated_ids(catalog, source_id).each_slice(page) do |slice|
          catalog[:dictionary_entries].where(id: slice).select_map(%i[id annotations_json]).each do |entry_id, json|
            keys = PassageFacetBuilder.facet_keys(JSON.parse(json), fields)
            next if keys.empty?

            entries += 1
            keys.each do |key|
              buffer << [dictionary[key] ||= insert_value(catalog, source_id, key), entry_id]
            end
            rows += flush(catalog, buffer) if buffer.size >= INSERT_SLICE
          end
        end
        rows += flush(catalog, buffer)
        [entries, rows, dictionary.size]
      end

      # The live, annotated entries of +source_id+'s dictionaries, id order.
      def annotated_ids(catalog, source_id)
        dictionary_ids = catalog[:dictionaries].where(source_id: source_id).select_map(:id)
        return [] if dictionary_ids.empty?

        catalog[:dictionary_entries].where(dictionary_id: dictionary_ids, withdrawn: false)
                                    .exclude(annotations_json: nil)
                                    .select_map(:id).sort
      end

      def insert_value(catalog, source_id, (facet, value, ref))
        catalog[:entry_facet_values].insert(source_id: source_id, facet: facet, value: value, ref: ref)
      end

      def flush(catalog, buffer)
        return 0 if buffer.empty?

        count = buffer.size
        catalog[:entry_facets].import(%i[value_id entry_id], buffer)
        buffer.clear
        count
      end
    end
  end
end
