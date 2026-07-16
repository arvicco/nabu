# frozen_string_literal: true

require_relative "source_dossier"
require_relative "source_shelf"

module Nabu
  # THE SEED (P24-0): the owner-fired one-shot that scaffolds a
  # canonical/local-source dossier for EVERY registered source, seeding the
  # load-bearing description from the best EXISTING prose — never inventing
  # content. Fired by the owner (`nabu list --export-source-dossiers`);
  # after it, `nabu sync local-source` derives the catalog records and the
  # list card / census / MCP serve the descriptions.
  #
  # == Where descriptions come from (the census, in precedence order)
  #
  # 1. docs/library.md per-shelf sections — a section whose `| **Source** |`
  #    table row names the slug in backticks contributes its first prose
  #    paragraph; a `- **`slug`** — …` bullet (the §8h shape) contributes
  #    its own text and, being slug-specific, WINS over section prose.
  # 2. config/sources.yml standalone comment lines inside the slug's block
  #    (the shelf-description comments; inline flag comments and
  #    license_watch lines are process notes, excluded).
  # 3. Nothing found → the HONEST STUB: a dossier with the slug and a
  #    provenance block saying no prose existed — description absent, never
  #    invented. The report counts stubs separately so the owner knows
  #    which shelves still need a hand-written description.
  #
  # Descriptions cap at three sentences (the dossier contract: a 1–3
  # sentence content description). IDEMPOTENT at the file grain: an
  # existing dossier is a no-op, whatever it contains — the owner's edits
  # (and prior seeds) always win. +dry_run+ computes the full report
  # without touching the tree.
  class SourceDossierExport
    # One export's outcome: dossiers written (of which +stubs+ carried no
    # description because no prose existed), and files already present
    # (unchanged — the idempotency contract).
    Report = Data.define(:written, :stubs, :unchanged, :stub_slugs)

    SENTENCE_CAP = 3

    def initialize(registry:, dir:, library_md: nil, sources_yml: nil, now: Time.now)
      @registry = registry
      @shelf = SourceShelf.new(dir: dir)
      @library_md = library_md
      @sources_yml = sources_yml
      @now = now
    end

    def run!(dry_run: false)
      written = 0
      unchanged = 0
      stub_slugs = []
      @registry.slugs.sort.each do |slug|
        if File.file?(@shelf.path_for(slug))
          unchanged += 1
          next
        end
        description, origin = best_prose(slug)
        stub_slugs << slug if description.nil?
        @shelf.write!(dossier_for(slug, description, origin)) unless dry_run
        written += 1
      end
      Report.new(written: written, stubs: stub_slugs.size, unchanged: unchanged, stub_slugs: stub_slugs)
    end

    private

    def dossier_for(slug, description, origin)
      provenance = { "exported" => @now.strftime("%Y-%m-%d"),
                     "seeded_from" => origin || "none — honest stub; no existing prose found, write the description" }
      SourceDossier.new(slug: slug, description: description, provenance: provenance)
    end

    # [description, origin] from the census precedence, or [nil, nil].
    def best_prose(slug)
      bullet = library_bullets[slug]
      return [bullet, "docs/library.md (source bullet)"] if bullet

      section = library_sections[slug]
      return [section, "docs/library.md (shelf section)"] if section

      comment = yml_comments[slug]
      return [comment, "config/sources.yml (shelf comments)"] if comment

      [nil, nil]
    end

    # -- docs/library.md ------------------------------------------------------

    def library_text
      @library_text ||= @library_md && File.file?(@library_md) ? File.read(@library_md, encoding: "UTF-8") : ""
    end

    def library_chunks
      @library_chunks ||= library_text.split(/^(?=## )/)
    end

    # { slug => first prose paragraph } for every slug named in a section's
    # `| **Source** |` row. A multi-source section seeds each of its slugs
    # with the same shelf prose — the section describes the shelf they
    # share.
    def library_sections
      @library_sections ||= library_chunks.each_with_object({}) do |chunk, map|
        slugs = chunk.scan(/^\|\s*\*\*Source\*\*\s*\|(.*)$/).flatten
                     .flat_map { |cell| cell.scan(/`([a-z0-9-]+)`/) }.flatten
        next if slugs.empty?

        prose = first_prose_paragraph(chunk)
        next if prose.nil?

        slugs.each { |slug| map[slug] ||= prose }
      end
    end

    # { slug => bullet text } for `- **`slug`** — …` bullets (the library.md
    # §8h shape) — slug-specific, so they win over section prose.
    def library_bullets
      @library_bullets ||= library_chunks.each_with_object({}) do |chunk, map|
        chunk.split(/^(?=- )/).each do |piece|
          match = /\A- \*\*`(?<slug>[a-z0-9-]+)`\*\*\s*—\s*(?<text>.+?)(?=\n- |\z)/m.match(piece)
          next unless match

          map[match[:slug]] ||= sentences(flatten_prose(match[:text]))
        end
      end
    end

    # The first paragraph of a section that is prose: not the heading, not
    # a table row, not a bullet, not bold-labelled furniture ("**Research
    # uses:** …" is a use catalogue, not a description).
    def first_prose_paragraph(chunk)
      chunk.split(/\n\s*\n/).drop(1).each do |paragraph|
        text = paragraph.strip
        next if text.empty? || text.start_with?("|", "#", "-", "*")

        return sentences(flatten_prose(text))
      end
      nil
    end

    # -- config/sources.yml ---------------------------------------------------

    # { slug => joined standalone comments } from each slug's block. Inline
    # comments (after a value) never match the line-start rule; commented
    # license_watch examples are excluded by name.
    def yml_comments
      @yml_comments ||= begin
        map = Hash.new { |hash, key| hash[key] = [] }
        slug = nil
        yml_lines.each do |line|
          if (top = /\A([a-z0-9-]+):/.match(line))
            slug = top[1]
          elsif slug && (comment = /\A\s+#\s?(?<text>\S.*)\z/.match(line))
            text = comment[:text].strip
            map[slug] << text unless text.start_with?("license_watch")
          end
        end
        map.transform_values { |lines| sentences(lines.join(" ")) }.reject { |_slug, text| text.empty? }
      end
    end

    def yml_lines
      return [] unless @sources_yml && File.file?(@sources_yml)

      File.read(@sources_yml, encoding: "UTF-8").lines.map(&:chomp)
    end

    # -- prose shaping ----------------------------------------------------------

    def flatten_prose(text)
      text.gsub(/\s+/, " ").strip
    end

    def sentences(text)
      text.split(/(?<=[.!?])\s+/).first(SENTENCE_CAP).join(" ")
    end
  end
end
