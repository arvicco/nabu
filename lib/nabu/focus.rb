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
      # The enablement filter is APPLIED whenever --all was NOT passed (P44-r3b:
      # the profile is now the box's ENABLED set, so it governs the default view
      # even when empty — an empty enabled set shows only the owner's shelves,
      # not the whole registry). --all is the pass-through: the full registry,
      # with blocked sources marked at the render.
      def active? = !all

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
      # An AXIS expands to its PUBLIC members only (P44-r3b): a blocked
      # (grant-gated private) source is never enabled implicitly by its desk —
      # it joins the set only when named explicitly by slug (which the +sources+
      # arm carries, blocked or not).
      # Shelves are implicitly ALWAYS in the enabled set (owner ruling
      # 2026-07-24): the owner's own canonical memory never needs enabling,
      # so no footer/hint ever claims a shelf is "not enabled".
      shelf_slugs = registry.each_source.select(&:shelf?).map(&:slug)
      slugs = (axes.flat_map { |name| registry.public_axis_members(name) } + sources + shelf_slugs).uniq
      Resolution.new(axes: axes, sources: sources, unknown: unknown, slugs: slugs)
    end

    # Build the View for +registry+ under +profile+ and the --all flag. When
    # the profile is applied, the filtered registry keeps every shelf (always
    # enabled) plus the enabled sources AND modules, in registration order,
    # carrying the same axes definitions so --axis grouping still works.
    def view(profile:, registry:, all:)
      resolution = resolve(profile, registry)
      applied = !all
      filtered =
        if applied
          # A shelf ALWAYS shows (implicitly always enabled — owner ruling
          # 2026-07-24: your own shelves never need enabling); every other
          # row — feature modules INCLUDED — shows iff enabled. The P40-f
          # focus-era "a module never shows outside --all" rule died with
          # the enablement promotion: under enablement semantics it read as
          # "modules disabled" (owner report), and a module enabled via its
          # desk or slug is as enabled as any source.
          visible = registry.each_source.select do |entry|
            next true if entry.shelf?

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

    # The empty-state line (P44-r3b): shown after a default view whose ENABLED
    # set resolves to zero sources (a fresh box, or an owner who disabled
    # everything). The owner's shelves still show; there is just nothing enabled
    # to acquire or list, so this names the on-ramp.
    def empty_state_line
      "no sources enabled — nabu enable <axis|source> (nabu quickstart for a starter set)"
    end

    # Shown after a default (enabled) table. The ROWS ARE the enabled set
    # (P44-r3b), so re-naming them here was pure duplication (owner report
    # 2026-07-24: "why are they listed TWICE?") — a focus-era leftover from
    # when the footer named the trim over an everything-table. Now a count
    # summary: how many enabled, how many --all would reveal (the P35
    # exact-count honesty rule; hidden clause zero-suppressed), and the
    # grow-the-set on-ramp.
    def footer_line(entries, hidden)
      head = "enabled: #{entries.size} #{entries.size == 1 ? 'entry' : 'entries'}"
      tail = " (nabu enable <axis|source> to add)"
      return head + tail unless hidden.positive?

      "#{head} — #{hidden} #{hidden == 1 ? 'source' : 'sources'} not enabled (--all shows them)"
    end

    # The registry-drift warning: names in the file that match nothing now.
    # Warned once and ignored, never fatal.
    def drift_line(unknown)
      "enablement: ignoring #{unknown.join(', ')} — not a known axis or source " \
        "(registry drift; `nabu disable` to remove)"
    end
  end
end
