# frozen_string_literal: true

require "yaml"

module Nabu
  # The consolidated core-layer posture record (P61-0, D59-f wave 1):
  # config/postures.yml declares per-source JUDGMENT for each core layer —
  # lect (the P59-4 record, migrated verbatim), dating, places, script —
  # one file, per-layer keys, so "no adapter without a posture" is one
  # mechanism instead of four.
  #
  # The P59-4 doctrine carries over unchanged: machine-knowable postures
  # are NEVER declared here (a source named by a lect_facet_rules.yml rule
  # or a lect_overrides.yml row is postured by those files; an
  # artifact_scripts.yml row likewise states its own machine fact); this
  # file holds only what pure judgment can state, and pending rows must
  # name their candidate.
  #
  # Layer vocabularies (.docs/core-layers-architecture.md, ratified):
  #   lect    identity / pending / dates / codemap        (P59-4 verbatim)
  #   dating  dated / partial / undatable / pending
  #   places  linked / named / unplaced / pending
  #   script  implied / qualified / mixed
  class Postures
    LAYERS = {
      "lect" => %w[identity pending dates codemap],
      "dating" => %w[dated partial undatable pending],
      "places" => %w[linked named unplaced pending],
      "script" => %w[implied qualified mixed]
    }.freeze

    Declaration = Data.define(:slug, :layer, :posture, :note)

    # nil when the file is absent (feature-module posture) — the suite
    # check then reports every non-machine source as unpostured. An
    # unknown layer key raises: a typo must never read as "no posture".
    # +path+ may be one file or an overlay pair (P71-0, owner-ruled
    # 2026-08-11): declarations merge per (slug, layer), later path wins.
    def self.load(path)
      paths = Array(path).select { |p| File.file?(p) }
      return nil if paths.empty?

      merged = paths.each_with_object({}) do |file, by_key|
        raw = YAML.safe_load_file(file) || {}
        (raw["sources"] || {}).each do |slug, layers|
          (layers || {}).each do |layer, entry|
            unless LAYERS.key?(layer)
              raise Nabu::Error, "postures.yml: #{slug}: unknown layer #{layer.inspect} " \
                                 "(ruled layers: #{LAYERS.keys.join('/')})"
            end

            by_key[[slug, layer]] =
              Declaration.new(slug: slug, layer: layer, posture: entry.fetch("posture"), note: entry["note"])
          end
        end
      end
      new(declarations: merged.values)
    end

    def initialize(declarations:)
      @declarations = declarations
    end

    attr_reader :declarations

    def declared(slug, layer:)
      declarations.find { |declaration| declaration.slug == slug && declaration.layer == layer }
    end

    # {slug => posture label} for one layer, declarations only — the
    # machine-grain merge is lect-specific (#lect_coverage).
    def layer_coverage(layer)
      declarations.select { |declaration| declaration.layer == layer }
                  .to_h { |declaration| [declaration.slug, declaration.posture] }
    end

    # The lect layer's {slug => posture label}, machine grains first (they
    # win — a declared duplicate of a machine posture is a validation
    # error, not a merge): "rules:<ids>" / "override" from the config
    # files, then this file's declared posture verbatim. (P59-4 contract,
    # carried through the P61-0 consolidation unchanged.)
    def lect_coverage(rules:, overrides:)
      map = layer_coverage("lect")
      (overrides || {}).each_key { |slug| map[slug] = "override" }
      (rules&.rules || []).each do |rule|
        rule.sources.each do |slug|
          map[slug] = map[slug]&.start_with?("rules:") ? "#{map[slug]}+#{rule.id}" : "rules:#{rule.id}"
        end
      end
      map
    end

    # Declared LECT slugs that are ALSO machine-postured — always a
    # mistake (the declaration would shadow or duplicate the config truth).
    def shadowing(rules:, overrides:)
      machine = (overrides || {}).keys + (rules&.rules || []).flat_map(&:sources)
      declarations.select { |declaration| declaration.layer == "lect" }.map(&:slug) & machine
    end
  end
end
