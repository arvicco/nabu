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
  #
  # The dictionary-entry grain is the third sibling: entry_fields name
  # dictionary_entries.annotations_json keys that project into the entry
  # facet tables (Store::EntryFacetBuilder) — JMdict's domain labels,
  # WOLD's semantic fields, TLS's concept assignments. Same rules again.
  #
  # The token grain feeds the PASSAGE tables: token_fields name CoNLL-U
  # MISC keys carried on each stored token (passages.annotations_json
  # "tokens"[]."misc" — DCS's WordSem sense ids), projected as passage
  # facets — the passage carries the facet when any of its tokens does.
  # A rule is a facet name, or {facet, shelf} when the values are entry
  # ids of a dictionary shelf (the ref then names the entry's urn,
  # urn:nabu:dict:<shelf>:<id>). The pair surface has no token position,
  # so token identity is recovered on the read path from the stored
  # tokens themselves (Query::Senses, show --senses).
  class FacetMap
    class ConfigError < Nabu::Error; end

    # The per-source lane keys: document metadata, passage annotations,
    # dictionary-entry annotations.
    LANES = %w[fields passage_fields entry_fields token_fields].freeze

    # One token_fields rule: the facet name, and the dictionary shelf whose
    # entry ids the values are (nil when the values are bare labels).
    TokenField = Data.define(:facet, :shelf)

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
      @entry_fields = {}
      @token_fields = {}
      @passage_order = []
      parse_sources(doc["sources"] || {})
    end

    # The document-field lane's sources (Store::FacetBuilder walks these).
    def sources = @fields.keys

    # {metadata_field => facet_name} for +slug+, or nil when unruled.
    def fields_for(slug) = @fields[slug]

    # The passage-grain lane's sources (Store::PassageFacetBuilder): those
    # ruling passage_fields, token_fields or both, in declaration order.
    def passage_sources = @passage_order.dup

    # {annotation_field => facet_name} for +slug+'s passages, or nil.
    def passage_fields_for(slug) = @passage_fields[slug]

    # The dictionary-entry lane's sources (Store::EntryFacetBuilder).
    def entry_sources = @entry_fields.keys

    # {annotation_field => facet_name} for +slug+'s dictionary entries, or nil.
    def entry_fields_for(slug) = @entry_fields[slug]

    # {misc_key => TokenField} for +slug+'s tokens, or nil when unruled.
    def token_fields_for(slug) = @token_fields[slug]

    # The distinct dictionary shelves token rules under +facet+ name — the
    # shelves a sense lookup resolves glosses against.
    def token_shelves(facet)
      @token_fields.values.flat_map(&:values).select { |field| field.facet == facet.to_s }
                                             .filter_map(&:shelf).uniq
    end

    private

    # The passage grain is a sibling key on the same per-source entry —
    # the smallest honest extension: one rule surface per source, one
    # loader, one validation discipline, and a source may carry either
    # lane or both. A separate passage_facet_map.yml would split one
    # source's projection rules across two files for no gain.
    def parse_sources(sources_doc)
      sources_doc.each do |slug, spec|
        spec ||= {}
        unless LANES.any? { |key| spec.key?(key) }
          raise ConfigError,
                "facet_map: #{slug} must declare fields: {metadata_field: facet}, " \
                "passage_fields: {annotation_field: facet}, entry_fields: {annotation_field: facet} " \
                "and/or token_fields: {misc_key: facet | {facet, shelf}}"
        end

        @fields[slug] = parse_lane(slug, "fields", spec["fields"]) if spec.key?("fields")
        if spec.key?("passage_fields")
          @passage_fields[slug] = parse_lane(slug, "passage_fields", spec["passage_fields"])
        end
        @entry_fields[slug] = parse_lane(slug, "entry_fields", spec["entry_fields"]) if spec.key?("entry_fields")
        @token_fields[slug] = parse_token_lane(slug, spec["token_fields"]) if spec.key?("token_fields")
        @passage_order << slug if spec.key?("passage_fields") || spec.key?("token_fields")
      end
    end

    def parse_token_lane(slug, fields)
      unless fields.is_a?(Hash) && !fields.empty?
        raise ConfigError, "facet_map: #{slug} token_fields must be a non-empty {misc_key: facet} map"
      end

      fields.to_h do |key, rule|
        facet, shelf = rule.is_a?(Hash) ? [rule["facet"], rule.fetch("shelf", :none)] : [rule, :none]
        if key.to_s.strip.empty? || !facet.is_a?(String) || facet.strip.empty? ||
           (shelf != :none && (!shelf.is_a?(String) || shelf.strip.empty?))
          raise ConfigError, "facet_map: #{slug} token_fields #{key.inspect} → #{rule.inspect} must be a facet " \
                             "name or {facet: NAME, shelf: DICTIONARY_SLUG}"
        end

        [key.to_s, TokenField.new(facet: facet, shelf: shelf == :none ? nil : shelf)]
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
