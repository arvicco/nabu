# frozen_string_literal: true

require "json"
require "yaml"

module Nabu
  module Store
    # The inline-entity index (migration 050: passage_entity_names +
    # passage_entities): the "entities" passage annotation — persons,
    # places and upstream's other typed names marked inside the text,
    # mined by EpidocParser::InlineLayer (Perseus), CopticTtParser and the
    # DHARMA Deccan parser — projected into a folded, dictionary-encoded
    # name table so `nabu entity` answers from precompiled rows. A pure
    # catalog projection like PassageFacetBuilder: the loader already
    # persisted every passage's annotations (f(canonical)), so the pass
    # re-reads the catalog, never canonical, and `nabu rebuild`
    # regenerates both tables.
    #
    # Projection rules:
    # - a record is a Hash under annotations["entities"]; its type, text,
    #   identity, key, ref and subtype project VERBATIM (strings only;
    #   blank → NULL). A record carrying none of text/identity/key/ref
    #   names nothing and mints nothing;
    # - search_key is the fold (#fold) of text, identity, key and ref,
    #   joined by U+001F so a substring match never spans two fields;
    # - names dedupe per source, pairs per (name, passage); withdrawn
    #   passages and passages of withdrawn documents contribute nothing.
    #
    # Scope: the sources config/entity_index.yml lists (#load_sources) —
    # an explicit roster, so a rebuild probes the entity-bearing slices
    # only, never the whole passages table. Lifecycle: wholesale per
    # source (#refresh_source!, the SyncRunner post-load seam); #rebuild!
    # clears both tables and re-projects every listed source.
    module EntityIndex
      NAMES_TABLE = :passage_entity_names
      TABLE = :passage_entities

      # The annotation key the parsers write the records under.
      ANNOTATION = "entities"
      FIELDS = %w[type text identity key ref subtype].freeze
      SEARCHED = %w[text identity key ref].freeze
      SEPARATOR = "\u001F"

      CONFIG_FILE = "entity_index.yml"

      class ConfigError < Nabu::Error; end

      # What one rebuild projected: passages carrying ≥1 entity, total
      # pairs, distinct dictionary names.
      Summary = Data.define(:passages, :rows, :names)

      DOCUMENT_SLICE = 200
      INSERT_SLICE = 5_000

      module_function

      # The fold both sides of a lookup pass through: combining marks
      # stripped (Normalize.fold_diacritics — Greek accents/breathings,
      # IAST dots/macrons, Coptic supralinear strokes) and Unicode case
      # folding (which also merges final sigma). Language-neutral by
      # design — a name query carries no language; DECLARED coarseness:
      # no per-language merges (Latin v/u, i/j) ride here.
      def fold(string)
        Normalize.fold_diacritics(string.to_s).downcase(:fold)
      end

      # The listed source slugs, or [] when the config file is absent (the
      # lane off). A malformed file raises ConfigError.
      def load_sources(config_dir:)
        path = File.join(config_dir, CONFIG_FILE)
        return [] unless File.exist?(path)

        sources = (YAML.safe_load_file(path) || {})["sources"]
        unless sources.is_a?(Array) && sources.all? { |slug| slug.is_a?(String) && !slug.strip.empty? }
          raise ConfigError, "#{CONFIG_FILE}: sources must be a list of source slugs"
        end

        sources
      end

      def load_default(config:) = load_sources(config_dir: config.config_dir)

      def available?(catalog)
        !catalog.nil? && catalog.table_exists?(NAMES_TABLE) && catalog.table_exists?(TABLE)
      end

      def populated?(catalog)
        available?(catalog) && !catalog[NAMES_TABLE].empty?
      end

      # nil on a catalog predating migration 050 (read and refresh paths
      # never migrate; the next write path or rebuild builds the tables).
      def rebuild!(catalog:, sources:)
        return nil unless available?(catalog)

        catalog.transaction do
          catalog[TABLE].delete
          catalog[NAMES_TABLE].delete
          totals = [0, 0, 0]
          sources.each do |slug|
            source_id = catalog[:sources].where(slug: slug).get(:id)
            next if source_id.nil?

            project_source(catalog, source_id).each_with_index { |count, i| totals[i] += count }
          end
          Summary.new(passages: totals[0], rows: totals[1], names: totals[2])
        end
      end

      # Drop +slug+'s slice and re-project it when listed; returns the
      # pairs written (0 for an unknown or unlisted source).
      def refresh_source!(catalog:, slug:, sources:)
        return 0 unless available?(catalog)

        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        catalog.transaction do
          drop_source(catalog, source_id)
          sources.include?(slug) ? project_source(catalog, source_id)[1] : 0
        end
      end

      def drop_source(catalog, source_id)
        name_ids = catalog[NAMES_TABLE].where(source_id: source_id).select(:id)
        catalog[TABLE].where(name_id: name_ids).delete
        catalog[NAMES_TABLE].where(source_id: source_id).delete
      end

      # One source's records → dictionary names + pairs. Returns
      # [passages, rows, names]. The LIKE probe skips the JSON parse for
      # passages carrying no entities layer (a superset test).
      def project_source(catalog, source_id)
        dictionary = {}
        buffer = []
        passages = 0
        rows = 0
        probe = Sequel.like(:annotations_json, %(%"#{ANNOTATION}"%))
        document_ids = catalog[:documents].where(source_id: source_id, withdrawn: false)
                                          .order(:id).select_map(:id)
        document_ids.each_slice(DOCUMENT_SLICE) do |slice|
          catalog[:passages].where(document_id: slice, withdrawn: false).where(probe)
                            .select_map(%i[id annotations_json]).each do |passage_id, json|
            records = records_of(json)
            next if records.empty?

            passages += 1
            records.each do |record|
              buffer << [dictionary[record] ||= insert_name(catalog, source_id, record), passage_id]
            end
            rows += flush(catalog, buffer) if buffer.size >= INSERT_SLICE
          end
        end
        rows += flush(catalog, buffer)
        [passages, rows, dictionary.size]
      end

      # The deduped verbatim records (FIELDS-ordered value arrays) one
      # passage's annotations carry; [] for unreadable JSON.
      def records_of(json)
        annotations = JSON.parse(json || "{}")
        raw = annotations.is_a?(Hash) ? annotations[ANNOTATION] : nil
        return [] unless raw.is_a?(Array)

        raw.filter_map { |element| record_of(element) }.uniq
      rescue JSON::ParserError
        []
      end

      def record_of(element)
        return nil unless element.is_a?(Hash)

        values = FIELDS.map { |field| present(element[field]) }
        named = FIELDS.each_index.any? { |i| SEARCHED.include?(FIELDS[i]) && values[i] }
        named ? values : nil
      end

      def present(value)
        value.is_a?(String) && !value.strip.empty? ? value : nil
      end

      def search_key(row)
        SEARCHED.filter_map { |field| row[field.to_sym] }.map { |value| fold(value) }.join(SEPARATOR)
      end

      def insert_name(catalog, source_id, values)
        row = FIELDS.map(&:to_sym).zip(values).to_h
        catalog[NAMES_TABLE].insert(row.merge(source_id: source_id, search_key: search_key(row)))
      end

      def flush(catalog, buffer)
        return 0 if buffer.empty?

        count = buffer.size
        catalog[TABLE].import(%i[name_id passage_id], buffer)
        buffer.clear
        count
      end
    end
  end
end
