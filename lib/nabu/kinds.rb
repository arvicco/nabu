# frozen_string_literal: true

require "yaml"

module Nabu
  # The kind axis' config seam (P99-1 — №R-63, ruled 2026-09-13): the
  # fourth document axis, "what KIND of document is this?", as one
  # multi-label facet over a RULED class list (21 heads + unknown since
  # №R-66's literary-family restructure, 2026-09-18). Two files:
  #
  # - config/kind_classes.yml — the ruled heads (+ `unknown`, upstream's
  #   own "cannot determine" as a claim, not a gap), each with a one-line
  #   desc, suggested sub-grains (extensible without re-ruling), and
  #   crosswalks to the external vocabularies that recognize it
  #   (EAGLE/FAIR, LCGFT, AAT) — pointers, never anchors: the survey
  #   verified no external standard spans cuneiform, papyri, stone,
  #   scripture, and novels at once. A slash-keyed entry
  #   (`literary/poetry`) is a named SUB-CLASS carrying its own desc and
  #   crosswalks under a declared head (№R-66, owner 2026-09-18: the
  #   literature families live under the `literary` head; the bare head
  #   is upstream's own "literary, unspecified").
  # - config/kind_map.yml — per-source folds, owner-ruled like lect
  #   rules: `map` (exact value, case-insensitive fallback), `prefix_map`
  #   (slash-path vocabularies like eBL's), `range_map` (numeric facets
  #   like tlhdig's CTH numbers), or `source_kind` (a whole-source
  #   declaration — okhc's 1.2M dynastic-history docs in one line).
  #   A source may also carry `deliberate:` — upstream values DECLARED
  #   not to be genre claims at all (physical layout, cult context, a
  #   bare copy marker), each with its one-line reason. A deliberate
  #   fragment folds to nothing: it is a reviewed non-claim, rendered as
  #   its own census section, never `unmapped` noise (P101, Q75).
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

    # One source's fold rule. Exactly one of +facet+ (map facet rows),
    # +metadata+ (map documents.metadata_json fields — P100-1),
    # +walk+ (a named canonical-tree walker in KindBuilder — P100-3:
    # papyri's HGV keywords live in sidecar files no facet or metadata
    # field carries), or +source_kind+ (whole-source declaration) is
    # live — validated at load. +regex_map+ (P100-1) collects EVERY
    # matching pattern's targets (aozora's "NDC 911 913" is
    # multi-label by design), unlike the first-hit exact/prefix/range
    # chain. +deliberate+ (P101) is the reviewed not-genre set: a
    # fragment in it folds to NOTHING (value → reason, case-insensitive
    # like the exact map).
    Rule = Data.define(:slug, :facet, :metadata, :walk, :map, :fold_map, :prefix_map, :regex_map,
                       :range_map, :source_kind, :deliberate, :deliberate_fold)

    # The canonical-tree walkers KindBuilder implements; a walk: value
    # outside this set is a config error, not a silent no-op.
    WALKERS = %w[hgv-keywords].freeze

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
    def heads = @classes.keys.map { |name| name.split("/", 2).first }.uniq
    def sources = @rules.keys

    # Every declared not-genre value, for the census' own section:
    # [slug, value, reason] rows in config order.
    def deliberate_declarations
      @rules.flat_map do |slug, rule|
        rule.deliberate.map { |value, reason| [slug, value, reason] }
      end
    end

    def rule_for(slug) = @rules[slug]
    def facet_for(slug) = @rules[slug]&.facet
    def metadata_for(slug) = @rules[slug]&.metadata
    def walk_for(slug) = @rules[slug]&.walk
    def source_kind(slug) = @rules[slug]&.source_kind

    # +value+ (one upstream facet or metadata value) → 0..n class paths
    # for +slug+, deduped, "unmapped" per uncovered fragment. A source
    # with no rule (or a pure declaration) returns [] — nothing to map.
    def normalize(slug, value)
      rule = @rules[slug]
      return [] if rule.nil? || rule.source_kind

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
      return [] if rule.deliberate.key?(fragment) || rule.deliberate_fold.key?(fragment.downcase)

      exact = rule.map[fragment] || rule.fold_map[fragment.downcase]
      return exact if exact

      prefix = rule.prefix_map.find { |head, _| fragment.start_with?(head) }
      return prefix[1] if prefix

      regex_hits = rule.regex_map.select { |pattern, _| fragment.match?(pattern) }.flat_map { |_, t| t }
      return regex_hits unless regex_hits.empty?

      range = (rule.range_map.find { |span, _| span.cover?(fragment.to_i) } if fragment.match?(/\A\d+\z/))
      return range[1] if range

      [UNMAPPED]
    end

    # -- parsing + validation ----------------------------------------------

    def parse_classes(doc)
      classes = (doc["classes"] || {}).to_h do |name, spec|
        spec ||= {}
        [name, KindClass.new(name: name, desc: spec["desc"].to_s,
                             subs: Array(spec["subs"]).map(&:to_s),
                             crosswalk: spec["crosswalk"] || {})]
      end
      classes.each_key do |name|
        head = name.split("/", 2).first
        next if classes.key?(head)

        raise ConfigError,
              "kind_classes: #{name.inspect} is a sub-class of #{head.inspect}, which is not declared"
      end
      classes
    end

    def parse_rules(sources_doc)
      sources_doc.to_h do |slug, spec|
        spec ||= {}
        facet = spec["facet"]
        metadata = spec.key?("metadata") ? Array(spec["metadata"]).map(&:to_s) : nil
        walk = spec["walk"]
        source_kind = spec["source_kind"]
        if [facet, metadata, walk, source_kind].compact.size != 1
          raise ConfigError,
                "kind_map: #{slug} must declare exactly one of facet:/metadata:/walk:/source_kind:"
        end
        if walk && !WALKERS.include?(walk)
          raise ConfigError,
                "kind_map: #{slug} walk #{walk.inspect} is not a known walker (#{WALKERS.join(', ')})"
        end

        validate_target(slug, source_kind) if source_kind
        map = targets_of(slug, spec["map"])
        deliberate = (spec["deliberate"] || {}).to_h { |value, reason| [value.to_s, reason.to_s] }
        [slug, Rule.new(slug: slug, facet: facet, metadata: metadata, walk: walk, map: map,
                        fold_map: map.transform_keys(&:downcase),
                        prefix_map: targets_of(slug, spec["prefix_map"]),
                        regex_map: regexes_of(slug, spec["regex_map"]),
                        range_map: ranges_of(slug, spec["range_map"]),
                        source_kind: source_kind, deliberate: deliberate,
                        deliberate_fold: deliberate.transform_keys(&:downcase))]
      end
    end

    def regexes_of(slug, doc)
      (doc || {}).to_h do |pattern, target|
        compiled = begin
          Regexp.new(pattern.to_s)
        rescue RegexpError => e
          raise ConfigError, "kind_map: #{slug} regex #{pattern.inspect} — #{e.message}"
        end
        paths = Array(target).map(&:to_s)
        paths.each { |path| validate_target(slug, path) }
        [compiled, paths]
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
