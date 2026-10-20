# frozen_string_literal: true

# Nabu::CLI — shared passage-display helpers (display policy, gaiji lanes).
# Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    no_commands do
      # -- display policy (P27-0) ------------------------------------------
      # Passage text reaches the terminal ONLY through display_text, which
      # applies the per-language display.yml policy under the --display mode
      # and records what changed; print_display_footer then hints ONCE per
      # invocation — never silent alteration, never a hint when nothing
      # happened. MCP and export never touch this path: pristine text.

      # Resolve --display MODE against the registry; validate before any
      # output so an unknown mode is a clean named error.
      def display_mode
        @display_mode ||= Nabu::Display.mode(options[:display] || Nabu::Display::DEFAULT_MODE)
      rescue Nabu::Display::UnknownModeError => e
        raise Thor::Error, e.message
      end

      def display_policies
        @display_policies ||= Nabu::Display.load_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      def display_source_policies
        @display_source_policies ||= Nabu::Display.load_source_policies(Nabu::Config.load.display_path)
      rescue Nabu::Display::ConfigError => e
        raise Thor::Error, e.message
      end

      # Render one run of text for the terminal and remember which transforms
      # actually applied (for the footer hint). +source+/+annotations+
      # (P27-1) are the optional edition context — call sites that know the
      # passage's source (the show family) pass them so `--display reading`
      # can apply the per-source convention rules and the ketiv/qere choice;
      # everywhere else the language-level policies alone apply.
      def display_text(text, language, source: nil, annotations: nil)
        @display_gaiji_ladder = true if source && display_source_policies[source]&.gaiji == "ladder"
        rendered = Nabu::Display.render(text.to_s, language: language,
                                                   mode: display_mode, policies: display_policies,
                                                   source: source, annotations: annotations,
                                                   source_policies: display_source_policies,
                                                   gaiji_map: gaiji_map_for(source),
                                                   gaiji_ids: gaiji_ids_for(source),
                                                   gaiji_substitutes: gaiji_substitutes_for(source))
        display_applied.merge(rendered.applied)
        record_gaiji(rendered.gaiji)
        rendered.text
      end

      def display_applied
        @display_applied ||= Set.new
      end

      # The source's three gaiji ladder lanes (P37-3/P38-2), each memoized per
      # source: config/gaiji/<source>.tsv (faithful), <source>-ids.tsv (IDS)
      # and <source>-substitutes.tsv (substitutes) — only kanripo ships them
      # today. A missing file is an empty map (that rung degrades to the next),
      # and the non-show call sites (no source) never load a map at all.
      def gaiji_map_for(source) = gaiji_lane(source, "")

      def gaiji_ids_for(source) = gaiji_lane(source, "-ids")

      def gaiji_substitutes_for(source) = gaiji_lane(source, "-substitutes")

      def gaiji_lane(source, suffix)
        return {} unless source

        (@gaiji_lanes ||= {})[[source, suffix]] ||=
          Nabu::Display.load_gaiji_map(File.join(Nabu::Config.load.gaiji_dir, "#{source}#{suffix}.tsv"))
      end

      # Running per-rung gaiji tallies for the once-per-invocation footer
      # ([faithful, ids, substitute, placeholder], summed across every passage a
      # show-family command renders).
      def display_gaiji
        @display_gaiji ||= [0, 0, 0, 0]
      end

      def record_gaiji(tally)
        return unless tally

        display_gaiji[0] += tally.faithful
        display_gaiji[1] += tally.ids
        display_gaiji[2] += tally.substitute
        display_gaiji[3] += tally.placeholder
      end

      # The once-per-invocation honesty footer: named only when a transform
      # actually changed something (compact rule — zero-signal silence).
      #   display: cantillation stripped (--display full shows all marks)
      #   display: cantillation stripped · rtl isolates (--display full shows all marks)
      # One footer per invocation, composing every applied transform's
      # vocabulary (P27-0 strips · P27-1 edition · P27-2 translit/colors/
      # spacing); the escape hatch names diplomatic when edition transforms
      # applied, else full.
      def print_display_footer
        gaiji_text = gaiji_clause(*display_gaiji)
        return if display_applied.empty? && gaiji_text.nil?

        labels = display_applied.to_a
        edition = Nabu::Display::EDITION_LABELS & labels
        parts = []
        parts << "transliterated" if labels.delete("translit")
        colors = labels.select { |label| label.start_with?("token colors") }
        strips = labels - colors - edition - ["spacing", Nabu::Display::ISOLATES]
        parts << "#{strips.join(', ')} stripped" unless strips.empty?
        parts << "apparatus simplified: #{edition.join(', ')}" unless edition.empty?
        parts << gaiji_text if gaiji_text
        parts << "spacing" if labels.include?("spacing")
        parts.concat(colors)
        parts << Nabu::Display::ISOLATES if labels.include?(Nabu::Display::ISOLATES)
        say "display: #{parts.join(' · ')} (#{display_footer_hint(edition, !gaiji_text.nil?)})"
      end

      # The escape-hatch hint: diplomatic when any edition-level transform ran
      # (apparatus OR gaiji — both are "shown as stored" under diplomatic),
      # naming "refs" when gaiji is the only edition transform; else full.
      def display_footer_hint(edition, gaiji)
        return "--display diplomatic shows the edition marks" unless edition.empty?
        return "--display diplomatic shows the gaiji refs" if gaiji

        "--display full shows all marks"
      end

      # The gaiji footer clause, per rung. Returns nil when there is nothing to
      # announce. Two shapes, honest to the policy:
      #   ladder (P38-2)     — FAITHFUL is silent (it IS the character); the
      #                        lossy rungs (substitutes, IDS compositions) and
      #                        the ⬚ placeholders DO get announced ("never
      #                        silent"). An all-faithful render says nothing.
      #   placeholder (P37-3) — the preserved rungs-1+4 vocabulary: unresolved
      #                        (⬚) refs and how many resolved to a real glyph.
      def gaiji_clause(faithful, ids, substitute, placeholder)
        return ladder_gaiji_clause(ids, substitute, placeholder) if @display_gaiji_ladder

        placeholder_gaiji_clause(faithful, placeholder)
      end

      def ladder_gaiji_clause(ids, substitute, placeholder)
        bits = []
        bits << "#{substitute} substituted" if substitute.positive?
        bits << "#{ids} composed" if ids.positive?
        bits << "#{placeholder} unresolved gaiji" if placeholder.positive?
        bits.empty? ? nil : bits.join(", ")
      end

      def placeholder_gaiji_clause(resolved, unresolved)
        if unresolved.positive? && resolved.positive?
          "#{unresolved} unresolved gaiji (#{resolved} resolved)"
        elsif unresolved.positive?
          "#{unresolved} unresolved gaiji"
        elsif resolved.positive?
          "#{resolved} gaiji resolved"
        end
      end
    end
  end
end
