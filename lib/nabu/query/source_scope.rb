# frozen_string_literal: true

require_relative "../errors"
require_relative "../source_registry"

module Nabu
  module Query
    # The --source / --axis scoping pair, resolved ONCE for every surface
    # that offers it: the CLI search family and export, and the MCP
    # nabu_search tool. The query classes take the result as their
    # +source:+ (one slug) and +sources:+ (an axis's member slugs) filters.
    #
    # - +source+ is validated against the CATALOG — what is held is what
    #   can be filtered; an unknown slug is refused naming the held set
    #   (the define-miss pattern), never answered with an empty page.
    # - +axis+ is a comma-joined list of research axes (config/axes.yml) or
    #   functional sets (SourceRegistry::FUNCTIONAL_SETS), resolved to the
    #   union of their member slugs; an unknown name is refused naming the
    #   known set, an axis-less registry says so. The slug/axis collision
    #   guarantee (SourceRegistry.load) makes a bare name unambiguous.
    #
    # Callers translate Error into their own surface's refusal (Thor::Error
    # on the CLI, the isError tool result on MCP).
    module SourceScope
      class Error < Nabu::Error; end

      module_function

      # nil when +slug+ is nil or held; raises Error otherwise.
      def validate_source!(catalog, slug)
        return nil if slug.nil?
        return nil if catalog[:sources].where(slug: slug).any?

        known = catalog[:sources].order(:slug).select_map(:slug)
        raise Error, "unknown source #{slug.inspect} — the catalog holds: #{known.join(', ')}"
      end

      # [axis names in the order asked, member slugs] for a non-blank
      # +spec+, nil for a blank one. +command+ prefixes the refusals.
      def axis_membership(registry, spec, command:)
        spec = spec.to_s.strip
        return nil if spec.empty?

        axes = registry.axes
        raise Error, "#{command}: no research axes are defined (config/axes.yml)" if axes.empty?

        names = spec.split(",").map(&:strip).reject(&:empty?).uniq
        names.each do |name|
          next if registry.functional_set?(name) || axes[name]

          raise Error, "#{command}: unknown axis #{name.inspect} — known axes: #{axes.names.join(', ')} · " \
                       "functional sets: #{SourceRegistry::FUNCTIONAL_SETS.join(', ')}"
        end
        slugs = names.flat_map do |name|
          registry.functional_set?(name) ? registry.functional_set_members(name) : registry.axis_members(name)
        end
        [names, slugs.uniq]
      end
    end
  end
end
