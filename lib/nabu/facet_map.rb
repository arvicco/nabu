# frozen_string_literal: true

require "yaml"

module Nabu
  # The metadata-field → facet projection config (P104-1, under №R-70's
  # aggressive-mining policy): config/facet_map.yml declares, per source,
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
      @fields = parse_sources(doc["sources"] || {})
    end

    def sources = @fields.keys

    # {metadata_field => facet_name} for +slug+, or nil when unruled.
    def fields_for(slug) = @fields[slug]

    private

    def parse_sources(sources_doc)
      sources_doc.to_h do |slug, spec|
        fields = (spec || {})["fields"]
        unless fields.is_a?(Hash) && !fields.empty?
          raise ConfigError,
                "facet_map: #{slug} must declare fields: {metadata_field: facet}"
        end

        fields.each do |field, facet|
          if field.to_s.strip.empty? || facet.to_s.strip.empty?
            raise ConfigError, "facet_map: #{slug} field #{field.inspect} → #{facet.inspect} is blank"
          end
        end
        [slug, fields.to_h { |field, facet| [field.to_s, facet.to_s] }]
      end
    end
  end
end
