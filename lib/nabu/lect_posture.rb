# frozen_string_literal: true

require "yaml"

module Nabu
  # The per-source lect posture record (P59-4, D59-e): the judgment half of
  # "no adapter without lects". Machine-knowable postures live where the
  # machines already state them — a source named by a lect_facet_rules.yml
  # rule or a lect_overrides.yml row IS postured by that file (single
  # source of truth) — so config/lect_posture.yml declares only what pure
  # judgment can: identity (ruled: no refinement available), pending (a
  # named candidate, not yet ruled), dates (per-document inference rides;
  # source grain bare by design), codemap (the universal map refines it).
  #
  # #coverage merges the three grains into {slug => posture label}; the
  # suite requires every passage-serving registry source to appear —
  # a missing slug is the loud absence D59-e demands.
  class LectPosture
    DECLARED_POSTURES = %w[identity pending dates codemap].freeze

    Declaration = Data.define(:slug, :posture, :note)

    # nil when the file is absent (feature-module posture) — the suite
    # check then reports every non-machine source as unpostured.
    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      declarations = (raw["sources"] || {}).map do |slug, entry|
        Declaration.new(slug: slug, posture: entry.fetch("posture"), note: entry["note"])
      end
      new(declarations: declarations)
    end

    def initialize(declarations:)
      @declarations = declarations
    end

    attr_reader :declarations

    def declared(slug)
      declarations.find { |declaration| declaration.slug == slug }
    end

    # {slug => posture label}, machine grains first (they win — a declared
    # duplicate of a machine posture is a validation error, not a merge):
    # "rules:<ids>" / "override" from the config files, then this file's
    # declared posture verbatim.
    def coverage(rules:, overrides:)
      map = {}
      declarations.each { |declaration| map[declaration.slug] = declaration.posture }
      (overrides || {}).each_key { |slug| map[slug] = "override" }
      (rules&.rules || []).each do |rule|
        rule.sources.each do |slug|
          map[slug] = map[slug]&.start_with?("rules:") ? "#{map[slug]}+#{rule.id}" : "rules:#{rule.id}"
        end
      end
      map
    end

    # Declared slugs that are ALSO machine-postured — always a mistake
    # (the declaration would shadow or duplicate the config truth).
    def shadowing(rules:, overrides:)
      machine = (overrides || {}).keys + (rules&.rules || []).flat_map(&:sources)
      declarations.map(&:slug) & machine
    end
  end
end
