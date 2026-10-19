# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # Populates the passage-grain facet surface (migration 045:
    # passage_facet_values + passage_facets) from the loaded passages'
    # annotations_json under config/facet_map.yml's passage_fields — the
    # passage-grain sibling of FacetBuilder's metadata-field lane. A pure
    # catalog projection: the loader already persisted every passage's
    # adapter-emitted annotations (f(canonical)), so the pass re-reads the
    # catalog, never canonical, and `nabu rebuild` regenerates both tables.
    #
    # Projection rules (the FacetMap discipline, passage grain):
    # - a field's value may be a String (one row), a Numeric (stringified),
    #   an Array of either, or an Array of {"value" => name, "ref" =>
    #   authority ref} objects — the entity shape; anything else (nil,
    #   blank strings, a ref-only object, nested arrays) mints nothing;
    # - values project VERBATIM (only emptiness is tested), deduped per
    #   (passage, facet, value, ref);
    # - withdrawn passages and passages of withdrawn documents contribute
    #   nothing; a value exists only while a live pair references it.
    #
    # Lifecycle: wholesale per source. Every value row belongs to one
    # source, so a slice drops by source (value ids → their pair range on
    # the (value_id, passage_id) primary key) and re-projects without
    # touching any other source — the seam SyncRunner calls post-load, and
    # the reason a source ruled out of the config loses its rows on its
    # next refresh. #rebuild! clears both tables and re-projects every
    # ruled source.
    module PassageFacetBuilder
      # What one rebuild projected: passages carrying ≥1 facet pair,
      # total pairs, distinct dictionary values.
      Summary = Data.define(:passages, :rows, :values)

      # Documents fetched per passage query (document_id probes on the
      # (document_id, sequence) unique index's left prefix — never a scan of
      # the whole passages table) and pairs per multi-row insert.
      DOCUMENT_SLICE = 200
      INSERT_SLICE = 5_000

      module_function

      def rebuild!(catalog:, facet_map: nil)
        catalog.transaction do
          catalog[:passage_facets].delete
          catalog[:passage_facet_values].delete
          totals = [0, 0, 0]
          (facet_map&.passage_sources || []).each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            next if source_id.nil?

            project_source(catalog, source_id, facet_map.passage_fields_for(slug))
              .each_with_index { |count, i| totals[i] += count }
          end
          Summary.new(passages: totals[0], rows: totals[1], values: totals[2])
        end
      end

      # Drop +slug+'s slice and re-project it when ruled; returns the pairs
      # written (0 for an unknown or unruled source).
      def refresh_source!(catalog:, slug:, facet_map: nil)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        catalog.transaction do
          drop_source(catalog, source_id)
          fields = facet_map&.passage_fields_for(slug)
          fields ? project_source(catalog, source_id, fields)[1] : 0
        end
      end

      def drop_source(catalog, source_id)
        value_ids = catalog[:passage_facet_values].where(source_id: source_id).select(:id)
        catalog[:passage_facets].where(value_id: value_ids).delete
        catalog[:passage_facet_values].where(source_id: source_id).delete
      end

      # One source's ruled fields → dictionary values + pairs. Returns
      # [passages, rows, values]. The LIKE probe skips the JSON parse for
      # passages carrying none of the fields (a superset test: "_" in a
      # field name is a LIKE wildcard, which only widens it).
      def project_source(catalog, source_id, fields)
        probe = Sequel.|(*fields.keys.map { |field| Sequel.like(:annotations_json, %(%"#{field}"%)) })
        dictionary = {}
        buffer = []
        passages = 0
        rows = 0
        document_ids = catalog[:documents].where(source_id: source_id, withdrawn: false)
                                          .order(:id).select_map(:id)
        document_ids.each_slice(DOCUMENT_SLICE) do |slice|
          catalog[:passages].where(document_id: slice, withdrawn: false).where(probe)
                            .select_map(%i[id annotations_json]).each do |passage_id, json|
            keys = facet_keys(JSON.parse(json || "{}"), fields)
            next if keys.empty?

            passages += 1
            keys.each do |key|
              buffer << [dictionary[key] ||= insert_value(catalog, source_id, key), passage_id]
            end
            rows += flush(catalog, buffer) if buffer.size >= INSERT_SLICE
          end
        end
        rows += flush(catalog, buffer)
        [passages, rows, dictionary.size]
      end

      # The deduped [facet, value, ref] keys one passage's annotations
      # carry under +fields+.
      def facet_keys(annotations, fields)
        return [] unless annotations.is_a?(Hash)

        keys = []
        fields.each do |field, facet|
          raw = annotations[field]
          (raw.is_a?(Array) ? raw : [raw]).each do |element|
            value, ref = value_and_ref(element)
            keys << [facet, value, ref] if value
          end
        end
        keys.uniq
      end

      def value_and_ref(element)
        case element
        when String, Numeric then [present(element.to_s), nil]
        when Hash
          value = element["value"]
          return [nil, nil] unless value.is_a?(String) || value.is_a?(Numeric)

          ref = element["ref"]
          [present(value.to_s), ref.nil? ? nil : present(ref.to_s)]
        else [nil, nil]
        end
      end

      def present(string) = string.strip.empty? ? nil : string

      def insert_value(catalog, source_id, (facet, value, ref))
        catalog[:passage_facet_values].insert(source_id: source_id, facet: facet, value: value, ref: ref)
      end

      def flush(catalog, buffer)
        return 0 if buffer.empty?

        count = buffer.size
        catalog[:passage_facets].import(%i[value_id passage_id], buffer)
        buffer.clear
        count
      end
    end
  end
end
