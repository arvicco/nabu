# frozen_string_literal: true

require "did_you_mean"

module Nabu
  # The registry-aware half of the focus profile (P40-f). Nabu::Profile owns
  # the file; Focus turns its stored entry list into a working scope against a
  # SourceRegistry:
  #
  # - RESOLUTION: split every stored name into the axes it matches, the source
  #   slugs it matches, and the unknowns (registry drift after a hand-edit);
  #   the focused source set is (members of every focused axis) ∪ (named
  #   sources), de-duplicated. Axis names can never equal slugs (the registry's
  #   load-time collision guarantee), so the split is unambiguous.
  #
  # - THE VIEW: a filtered registry the read surfaces render instead of the
  #   full one. A source shows only when focused; a SHELF (kind: shelf — the
  #   owner's own) ALWAYS shows; a MODULE shows only under --all. An empty
  #   profile (or --all) is the pass-through: the full registry, current
  #   behavior everywhere.
  #
  # - WRITE VALIDATION: `focus only/add` refuse an unknown name loudly, naming
  #   near-misses; drop/clear never validate (removing a name the registry no
  #   longer knows is exactly how you clean up drift).
  #
  # - HONESTY LINES: the meta lines the scoped surfaces print (to stderr, so
  #   piped stdout stays byte-identical to the unfocused output).
  module Focus
    module_function

    # The resolution of a profile against a registry: the entries that matched
    # an axis, those that matched a source slug, the leftovers (drift), and the
    # de-duplicated focused source set the axes+sources expand to.
    Resolution = Data.define(:axes, :sources, :unknown, :slugs)

    # A working scope over +registry+: the (possibly filtered) registry the
    # surface renders, the full one for hidden-count math, and the resolution.
    View = Data.define(:registry, :full_registry, :resolution, :profile, :all) do
      # A profile is APPLIED (rows actually filtered) only when it is non-empty
      # and --all was not passed. Empty or --all is the pass-through.
      def active? = !profile.empty? && !all

      def entries = profile.entries

      def unknown = resolution.unknown

      # Is +slug+ visible under this view? Everything is visible in the
      # pass-through (so an orphan catalog slug never vanishes); when active,
      # visibility is exactly membership in the filtered registry.
      def visible?(slug)
        return true unless active?

        !registry[slug].nil?
      end

      # Registry rows hidden by the filter (sources + modules --all reveals).
      def registry_hidden = full_registry.size - registry.size
    end

    # Split +profile+'s entries against +registry+ and expand to the focused
    # source set. An entry is an axis if the registry defines that axis, else a
    # source if the registry registers that slug, else unknown.
    def resolve(profile, registry)
      known_axes = registry.axes.names
      known_slugs = registry.slugs
      axes = []
      sources = []
      unknown = []
      profile.entries.each do |name|
        if known_axes.include?(name) then axes << name
        elsif known_slugs.include?(name) then sources << name
        else unknown << name
        end
      end
      slugs = (axes.flat_map { |name| registry.axis_members(name) } + sources).uniq
      Resolution.new(axes: axes, sources: sources, unknown: unknown, slugs: slugs)
    end

    # Build the View for +registry+ under +profile+ and the --all flag. When
    # the profile is applied, the filtered registry keeps every shelf plus the
    # focused sources (modules and unfocused sources drop out), in registration
    # order, carrying the same axes definitions so --axis grouping still works.
    def view(profile:, registry:, all:)
      resolution = resolve(profile, registry)
      applied = !profile.empty? && !all
      filtered =
        if applied
          # A shelf ALWAYS shows; a module NEVER shows here (only under --all,
          # the pass-through branch), even when tagged to a focused axis; a
          # source shows iff it is in the focused set.
          visible = registry.each_source.select do |entry|
            next true if entry.shelf?
            next false if entry.feature_module?

            resolution.slugs.include?(entry.slug)
          end
          SourceRegistry.new(visible, axes: registry.axes)
        else
          registry
        end
      View.new(registry: filtered, full_registry: registry, resolution: resolution, profile: profile, all: all)
    end

    # -- write validation -----------------------------------------------------

    # Raised by validate_names! when a WRITE (only/add) is handed a name that
    # is neither a known axis nor a known source slug.
    class UnknownName < Nabu::Error; end

    # Validate the names of a WRITE against the registry. Returns them
    # unchanged when every one is a known axis or slug; otherwise raises
    # UnknownName naming the first offender and its near-misses (or the whole
    # known set when nothing is close), so a fat-fingered `focus only germnic`
    # fails loudly instead of silently focusing on nothing.
    def validate_names!(names, registry)
      known = registry.axes.names + registry.slugs
      bad = names.find { |name| !known.include?(name) }
      return names if bad.nil?

      raise UnknownName, "unknown name #{bad.inspect} — #{suggestion(bad, known)}"
    end

    # The "did you mean …" clause for an unknown name: near-misses when the
    # spell-checker finds any, else the full known set (small registries).
    def suggestion(name, known)
      near = DidYouMean::SpellChecker.new(dictionary: known).correct(name)
      return "did you mean #{near.join(', ')}?" unless near.empty?

      "known axes/sources: #{known.sort.join(', ')}"
    end

    # -- honesty lines (stderr meta) -----------------------------------------

    # Shown after an UNFOCUSED table (no profile): the one-line nudge toward
    # focusing. Verbatim owner phrasing.
    def hint_line
      "nabu focus only <axes…> trims this to your desks"
    end

    # Shown after a FOCUSED table: what is in focus and the exact count of rows
    # --all would reveal (the P35 exact-count honesty rule). The hidden clause
    # is zero-suppressed — nothing to reveal, nothing said.
    def footer_line(entries, hidden)
      head = "focused on #{entries.join(', ')}"
      return head unless hidden.positive?

      "#{head} — #{hidden} #{hidden == 1 ? 'source' : 'sources'} hidden (--all shows them)"
    end

    # The registry-drift warning: names in the file that match nothing now.
    # Warned once and ignored, never fatal.
    def drift_line(unknown)
      "focus: ignoring #{unknown.join(', ')} — not a known axis or source " \
        "(registry drift; `nabu focus drop` to remove)"
    end
  end
end
