# frozen_string_literal: true

require "yaml"

module Nabu
  # The kind axis' config seam (P99-1 — №R-63, ruled 2026-09-13): the
  # fourth document axis, "what KIND of document is this?", as one
  # multi-label facet over a RULED 26-head class list. Two files:
  #
  # - config/kind_classes.yml — the ruled heads (+ `unknown`, upstream's
  #   own "cannot determine" as a claim, not a gap), each with a one-line
  #   desc, suggested sub-grains (extensible without re-ruling), and
  #   crosswalks to the external vocabularies that recognize it
  #   (EAGLE/FAIR, LCGFT, AAT) — pointers, never anchors: the survey
  #   verified no external standard spans cuneiform, papyri, stone,
  #   scripture, and novels at once.
  # - config/kind_map.yml — per-source folds, owner-ruled like lect
  #   rules: `map` (exact value, case-insensitive fallback), `prefix_map`
  #   (slash-path vocabularies like eBL's), `range_map` (numeric facets
  #   like tlhdig's CTH numbers), or `source_kind` (a whole-source
  #   declaration — okhc's 1.2M dynastic-history docs in one line).
  #
  # Normalization (survey §4b): strip trailing uncertainty markers →
  # split composites → per-fragment lookup → 0..n class paths; a fragment
  # no rule covers yields "unmapped" — the honest, filterable bucket,
  # distinct from the ruled class "unknown" and from no-row-at-all (a
  # source without genre-shaped data speaks through its posture).
  class Kinds
    class ConfigError < Nabu::Error; end

    UNMAPPED = "unmapped"

    KindClass = Data.define(:name, :desc, :subs, :crosswalk)

    # One source's fold rule. Exactly one of +facet+ (with maps) or
    # +source_kind+ is live — validated at load.
    Rule = Data.define(:slug, :facet, :map, :fold_map, :prefix_map, :range_map, :source_kind)

    attr_reader :classes, :split, :strip

    def self.load(classes_path:, map_path:)
      new(YAML.safe_load_file(classes_path) || {}, YAML.safe_load_file(map_path) || {})
    end

    # The default instance for a Config root; nil when the files are
    # absent (a stripped clone) — lane off, never an error.
    def self.load_default(config:)
      classes_path = File.join(config.config_dir, "kind_classes.yml")
      map_path = File.join(config.config_dir, "kind_map.yml")
      return nil unless File.exist?(classes_path) && File.exist?(map_path)

      load(classes_path: classes_path, map_path: map_path)
    end

    def initialize(classes_doc, map_doc)
      @classes = parse_classes(classes_doc)
      @split = Array(map_doc["split"] || [])
      @strip = Array(map_doc["strip"] || [])
      @rules = parse_rules(map_doc["sources"] || {})
    end

    def class_names = @classes.keys
    def sources = @rules.keys
    def rule_for(slug) = @rules[slug]
    def facet_for(slug) = @rules[slug]&.facet
    def source_kind(slug) = @rules[slug]&.source_kind

    # +value+ (one upstream facet value) → 0..n class paths for +slug+,
    # deduped, "unmapped" per uncovered fragment. A source with no rule
    # returns [] — nothing to claim.
    def normalize(slug, value)
      rule = @rules[slug]
      return [] if rule.nil? || rule.facet.nil?

      fragments(value).flat_map { |fragment| lookup(rule, fragment) }.uniq
    end

    private

    def fragments(value)
      parts = [value.to_s]
      @split.each { |sep| parts = parts.flat_map { |part| part.split(sep) } }
      parts.map { |part| strip_markers(part.strip) }.reject(&:empty?)
    end

    def strip_markers(fragment)
      @strip.each do |marker|
        fragment = fragment.delete_suffix(marker).rstrip while fragment.end_with?(marker)
      end
      fragment
    end

    def lookup(rule, fragment)
      exact = rule.map[fragment] || rule.fold_map[fragment.downcase]
      return exact if exact

      prefix = rule.prefix_map.find { |head, _| fragment.start_with?(head) }
      return prefix[1] if prefix

      range = (rule.range_map.find { |span, _| span.cover?(fragment.to_i) } if fragment.match?(/\A\d+\z/))
      return range[1] if range

      [UNMAPPED]
    end

    # -- parsing + validation ----------------------------------------------

    def parse_classes(doc)
      (doc["classes"] || {}).to_h do |name, spec|
        spec ||= {}
        [name, KindClass.new(name: name, desc: spec["desc"].to_s,
                             subs: Array(spec["subs"]).map(&:to_s),
                             crosswalk: spec["crosswalk"] || {})]
      end
    end

    def parse_rules(sources_doc)
      sources_doc.to_h do |slug, spec|
        spec ||= {}
        facet = spec["facet"]
        source_kind = spec["source_kind"]
        if (facet && source_kind) || (!facet && !source_kind)
          raise ConfigError, "kind_map: #{slug} must declare exactly one of facet:/source_kind:"
        end

        validate_target(slug, source_kind) if source_kind
        map = targets_of(slug, spec["map"])
        [slug, Rule.new(slug: slug, facet: facet, map: map,
                        fold_map: map.transform_keys(&:downcase),
                        prefix_map: targets_of(slug, spec["prefix_map"]),
                        range_map: ranges_of(slug, spec["range_map"]),
                        source_kind: source_kind)]
      end
    end

    def targets_of(slug, doc)
      (doc || {}).to_h do |key, target|
        paths = Array(target).map(&:to_s)
        paths.each { |path| validate_target(slug, path) }
        [key.to_s, paths]
      end
    end

    def ranges_of(slug, doc)
      (doc || {}).to_h do |span, target|
        match = span.to_s.match(/\A(\d+)-(\d+)\z/)
        raise ConfigError, "kind_map: #{slug} range key #{span.inspect} is not N-M" if match.nil?

        paths = Array(target).map(&:to_s)
        paths.each { |path| validate_target(slug, path) }
        [Range.new(match[1].to_i, match[2].to_i), paths]
      end
    end

    def validate_target(slug, path)
      head = path.split("/", 2).first
      return if @classes.key?(head)

      raise ConfigError,
            "kind_map: #{slug} maps to #{path.inspect} but #{head.inspect} is not a declared class"
    end
  end
end
