# frozen_string_literal: true

require "fileutils"
require "yaml"

module Nabu
  module Ops
    # The MCP skill pack (`rake skills:scaffold` / `rake skills:check`):
    # one skills/nabu-<desk>/SKILL.md per research desk (config/axes.yml),
    # so an agent connected to `nabu mcp` can load per-desk methodological
    # guidance — what the fields mean, what not to conflate, what to record
    # for reproducibility. The file shape is the Agent Skills one: YAML
    # front matter (name / description / license / compatibility /
    # metadata, metadata a string-to-string map) over a Markdown body.
    #
    # Two lanes per file, with different owners:
    #   * the MANAGED lanes — the `metadata.sources` line and the block
    #     between the BEGIN/END markers (the desk's live sources: slug,
    #     upstream name, license class; the verbatim terms keep their one
    #     home in docs/02-sources.md) — are a projection of
    #     the tracked registry (config/sources.yml + config/axes.yml + the
    #     adapter manifests). #sync! rewrites them in place; #stale reports
    #     any file whose managed lanes have drifted from the registry.
    #   * everything else is PROSE, seeded once by #scaffold (persona, desc,
    #     and the per-source dossier descriptions held on this box, read
    #     through the source-dossier reader) and owned by hand afterwards:
    #     #sync! never rewrites it. `metadata.origin` records which skills
    #     still carry the seed (generated) and which were rewritten into
    #     desk-specific guidance (hand-tuned).
    #
    # The managed lanes read ONLY tracked data, so the drift guard holds on
    # a public clone without the owner's dossier shelf. The seed prose is
    # scrubbed of internal development identifiers (phase/ruling tokens) —
    # meaningless to an outside agent.
    class SkillPack
      class FormatError < Nabu::Error; end

      Skill = Data.define(:front, :body)
      Result = Data.define(:path, :action)

      BEGIN_MARK = "<!-- nabu:skill-sources:begin — generated from config/sources.yml by " \
                   "`rake skills:scaffold`; edit outside this block -->"
      END_MARK = "<!-- nabu:skill-sources:end -->"
      MANAGED_BLOCK = /<!-- nabu:skill-sources:begin[^\n]*-->\n.*?<!-- nabu:skill-sources:end -->/m
      SOURCES_LINE = /^  sources: .*$/

      # The owner's memory shelves are a desk in the registry but private by
      # nature (architecture §16) — no public guidance file.
      EXCLUDED_DESKS = %w[local].freeze

      # The license of the guidance TEXT (the repository's). Every corpus a
      # skill names carries its own data license — the managed table says so.
      LICENSE = "MIT"

      COMPATIBILITY = "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a " \
                      "locally built Nabu catalog; tool names are the nabu_* set " \
                      "(nabu_status, nabu_search, nabu_show, and the desk instruments)."

      FRONT_MATTER = /\A---\n(?<yaml>.*?)\n---\n(?<body>.*)\z/m

      # Internal development identifiers in seed prose: a parenthetical that
      # cites one goes whole; a bare one goes with its leading preposition.
      INTERNAL_ID = %r{\b[PDQ]\d{1,3}(?:-[A-Za-z0-9]+)*(?:/[PDQ]?\d{1,3}(?:-[A-Za-z0-9]+)*)*\b}
      INTERNAL_PAREN = /\s*\([^()]*#{INTERNAL_ID}[^()]*\)/
      INTERNAL_BARE = /\s*(?:\b(?:since|by|per|in|from|at)\s+)?#{INTERNAL_ID}/

      def self.parse(text)
        match = FRONT_MATTER.match(text)
        raise FormatError, "missing YAML front matter (--- … ---)" unless match

        front = YAML.safe_load(match[:yaml])
        raise FormatError, "front matter must be a mapping, got #{front.class}" unless front.is_a?(Hash)

        Skill.new(front: front, body: match[:body])
      rescue Psych::SyntaxError => e
        raise FormatError, "front matter is not valid YAML: #{e.message}"
      end

      def self.skill_name(desk) = "nabu-#{desk}"

      def self.scrub(text)
        text.to_s.gsub(INTERNAL_PAREN, "").gsub(INTERNAL_BARE, "").gsub(/\s+([,.;:])/, '\1').strip
      end

      # +dossier+: slug -> description String or nil (the scaffold's seed
      # prose; the rake task wires it to the local-source shelf reader).
      # +examples+: desk -> [{"ask", "call", "answer"}] — the live-verified
      # MCP compositions curated in site/axis/_mcp.yml, seeded as the
      # skill's worked examples.
      def initialize(registry:, skills_dir:, dossier: ->(_slug) {}, examples: {})
        @registry = registry
        @skills_dir = skills_dir
        @dossier = dossier
        @examples = examples
      end

      def desks
        @registry.axes.names - EXCLUDED_DESKS
      end

      # A slug a public guidance file may name: registered, not grant-gated
      # private, and either wired (its sync link verified) or a feature
      # module (a live instrument by nature).
      def live_slug?(slug)
        entry = @registry[slug]
        return false unless entry&.public?

        entry.wired || entry.feature_module?
      end

      # The desk's live sources, registry order.
      def members(desk)
        @registry.public_axis_members(desk).select { |slug| live_slug?(slug) }
      end

      def path_for(desk)
        File.join(@skills_dir, self.class.skill_name(desk), "SKILL.md")
      end

      # Every SKILL.md under the skills dir (desk skills and any others).
      def skill_paths
        Dir.glob(File.join(@skills_dir, "*", "SKILL.md"))
      end

      # A fresh skeleton for +desk+: front matter, seed prose, managed block.
      def scaffold(desk)
        axis = @registry.axes[desk]
        persona = self.class.scrub(axis.persona)
        <<~MD
          ---
          name: #{self.class.skill_name(desk)}
          description: #{yaml_string(description_for(desk, axis))}
          license: #{LICENSE}
          compatibility: #{yaml_string(COMPATIBILITY)}
          metadata:
            desk: #{desk}
            origin: generated
          #{sources_line(desk)}
          ---

          # #{persona.split(' — ').first} — the `#{desk}` desk

          #{persona}

          #{self.class.scrub(axis.desc)}

          ## Sources on this desk

          The class is the machine-actionable reading of each source's data license; the
          verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

          #{managed_block(desk)}

          ## What the shelves hold

          #{seed_lines(desk)}
          #{example_lines(desk)}
          #{GENERIC_CAUTIONS}
        MD
      end

      # The managed lanes of +text+ re-projected for +desk+.
      def refresh(text, desk)
        raise FormatError, "#{path_for(desk)}: no managed sources block" unless text.match?(MANAGED_BLOCK)
        raise FormatError, "#{path_for(desk)}: no metadata.sources line" unless text.match?(SOURCES_LINE)

        text.sub(MANAGED_BLOCK) { managed_block(desk) }.sub(SOURCES_LINE) { sources_line(desk) }
      end

      # Create every missing desk skill; re-project the managed lanes of the
      # existing ones. Never touches prose.
      def sync!
        desks.map do |desk|
          path = path_for(desk)
          if File.exist?(path)
            current = File.read(path, encoding: "UTF-8")
            updated = refresh(current, desk)
            next Result.new(path: path, action: :unchanged) if updated == current

            File.write(path, updated)
            Result.new(path: path, action: :refreshed)
          else
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, scaffold(desk))
            Result.new(path: path, action: :created)
          end
        end
      end

      # Desk skills whose managed lanes drifted from the registry (or lost
      # them). Missing skills are not stale — the shipped-skills guard
      # reports those separately.
      def stale
        desks.filter_map do |desk|
          path = path_for(desk)
          next unless File.exist?(path)

          current = File.read(path, encoding: "UTF-8")
          begin
            path unless refresh(current, desk) == current
          rescue FormatError
            path
          end
        end
      end

      GENERIC_CAUTIONS = <<~MD.chomp
        ## Working cautions

        - **Data license is not code license.** This guidance text is MIT; every passage
          carries its own `license_class` (`open`, `attribution`, `nc`, `odbl`, and — excluded
          by default — `research_private` / `restricted`). `nc` forbids commercial reuse of the
          quoted text; `attribution` and `odbl` require naming the source edition (`odbl`
          also binds derived databases to share-alike). A `credit` key, when present, must
          travel with any quotation.
        - **An empty result is not absence of evidence.** Call `nabu_status` before concluding
          a text, word or form is unattested: the shelf may be unsynced on this box, the
          language may be indexed at another grain, or the class may be excluded by default.
        - **Search is folded, `nabu_show` is pristine.** Matching runs over a folded form
          (case, diacritics, and per-language rules); quote only the pristine text
          `nabu_show` returns, never a search snippet or a folded phrase.
        - **Lemma tiers differ in evidential weight.** `gold` lemmas are verified annotation
          and the only tier that counts as attestation; `silver` lemmas are upstream-automatic
          and always labeled; `equivalence` rows are glosses, never attestation. A lemma
          search reaches only the lemmatized minority of the corpus.
        - **Dates are typed.** A document's primary dated row has a class — `artifact` (the
          object's own dating), `composition` (an attributed author-era date), `edition` (a
          print year, never the text's date), or `silver` (a tool estimate, never an upstream
          claim). Years are signed, with no year 0. Use `date_basis` to keep the classes
          apart.

        ## Reproducibility

        Record, per claim: the passage or document `urn`, the `source` slug, its
        `license_class` (and `credit` when served), the exact tool call and arguments, and the
        date of the `nabu_status` snapshot the catalog answered from. Upstream editions are
        revised; the urn plus the catalog date is the citation, the snippet is not.
      MD

      private

      def description_for(desk, axis)
        noun = self.class.scrub(axis.persona).split(" — ").first.sub(/\AThe /, "")
        text = "Methodological guidance for the #{desk} desk of a Nabu library (#{noun}): " \
               "what its sources hold, their license classes, and the cautions to observe when " \
               "searching, reading and citing them through the nabu MCP tools."
        text[0, 1024]
      end

      def sources_line(desk)
        "  sources: #{yaml_string(members(desk).join(' '))}"
      end

      def managed_block(desk)
        rows = members(desk).map do |slug|
          manifest = @registry[slug].manifest
          "| `#{slug}` | #{cell(self.class.scrub(manifest.name))} | #{manifest.license_class} |"
        end
        [BEGIN_MARK, "| Source | Upstream | License class |", "| --- | --- | --- |", *rows, END_MARK].join("\n")
      end

      def seed_lines(desk)
        lines = members(desk).filter_map do |slug|
          text = self.class.scrub(@dossier.call(slug).to_s.gsub(/\s+/, " "))
          "- `#{slug}` — #{text}" unless text.empty?
        end
        lines.empty? ? "_No source descriptions were available when this skill was scaffolded._" : lines.join("\n")
      end

      def example_lines(desk)
        rows = Array(@examples[desk])
        return "" if rows.empty?

        lines = rows.map do |row|
          "- *#{row['ask']}* — `#{row['call']}`: #{self.class.scrub(row['answer'].to_s.gsub(/\s+/, ' '))}"
        end
        "\n## Worked examples\n\nCompositions verified live against a Nabu library " \
          "(holdings differ per box; check `nabu_status` first):\n\n#{lines.join("\n")}\n"
      end

      def cell(value)
        value.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip
      end

      def yaml_string(value)
        %("#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}")
      end
    end
  end
end
