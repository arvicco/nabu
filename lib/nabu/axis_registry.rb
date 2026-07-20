# frozen_string_literal: true

require "yaml"

module Nabu
  # The research-axes definitions registry (P35-0, architecture §5;
  # config/axes.yml). An axis is a TAG, not a partition — the owner's desks
  # (The Classicist, The Papyrologist-Epigraphist, …) over the source list,
  # multi-membership deliberate (D35 rulings 2026-07-20: dual-tagging over
  # folding; membership is whole-source, no per-document axes in v1 — the
  # honest partial-fit note rides the axis desc, never a fake partition).
  #
  # Definitions live in their OWN file, NOT as a reserved top-level key in
  # sources.yml: the sources registry's contract is a pure slug => entry
  # mapping, and a magic `axes:` carve-out there would both complicate the
  # loader and make a source slug named "axes" silently impossible instead
  # of loudly colliding. Membership is the list-valued `axes:` key on each
  # source row (SourceRegistry), validated against these definitions at load
  # time. "Axis" here always means RESEARCH axis; the date/place axis of
  # architecture §14 is a different mechanism (renamed "timeline" per D35).
  class AxisRegistry
    # One definition. +persona+ is FIRST-CLASS RENDER DATA — the hat's
    # one-liner in the house voice (P35-1/2 surfaces print it verbatim);
    # +desc+ is the membership rationale incl. honest whole-source caveats;
    # +order+ is the file's own position — the ratified render order.
    Axis = Data.define(:name, :persona, :desc, :order)

    # Parse config/axes.yml at +path+. A missing or empty file is a valid,
    # empty registry (bootstrap/test mode — sources then need no axes).
    def self.load(path)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      unless data.is_a?(Hash)
        raise ValidationError, "axes registry must be a mapping of axis => definition, got #{data.class}"
      end

      new(data.each_with_index.map { |(name, config), order| build_axis(name, config, order) })
    end

    def self.build_axis(name, config, order)
      unless name.is_a?(String) && name.match?(Model::Validation::SLUG_SHAPE)
        raise ValidationError, "axis #{name.inspect}: name must be a lowercase slug ([a-z0-9_-])"
      end
      unless config.is_a?(Hash)
        raise ValidationError, "axis #{name.inspect}: definition must be a mapping, got #{config.class}"
      end

      Axis.new(name: name, persona: string!(name, config, "persona"),
               desc: string!(name, config, "desc"), order: order)
    end
    private_class_method :build_axis

    def self.string!(name, config, key)
      value = config.fetch(key, nil)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ValidationError, "axis #{name.inspect}: #{key} must be a non-empty string, got #{value.inspect}"
    end
    private_class_method :string!

    def initialize(axes)
      @axes = axes.to_h { |axis| [axis.name, axis] }
    end

    # Yield each Axis in ratified (file) order; returns an Enumerator without
    # a block.
    def each_axis(&block)
      return enum_for(:each_axis) { @axes.size } unless block

      @axes.each_value(&block)
      self
    end

    def [](name)
      @axes[name]
    end

    def names
      @axes.keys
    end

    def empty?
      @axes.empty?
    end

    def size
      @axes.size
    end
  end
end
