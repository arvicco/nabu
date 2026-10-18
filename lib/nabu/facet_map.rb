# frozen_string_literal: true

require "yaml"

module Nabu
  # The metadata-field → facet projection config (P104-1, under the
  # aggressive-mining policy, owner-ruled 2026-09-26): config/facet_map.yml declares, per source,
  # which documents.metadata_json fields project into document_facets
  # rows and under which facet name — so a source whose axis-shaped
  # fields already ride the catalog verbatim (okhc's corpus, seal's
  # genre/period, rsti's whole inventory sheet) gets its facets as a pure
  # catalog projection: no adapter change, no canonical re-parse, and the
  # 1.2M-document shelf faces one metadata scan instead of a re-parse.
  #
  # The kind_map discipline applies: the config is the rule surface
  # (adding a source is rule curation, not code), values project VERBATIM
  # (the facet value IS the upstream claim — normalization is the kind
  # lane's job, never this one's), arrays project one row per element,
  # and absent/empty fields contribute nothing (absence, never a row).
  # Consumed by Store::FacetBuilder in both rebuild flavors and by
  # SyncRunner's post-load refresh (the P47-r3 no-lane-lags-a-sync rule).
  #
  # The passage grain rides the same entry: a source's passage_fields
  # name passages.annotations_json keys that project into the passage
  # facet tables (Store::PassageFacetBuilder) — claims upstream makes per
  # article, which a document facet would smear. Same verbatim rules.
  class FacetMap
    class ConfigError < Nabu::Error; end

    def self.load(path)
      new(YAML.safe_load_file(path) || {})
    end

    # The config-repo table, or nil when the file is absent (a stripped
    # clone) — lane off, never an error (the Kinds.load_default stance).
    def self.load_default(config:)
      path = File.join(config.config_dir, "facet_map.yml")
      return nil unless File.exist?(path)

      load(path)
    end

    def initialize(doc)
      @fields = {}
      @passage_fields = {}
      parse_sources(doc["sources"] || {})
    end

    # The document-field lane's sources (Store::FacetBuilder walks these).
    def sources = @fields.keys

    # {metadata_field => facet_name} for +slug+, or nil when unruled.
    def fields_for(slug) = @fields[slug]

    # The passage-grain lane's sources (Store::PassageFacetBuilder).
    def passage_sources = @passage_fields.keys

    # {annotation_field => facet_name} for +slug+'s passages, or nil.
    def passage_fields_for(slug) = @passage_fields[slug]

    private

    # The passage grain is a sibling key on the same per-source entry —
    # the smallest honest extension: one rule surface per source, one
    # loader, one validation discipline, and a source may carry either
    # lane or both. A separate passage_facet_map.yml would split one
    # source's projection rules across two files for no gain.
    def parse_sources(sources_doc)
      sources_doc.each do |slug, spec|
        spec ||= {}
        unless spec.key?("fields") || spec.key?("passage_fields")
          raise ConfigError,
                "facet_map: #{slug} must declare fields: {metadata_field: facet} " \
                "and/or passage_fields: {annotation_field: facet}"
        end

        @fields[slug] = parse_lane(slug, "fields", spec["fields"]) if spec.key?("fields")
        if spec.key?("passage_fields")
          @passage_fields[slug] = parse_lane(slug, "passage_fields", spec["passage_fields"])
        end
      end
    end

    def parse_lane(slug, key, fields)
      unless fields.is_a?(Hash) && !fields.empty?
        raise ConfigError, "facet_map: #{slug} #{key} must be a non-empty {field: facet} map"
      end

      fields.each do |field, facet|
        if field.to_s.strip.empty? || facet.to_s.strip.empty?
          raise ConfigError, "facet_map: #{slug} #{key} #{field.inspect} → #{facet.inspect} is blank"
        end
      end
      fields.to_h { |field, facet| [field.to_s, facet.to_s] }
    end
  end
end
