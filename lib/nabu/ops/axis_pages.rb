# frozen_string_literal: true

require "date"
require "yaml"

module Nabu
  module Ops
    # The per-axis site-page generator (P37-9, `rake site:axes`). Writes one
    # committed Jekyll page per research axis (site/axis/<name>.md, permalink
    # /axis/<name>/) plus the /axis/ index — the site rendition of
    # docs/axes.md. Every page is a PROJECTION of the live registry
    # (config/axes.yml + config/sources.yml) merged with a HAND-CURATED
    # fragments file (site/axis/_fragments.yml — recipes, display notes, the
    # desk's instruments) that this generator READS and NEVER writes.
    #
    # Two kinds of fact ride each page, with different honesty rules:
    #   * REGISTRY facts (persona, desc, member slug list) are pinned to the
    #     live registry by test/site/axis_pages_test.rb — a registry change
    #     with no page regeneration fails the gate (the docs/axes.md
    #     precedent, now over 18 files + the index).
    #   * HOLDINGS counts (documents/passages/entries) are read live from the
    #     catalog and stamped with an AS-OF DATE, so they stay honest between
    #     regenerations and are never pinned (they drift by design). A source
    #     with nothing synced says so.
    #
    # The catalog is opened READ-ONLY; a missing catalog is not an error (the
    # holdings cells read "not built in this checkout"), so the generator runs
    # in a fresh worktree and against a live, actively-written db alike.
    class AxisPages
      Result = Data.define(:path, :axis)

      WORD_NUMBERS = %w[zero one two three four five six seven eight nine ten eleven twelve
                        thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty].freeze

      def initialize(registry:, fragments_path:, output_dir:, catalog_path:, as_of: Date.today)
        @registry = registry
        @axes = registry.axes
        @fragments = load_fragments(fragments_path)
        @output_dir = output_dir
        @catalog_path = catalog_path
        @as_of = as_of
      end

      # Render and WRITE every page (18 axis pages + the /axis/ index). Returns
      # the list of Results in ratified order (index last).
      def generate!
        require "fileutils"
        FileUtils.mkdir_p(@output_dir)
        census = read_census
        results = @axes.each_axis.map do |axis|
          path = File.join(@output_dir, "#{axis.name}.md")
          File.write(path, render_axis(axis, census))
          Result.new(path: path, axis: axis.name)
        end
        index_path = File.join(@output_dir, "index.md")
        File.write(index_path, render_index)
        results + [Result.new(path: index_path, axis: nil)]
      end

      private

      # The curated fragments file: a mapping of axis name => { instruments,
      # recipes, display, blurb } plus a top-level `kinds:` slug => holds-label
      # override map. A missing file is a valid empty curation (the pages then
      # carry only the generic quartet and derived holds-kinds).
      def load_fragments(path)
        return {} unless File.exist?(path)

        data = YAML.safe_load_file(path) || {}
        raise ValidationError, "axis fragments must be a mapping, got #{data.class}" unless data.is_a?(Hash)

        data
      end

      def kinds_overrides
        @fragments.fetch("kinds", nil) || {}
      end

      def fragment(axis_name)
        @fragments.fetch(axis_name, nil) || {}
      end

      # Open the catalog READ-ONLY and take the content census (one row per
      # source), or nil when no catalog exists in this checkout. Tolerates the
      # live db's locks via the store's busy timeout.
      def read_census
        return nil unless File.exist?(@catalog_path)

        catalog = Nabu::Store.connect(@catalog_path, readonly: true)
        Nabu::Store.setup!(catalog)
        Nabu::Query::List.new(catalog: catalog).census.to_h { |row| [row.slug, row] }
      ensure
        catalog&.disconnect
      end

      # ---- page rendering -------------------------------------------------

      def render_axis(axis, census)
        members = @registry.axis_members(axis.name)
        <<~PAGE
          ---
          title: "#{axis.name.capitalize} — #{persona_lead(axis)}"
          permalink: /axis/#{axis.name}/
          description: >-
            #{description_line(axis)}
          ---

          > #{axis.persona}

          #{axis.desc}
          #{blurb_block(axis)}## The shelves

          #{shelves_intro(members)}

          #{shelves_table(members, census)}

          ## The desk's instruments

          #{instruments_block(axis)}

          ## Working the #{axis.name} desk

          The generic axis surfaces — every desk answers to these:

          ```
          nabu list --axis #{axis.name}          # the shelf census, this desk only
          nabu axis #{axis.name}                 # the desk card: members, holdings, gold coverage
          nabu search WORD --axis #{axis.name}   # a query scoped to this desk's shelves
          nabu sync #{axis.name}                 # sync the desk's enabled members
          ```
          #{recipes_block(axis)}
          #{display_block(axis)}---

          #{footer(axis)}
        PAGE
      end

      def render_index
        <<~PAGE
          ---
          title: Research axes
          permalink: /axis/
          description: >-
            The eighteen research desks of the Nabu library — tags over the
            source list, each a scholarly hat with its own shelves, instruments
            and commands.
          ---

          The library is one flat list of corpora (the shelf map is
          [The Library]({{ '/library/' | relative_url }}); the code-per-language
          table is [Languages]({{ '/languages/' | relative_url }})). This page is
          the other view of the same sources: the **research axes** — the owner's
          scholarly desks, each a hat a reader puts on to work one tradition.

          An axis is **not a folder**. It is a **tag** over the source list, and a
          source wears every tag it serves — the Vulgate sits at the Classicist's
          desk for its Latin and at the Biblical scholar's for its scripture; the
          UD treebanks answer to nine desks at once. Multi-membership is the point,
          not an accident to be tidied away. The full rationale, with the
          dual-tagging and whole-source-membership rulings, is
          [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).

          Each desk below leads with its **persona** — the hat's one-line
          self-description, printed verbatim by `nabu axis` — and links to its own
          page, where the member shelves, live holdings, instruments, CLI recipes
          and terminal setup live.

          ## The eighteen desks

          #{index_entries}

          ---

          The desk listing on this page is a projection of the live registry
          (`config/axes.yml`), regenerated with `rake site:axes` and pinned to the
          registry by the suite — it can never silently drift from the sources it
          documents.
        PAGE
      end

      def index_entries
        @axes.each_axis.map do |axis|
          <<~ENTRY.rstrip
            ### #{axis.name}

            > #{axis.persona}

            #{axis.desc}

            [Open the #{axis.name} desk]({{ '/axis/#{axis.name}/' | relative_url }})
          ENTRY
        end.join("\n\n")
      end

      # ---- fragment-driven blocks -----------------------------------------

      # "The Celticist — …" → "The Celticist" for the page title / description.
      def persona_lead(axis)
        axis.persona.split(/\s+[—–-]\s+/, 2).first.strip
      end

      def description_line(axis)
        "#{persona_lead(axis)}'s desk: its shelves, instruments, CLI recipes and terminal setup."
          .gsub(/\s+/, " ")
      end

      def blurb_block(axis)
        blurb = fragment(axis.name)["blurb"]
        blurb ? "\n#{blurb.strip}\n\n" : "\n"
      end

      def shelves_intro(members)
        "#{count_phrase(members.size)} Holdings are read live from the catalog and " \
          "dated; a shelf with nothing synced yet says so."
      end

      def shelves_table(members, census)
        header = "| Source | Holds | License | Status | Holdings " \
                 "<span title=\"read live from the catalog\">(as of #{as_of_human})</span> |\n" \
                 "|---|---|---|---|---|"
        rows = members.map { |slug| shelf_row(slug, census) }
        ([header] + rows).join("\n")
      end

      def shelf_row(slug, census)
        entry = @registry[slug]
        holds = holds_label(slug, entry)
        license = entry ? entry.manifest.license_class : "?"
        status = status_label(entry)
        holdings = holdings_cell(census, slug)
        "| `#{slug}` | #{holds} | #{license} | #{status} | #{holdings} |"
      end

      # The coarse content kind from the adapter (dictionary/passages/local
      # shelves), refined by a curated per-slug override (treebank,
      # feature-module, inscriptions…) where the coarse kind under-describes.
      # A kind: module row is machinery, never a peer corpus (P39-0): it reads
      # "feature module" so `content_kind :passages` never renders it as
      # "texts" (a curated override — e.g. bridging's "crosswalk module" — is
      # more specific and still wins).
      def holds_label(slug, entry)
        override = kinds_overrides[slug]
        return override if override
        return "corpus" unless entry
        return "feature module" if entry.feature_module?

        case entry.adapter_class.content_kind
        when :dictionary then "dictionary"
        when :language then "language dossiers"
        when :notes then "owner notes"
        when :source then "source records"
        else "texts"
        end
      end

      def status_label(entry)
        return "unknown" unless entry

        entry.enabled ? "enabled · #{entry.sync_policy}" : "not enabled"
      end

      def holdings_cell(census, slug)
        return "not built in this checkout" if census.nil?

        row = census[slug]
        return "not synced yet" if row.nil?

        parts = []
        parts << "#{commas(row.docs)} docs" if row.docs.positive?
        parts << "#{commas(row.passages)} passages" if row.passages.positive?
        parts << "#{commas(row.entries)} entries" if row.entries.positive?
        parts << "#{commas(row.dossiers)} dossiers" if row.dossiers.positive?
        parts.empty? ? "nothing held yet" : parts.join(" / ")
      end

      def instruments_block(axis)
        text = fragment(axis.name)["instruments"]
        return "No axis-specific instruments curated yet — the generic surfaces above apply." unless text

        text.strip
      end

      def recipes_block(axis)
        recipes = fragment(axis.name)["recipes"]
        return "" unless recipes && !recipes.empty?

        lines = ["", "This desk's own surfaces:", "", "```"]
        recipes.each do |recipe|
          cmd = recipe.fetch("cmd")
          note = recipe["note"]
          lines << (note ? "#{cmd}#{padding(cmd)}# #{note}" : cmd)
        end
        lines << "```"
        "#{lines.join("\n")}\n"
      end

      def display_block(axis)
        text = fragment(axis.name)["display"]
        return "" unless text

        "\n## Terminal setup\n\n#{text.strip}\n\nThe full guidance, per script, is on the " \
          "[display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).\n\n"
      end

      def footer(_axis)
        "One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat " \
          "shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is " \
          "[docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md)."
      end

      # ---- small helpers --------------------------------------------------

      def as_of_human
        @as_of.strftime("%-d %B %Y")
      end

      def commas(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def padding(cmd)
        width = 38
        cmd.length >= width ? "  " : " " * (width - cmd.length)
      end

      def count_phrase(count)
        return "The single shelf below answers this desk." if count == 1

        word = WORD_NUMBERS[count] || count.to_s
        "A source wears every desk it serves — these #{word} answer this desk."
      end
    end
  end
end
