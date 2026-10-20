# frozen_string_literal: true

# Nabu::CLI — box profile commands: enable, disable, focus. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    # The one pointer line every deprecated `focus` alias prints (P44-r3b).
    FOCUS_POINTER = "focus is now enable/disable; this alias will be removed in a future release"

    desc "enable AXIS|SOURCE...|all", "Enable sources or axes on this box — `all` is every ungated source in one move"
    long_desc <<~HELP, wrap: false
      Add axes and/or sources to config/profile.yml — this box's ENABLEMENT
      CONFIG (P44-r3b). The entries govern BOTH what `nabu sync` / `sync --all`
      acquires AND the default row set of `nabu list` / `status` / `health` and
      the MCP nabu_status sources array. `nabu search` / `show` / `export` stay
      library-wide (enablement scopes acquisition + visibility, never reading).

      A GROUP name (core · signs) expands to the group's SOURCE members —
      its modules are machinery, pre-enabled by nature, and never enter the
      profile. `nabu enable signs && nabu sync signs` restores the whole
      sign/char capability on a fresh box.

      enable is ADDITIVE: it APPENDS (never trims). An AXIS is recorded by name
      (it expands to the axis's PUBLIC members); a SOURCE by slug. Enabling an
      axis never implicitly enables its grant-gated (blocked) members — each is
      skipped with the on-ramp line, so a private research source is only ever
      enabled by naming it. Enabling a blocked source BY SLUG runs its grant
      terms and demands a typed `granted` (or --grant-acknowledged) once,
      recorded in the ledger; a later enable skips the prompt.

      Examples:
        nabu enable germanic          # the germanic desk's public sources
        nabu enable sblgnt proiel     # two sources by slug
        nabu enable titus-avestan     # a grant-gated source: shows terms, asks
    HELP
    option :grant_acknowledged, type: :boolean, default: false,
                                desc: "Acknowledge a grant-gated source's terms non-interactively " \
                                      "(scripted use); records the acknowledgment, then enables."
    def enable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "enable: name at least one axis, source, or group to enable" if names.empty?

      # `enable all` (owner feature, 2026-10-13): the fast path to a whole
      # library — every source the box can sync unattended, in one move.
      # Access-gated rows (blocked availability, grant-gated, credential-
      # bound) are deliberately skipped with their reasons: each of those
      # must be enabled BY NAME so its own grant/credential flow runs.
      if names.include?("all")
        raise Thor::Error, "enable all: stands alone (it already covers every ungated source)" if names.size > 1

        rows = registry.slugs.map { |slug| registry[slug] }.reject(&:feature_module?)
        gated, open_rows = rows.partition { |e| e.blocked? || e.grant_required? || e.credentials }
        unless gated.empty?
          say "skipped as access-gated (enable each by name to run its grant or credential flow):"
          gated.each do |e|
            reasons = [e.blocked? ? "blocked" : nil, e.grant_required? ? "grant-gated" : nil,
                       e.credentials ? "credentials: #{e.credentials}" : nil].compact
            say "  #{e.slug} (#{reasons.join(', ')})"
          end
        end
        names = open_rows.map(&:slug)
        say "enable all → #{names.size} ungated sources"
      end

      # P68-4: a GROUP name expands to its source members (modules are
      # machinery — pre-enabled by nature, never profile entries), so
      # `nabu enable signs && nabu sync signs` is the whole restore dance.
      names = names.flat_map do |name|
        next name unless Nabu::SourceRegistry::GROUPS.include?(name)

        members = registry.group_members(name)
        sources = members.reject { |slug| registry[slug].feature_module? }
        modules = members - sources
        say "#{name} group → enabling #{sources.join(', ')}"
        say "  (#{modules.join(', ')}: modules — pre-enabled by nature)" unless modules.empty?
        sources
      end

      Nabu::Focus.validate_names!(names, registry)
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      run_enable(config, registry, names, ledger: ledger, catalog: catalog)
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "enable: #{e.message}"
    rescue Nabu::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    desc "disable AXIS|SOURCE...", "Disable sources or axes on this box (synced data stays)"
    long_desc <<~HELP, wrap: false
      Remove axes and/or sources from config/profile.yml (the enablement
      config). The synced data STAYS on disk — disabling only drops the entries
      from the enabled set, so `sync`/`list`/`status` stop touching/showing them
      by default (--all still reveals them). Withdrawal of data is a different,
      existing concept. Removing a name the registry no longer knows (drift
      after a hand-edit) is fine — disable never validates, so it also cleans up.

      Examples:
        nabu disable germanic
        nabu disable proiel
    HELP
    def disable(*names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      raise Thor::Error, "disable: name at least one axis or source to disable" if names.empty?

      catalog = open_catalog(config)
      run_disable(config, registry, names, catalog: catalog)
    ensure
      catalog&.disconnect
    end

    desc "focus [only|add|drop|clear] [NAMES…]",
         "DEPRECATED — alias for enable/disable (will be removed in a future release)"
    long_desc <<~HELP, wrap: false
      DEPRECATED (P44-r3b): the focus profile was promoted to the local
      enablement config, and the verbs moved to `nabu enable` / `nabu disable`.
      Each focus subcommand still works for one release as an alias, printing a
      pointer to its replacement:

        nabu focus only <names…>  →  clear, then nabu enable <names…>
        nabu focus add  <names…>  →  nabu enable  <names…>
        nabu focus drop <names…>  →  nabu disable <names…>
        nabu focus clear          →  enable nothing (empty enabled set)
        nabu focus                →  show the current enabled set
    HELP
    def focus(action = nil, *names)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      names = names.map(&:strip).reject(&:empty?)
      say FOCUS_POINTER
      ledger = open_or_create_ledger(config)
      catalog = open_catalog(config) # read-only: only the migration detector needs it
      case action.to_s.strip
      when "" then show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      when "only"
        Nabu::Focus.validate_names!(names, registry)
        Nabu::Profile.new([]).save(config.profile_path) # clear first (only = clear + enable)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "add"
        Nabu::Focus.validate_names!(names, registry)
        run_enable(config, registry, names, ledger: ledger, catalog: catalog)
      when "drop" then run_disable(config, registry, names, catalog: catalog)
      when "clear"
        Nabu::Profile.new([]).save(config.profile_path)
        say "cleared — no sources enabled (nabu enable <axis|source> to add)"
      else
        raise Thor::Error, "focus: unknown action #{action.inspect} — use only, add, drop, clear " \
                           "(or the new nabu enable/disable)"
      end
    rescue Nabu::Focus::UnknownName => e
      raise Thor::Error, "focus: #{e.message}"
    ensure
      catalog&.disconnect
      ledger&.disconnect
    end

    no_commands do
      # -- the local enablement config (P44-r3b, promoted from P40-f focus) --

      # The EFFECTIVE enablement profile for +config+ against +registry+. The
      # promotion's default inversion (P44-r3b): an ABSENT config no longer
      # means "everything". Three cases:
      #   file EXISTS         → its entries are the enabled set, as-is.
      #   absent + a library  → MIGRATION: write every registry source present
      #                         in the catalog out once, announced (no silent
      #                         visibility loss of a built library). Needs the
      #                         catalog to detect it, so surfaces without one
      #                         (remote health) pass catalog: nil and defer.
      #   absent + fresh box  → the quickstart starter set (empty until r3c
      #                         seeds the tags → the honest empty-state).
      def effective_profile(config, registry, catalog: nil)
        path = config.profile_path
        if Nabu::Profile.exist?(path)
          profile = Nabu::Profile.load(path)
          # An EMPTY pre-promotion (P40-f focus-era) file means "no focus
          # trim", never "nothing enabled" — it migrates exactly like an
          # absent file (announced, once). Only an empty file SAVED UNDER
          # THE ENABLEMENT HEADER governs as deliberately-empty (a
          # disable-everything is re-saved with the new header, so it
          # never re-migrates). Files with entries govern as-is either way.
          return profile unless profile.empty? && !Nabu::Profile.enablement_header?(path)
        end

        migrated = migrate_profile(config, registry, catalog)
        return migrated if migrated

        Nabu::Profile.new(Nabu::Profile.default_entries(registry))
      end

      # The one-time migration (P44-r3b): if the box already built a library
      # (the catalog carries source rows) but has no enablement config yet,
      # write one enabling every registry source present in the catalog, so the
      # promotion never drops visibility of what the owner already synced.
      # Returns the saved profile, or nil when there is nothing to migrate.
      def migrate_profile(config, registry, catalog)
        return nil unless catalog&.table_exists?(:sources)

        present = catalog[:sources].select_map(:slug) & registry.slugs
        return nil if present.empty?

        profile = Nabu::Profile.new(present).save(config.profile_path)
        warn "enablement: wrote config/profile.yml enabling your #{pluralize(present.size, 'synced source')} " \
             "(the profile is now this box's enabled set — nabu enable/disable to adjust)."
        profile
      end

      # The working scope for a read surface: the effective enablement resolved
      # against the registry, honoring --all. The filtered registry it carries
      # is what status/list/health render instead of the full one. +catalog+
      # feeds the migration detector (nil where a surface has none open yet).
      def focus_view(config, registry, catalog: nil)
        Nabu::Focus.view(
          profile: effective_profile(config, registry, catalog: catalog),
          registry: registry, all: options[:all], disabled: options[:disabled] || false
        )
      end

      # The box's effective enabled set: the stored profile resolved
      # against the registry (modules pre-enabled by nature); no profile
      # file = the fresh-box default entries.
      def enabled_slugs(profile, registry)
        profile ||= Nabu::Profile.new(Nabu::Profile.default_entries(registry))
        view = Nabu::Focus.view(profile: profile, registry: registry, all: false)
        registry.slugs.select { |slug| view.visible?(slug) }.to_set
      end

      # The enablement META lines go to STDERR, never stdout: piped output stays
      # byte-identical to the table, while the terminal user still sees context.
      # A default view names the enabled set + the exact hidden count, or the
      # honest empty-state when nothing is enabled; --all (the full reveal) is
      # silent.
      def print_focus_note(view, hidden_slugs)
        # The --disabled complement (P46-r3): the rows shown ARE the enable
        # menu, so the footer is the on-ramp (or the all-enabled state) —
        # never the enabled-set summary, never the empty-state.
        return warn(Nabu::Focus.disabled_footer_line(view.registry.slugs)) if view.disabled
        return unless view.active?

        if view.resolution.slugs.empty?
          warn Nabu::Focus.empty_state_line
        else
          warn Nabu::Focus.footer_line(view.entries, hidden_slugs, resolved_count: view.resolution.slugs.size)
        end
      end

      # Warn once about names the file carries that the registry no longer
      # knows (drift after a hand-edit): ignored, never fatal.
      def warn_focus_drift(view)
        warn Nabu::Focus.drift_line(view.unknown) unless view.unknown.empty?
      end

      # `nabu enable <axis|source…>`: additive. Validate the names, migrate an
      # absent-but-built profile first (no visibility loss), then append —
      # recording the AXIS NAME (the existing profile vocabulary; Focus expands
      # it to its PUBLIC members, blocked ones skipped) or the source slug. A
      # blocked (grant-gated private) source named BY SLUG runs the P42-r1 grant
      # flow here, at the natural consent moment; enabling an AXIS never drags a
      # blocked member in — each is skipped with the on-ramp line.
      def run_enable(config, registry, names, ledger:, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        entries = profile.entries.dup
        added = []
        names.each do |name|
          if registry.axes[name]
            note_blocked_axis_members(registry, name)
          else
            enable_source!(registry[name], ledger) # raises (adds nothing) on a refused grant
          end
          added << name unless entries.include?(name)
        end
        Nabu::Profile.new(entries + added).save(config.profile_path)
        announce_enablement(config, registry, verb: "enabled", changed: added, catalog: catalog)
      end

      # One source being enabled by slug: a grant-gated (blocked) source with a
      # grant block runs the P42-r1 acknowledgment before it joins the enabled
      # set — a refusal raises (and the caller adds nothing).
      def enable_source!(entry, ledger)
        return unless entry.blocked? && entry.grant_required?

        enable_grant!(entry, ledger)
      end

      # Print the on-ramp line for every blocked (grant-gated) member an axis
      # would otherwise drag in — enabling an axis never implicitly enables its
      # private members (P44-r3b).
      def note_blocked_axis_members(registry, axis_name)
        registry.blocked_axis_members(axis_name).each do |slug|
          say "#{slug} is grant-gated — enable it explicitly: nabu enable #{slug}", :yellow
        end
      end

      # The P42-r1 grant flow AT ENABLE TIME: a recorded acknowledgment skips
      # the prompt with an honest one-liner; --grant-acknowledged records
      # non-interactively; otherwise show the terms and demand the typed word
      # (no TTY / refusal aborts with the request scaffold, adding nothing).
      def enable_grant!(entry, ledger)
        gate = Nabu::GrantGate.new(ledger: ledger, grants_path: Nabu::Config.load.grants_path)
        return say("#{entry.slug}: grant already acknowledged — enabling.", :yellow) if gate.acknowledged?(entry.slug)

        if options[:grant_acknowledged]
          gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "flag")
          return say("#{entry.slug}: grant acknowledged (--grant-acknowledged) — recorded, enabling.", :yellow)
        end
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless $stdin.tty?

        say Nabu::GrantGate.notice(entry), :yellow
        say Nabu::GrantGate.prompt_line(entry)
        answer = $stdin.gets
        raise Thor::Error, Nabu::GrantGate.abort_message(entry) unless Nabu::GrantGate.acknowledged_answer?(answer)

        gate.record!(slug: entry.slug, terms: entry.grant.terms, how: "typed")
        say "#{entry.slug}: grant acknowledged — recorded, enabling.", :green
      end

      # `nabu disable <axis|source…>`: remove entries from the config (synced
      # data stays — withdrawal is a different, existing concept). Removes any
      # entry that matches a name given, whether it is an axis name or a slug.
      def run_disable(config, registry, names, catalog:)
        profile = effective_profile(config, registry, catalog: catalog)
        removed = profile.entries & names
        Nabu::Profile.new(profile.entries - names).save(config.profile_path)
        announce_enablement(config, registry, verb: "disabled", changed: removed, catalog: catalog)
        warn_still_required(config, registry, names, catalog: catalog)
      end

      # P77-r4 (the survey's disable finding): a disabled name the closure
      # re-adds must SAY so — "disabled" while it stays enabled is a lie.
      def warn_still_required(config, registry, names, catalog:)
        resolution = Nabu::Focus.resolve(effective_profile(config, registry, catalog: catalog), registry)
        names.select { |name| resolution.slugs.include?(name) }.each do |name|
          dependents = registry.required_by(name) & resolution.slugs
          next if dependents.empty?

          warn "#{name} stays enabled — required by #{dependents.join(', ')} " \
               "(disable the dependent to drop it)"
        end
      end

      # Confirm a write: what changed, then the current enabled set.
      def announce_enablement(config, registry, verb:, changed:, catalog:)
        say(changed.empty? ? "nothing #{verb} (already so)" : "#{verb}: #{changed.sort.join(', ')}")
        show_enablement(effective_profile(config, registry, catalog: catalog), registry)
      end

      # The current enabled set, grouped by PROVENANCE (P77-r2, owner report
      # 2026-08-13): core first (the auto-enabled default — shown even when
      # no profile entry names it), then each profile axis entry with the
      # members it pulls in, then the individually enabled remainder. Every
      # source is listed ONCE, under the first provenance that covers it,
      # and the headline count is the DEDUPED UNION of all of them — never
      # the raw entry count alone (a single axis entry covers many sources).
      def show_enablement(profile, registry)
        resolution = Nabu::Focus.resolve(profile, registry)
        return say(Nabu::Focus.empty_state_line) if resolution.slugs.empty?

        groups = enablement_groups(registry, resolution)
        entries = profile.entries.size
        total = groups.sum { |_label, members| members.size }
        say "enabled (#{entries} #{entries == 1 ? 'entry' : 'entries'} → #{total} distinct sources):"
        groups.each { |label, members| say "  #{label}: #{members.join(', ')}" }
        unless resolution.unknown.empty?
          say "  unknown: #{resolution.unknown.join(', ')} (not a known axis or source — ignored)"
        end
        shown = resolution.slugs.count { |slug| !registry[slug]&.feature_module? }
        say "resolved: #{pluralize(shown, 'source')} enabled (nabu status shows them; --all shows everything)"
      end

      def enablement_groups(registry, resolution)
        groups = []
        shown = []
        core = registry.core_members
        unless core.empty?
          groups << ["core (enabled by default)", core.sort]
          shown += core
        end
        resolution.axes.each do |axis|
          members = (registry.axis_members(axis) - shown).sort
          groups << ["#{axis} (axis)", members] unless members.empty?
          shown += members
        end
        individual = (resolution.sources - shown).sort
        groups << ["sources", individual] unless individual.empty?
        shown += individual
        # The chain-pulled remainder (P77-r3): slugs in the resolution only
        # because something above requires them, each named with its
        # dependents — the package-manager provenance.
        required = (resolution.slugs - shown).reject { |slug| registry[slug]&.shelf? }.sort
        unless required.empty?
          labeled = required.map do |slug|
            "#{slug} (by #{(registry.required_by(slug) & resolution.slugs).join(', ')})"
          end
          groups << ["required", labeled]
        end
        groups
      end
    end
  end
end
