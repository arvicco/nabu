# frozen_string_literal: true

require "yaml"

module Nabu
  # One SOURCE dossier (P24-0, architecture §16): the Markdown + YAML
  # front-matter file at canonical/local-source/<slug>.md that is the
  # PERMANENT home of everything nabu knows ABOUT a registered source —
  # the language dossier's twin at the source grain. Human-first by design
  # — greppable, editable in any editor, one file per shelf — and
  # machine-parsed into the catalog's derived source_records at
  # sync/rebuild.
  #
  # == The shape
  #
  #   ---
  #   slug: edh                    # required; must equal the filename base
  #   description: >-              # THE load-bearing curated lane: a 1–3
  #     Latin inscriptions from    #   sentence content description, served
  #     the whole Roman empire.    #   on cards and over MCP
  #   themes: [epigraphy, prosopography]   # curated list lane
  #   key_works: [urn:nabu:edh:hd029093]   # curated urn list lane
  #   period: Republic – Late Antiquity    # any other scalar key is an
  #                                        #   extra lane
  #   provenance:                  # optional documentation block — indexed
  #     exported: 2026-07-16       #   nowhere; git + section headers carry
  #   ---                          #   the real history
  #   Free prose up to the first "## " heading is the curated NOTE lane.
  #
  #   ## witness:survey (edh-survey, 2026-07-13)
  #   One accretion SECTION per kind — the language-dossier append-only
  #   latest-per-(slug, kind) contract verbatim: the section body IS the
  #   latest, the header carries (kind, provenance, date), supersession
  #   means a writer replacing its OWN section only (kinds are
  #   writer-owned).
  #
  # #records flattens the dossier into the derived (kind, body, provenance)
  # rows the catalog indexes (list lanes join with ", " — one row per kind,
  # the loader's replace key). Parsing normalizes to NFC at this boundary
  # (the adapter-boundary rule); #render is the deterministic inverse used
  # by the sanctioned write paths (SourceShelf accretion, the seed
  # exporter), so parse(render(d)) round-trips.
  class SourceDossier
    # The curated front-matter lanes with dedicated keys; anything else
    # scalar becomes an extra lane. `slug` and `provenance` are structural.
    # `group` (P28-4) is OWNER-ONLY: an optional header override for the
    # `nabu list --sources` map (absent = the family-lane derivation; present
    # = wins verbatim). No write path — seed/scaffold/ingest never set it;
    # the owner hand-edits the dossier.
    CURATED_KEYS = %w[description themes key_works group].freeze
    LIST_KEYS = %w[themes key_works].freeze
    STRUCTURAL_KEYS = %w[slug provenance].freeze

    # A parse failure (malformed front matter, slug mismatch, duplicate
    # section kind). The adapter wraps it in Nabu::ParseError → quarantine.
    class FormatError < Nabu::Error; end

    # One accretion section: kind ("witness:survey"), the provenance
    # source, the date it last changed, and the body prose.
    Section = Data.define(:kind, :provenance, :date, :body)

    # One derived record row (the catalog shape, minus slug).
    Record = Data.define(:kind, :body, :provenance)

    SECTION_HEADER = /\A##\s+(?<kind>\S+)\s+\((?<provenance>[^,()]+),\s*(?<date>[^)]+)\)\s*\z/
    FRONT_MATTER = /\A---\n(?<yaml>.*?)\n---\n?(?<body>.*)\z/m

    # Provenance recorded for the owner-curated lanes (front matter + note
    # prose) — the dossier itself is their authority.
    CURATED_PROVENANCE = "dossier"

    attr_reader :slug, :description, :themes, :key_works, :group, :note, :extras, :sections, :provenance

    def initialize(slug:, description: nil, themes: [], key_works: [], group: nil, note: nil,
                   extras: {}, sections: [], provenance: nil)
      @slug = slug
      @description = description
      @themes = themes
      @key_works = key_works
      @group = group
      @note = note
      @extras = extras
      @sections = sections
      @provenance = provenance
    end

    # Parse dossier +text+. +slug+ (when given — the adapter passes the
    # filename base) must match the front matter's slug: a renamed file
    # whose front matter still says something else is a real integrity
    # defect.
    def self.parse(text, slug: nil)
      match = FRONT_MATTER.match(text)
      raise FormatError, "missing YAML front matter (--- … ---)" unless match

      front = load_front_matter(match[:yaml])
      declared = front["slug"].to_s
      raise FormatError, "front matter has no slug:" if declared.empty?
      raise FormatError, "slug #{declared.inspect} does not match filename #{slug.inspect}" if slug && declared != slug

      note, sections = split_body(match[:body])
      new(slug: declared, description: presence(front["description"]),
          themes: list_from(front["themes"]), key_works: list_from(front["key_works"]),
          group: presence(front["group"]),
          note: note, extras: extras_from(front), sections: sections,
          provenance: front["provenance"])
    end

    def self.load_front_matter(yaml)
      front = YAML.safe_load(yaml)
      raise FormatError, "front matter must be a mapping, got #{front.class}" unless front.is_a?(Hash)

      front
    rescue Psych::Exception => e
      raise FormatError, "front matter is not valid YAML: #{e.message}"
    end
    private_class_method :load_front_matter

    # Note prose (everything before the first "## " heading) + the
    # sections. A "## " line that does not parse as a section header is a
    # format defect — silent tolerance would drop an accretion on
    # re-render.
    def self.split_body(body)
      chunks = body.split(/^(?=## )/)
      section_chunks = chunks
      note = nil
      unless chunks.empty? || chunks.first.start_with?("## ")
        note = presence(chunks.first)
        section_chunks = chunks.drop(1)
      end
      sections = section_chunks.map { |chunk| parse_section(chunk) }
      duplicate = sections.map(&:kind).tally.find { |_kind, count| count > 1 }
      raise FormatError, "duplicate section kind #{duplicate.first.inspect} — one section per kind" if duplicate

      [note, sections]
    end
    private_class_method :split_body

    def self.parse_section(chunk)
      header, _sep, rest = chunk.partition("\n")
      match = SECTION_HEADER.match(header)
      raise FormatError, "malformed section header #{header.inspect} — expected '## kind (source, date)'" unless match

      body = normalize(rest.strip)
      raise FormatError, "section #{match[:kind].inspect} has an empty body" if body.empty?

      Section.new(kind: match[:kind], provenance: match[:provenance].strip, date: match[:date].strip, body: body)
    end
    private_class_method :parse_section

    # Non-structural, non-curated scalar front-matter keys become extra
    # lanes (period, …); list values join with ", ".
    def self.extras_from(front)
      front.except(*STRUCTURAL_KEYS, *CURATED_KEYS).filter_map do |key, value|
        body = value.is_a?(Array) ? value.join(", ") : value.to_s.strip
        [key.to_s, normalize(body)] unless body.empty?
      end.to_h
    end
    private_class_method :extras_from

    # The curated list lanes accept a YAML list or a comma string; each
    # member normalizes to NFC.
    def self.list_from(value)
      members = value.is_a?(Array) ? value.map(&:to_s) : value.to_s.split(",")
      members.map(&:strip).reject(&:empty?).map { |member| normalize(member) }
    end
    private_class_method :list_from

    def self.presence(value)
      text = value.to_s.strip
      text.empty? ? nil : normalize(text)
    end
    private_class_method :presence

    def self.normalize(text)
      Nabu::Normalize.nfc(text)
    end

    # The derived rows the catalog indexes: curated lanes (description /
    # theme / key_work / note + front-matter extras) under
    # CURATED_PROVENANCE — list lanes joined ", ", one row per kind, the
    # loader's replace key — and one row per section under its own
    # provenance.
    def records
      rows = []
      rows << Record.new(kind: "description", body: description, provenance: CURATED_PROVENANCE) if description
      rows << Record.new(kind: "theme", body: themes.join(", "), provenance: CURATED_PROVENANCE) unless themes.empty?
      unless key_works.empty?
        rows << Record.new(kind: "key_work", body: key_works.join(", "), provenance: CURATED_PROVENANCE)
      end
      rows << Record.new(kind: "group", body: group, provenance: CURATED_PROVENANCE) if group
      rows << Record.new(kind: "note", body: note, provenance: CURATED_PROVENANCE) if note
      extras.each { |kind, body| rows << Record.new(kind: kind, body: body, provenance: CURATED_PROVENANCE) }
      sections.each { |s| rows << Record.new(kind: s.kind, body: s.body, provenance: s.provenance) }
      rows
    end

    def section(kind)
      sections.find { |s| s.kind == kind }
    end

    # A copy with +section+ replacing its own kind's section (or appended).
    # The own-section supersession contract: only the matching kind is
    # touched; every other section and every curated lane is carried
    # verbatim.
    def with_section(section)
      kept = sections.reject { |s| s.kind == section.kind }
      self.class.new(slug: slug, description: description, themes: themes, key_works: key_works,
                     group: group, note: note, extras: extras, sections: kept + [section],
                     provenance: provenance)
    end

    # Deterministic Markdown render — the inverse of .parse.
    def render
      "#{front_matter_yaml}---\n#{note_block}#{sections.map { |s| render_section(s) }.join}"
    end

    private

    def front_matter_yaml
      front = { "slug" => slug }
      front["description"] = description if description
      front["themes"] = themes unless themes.empty?
      front["key_works"] = key_works unless key_works.empty?
      front["group"] = group if group
      extras.each { |key, value| front[key] = value }
      front["provenance"] = provenance if provenance
      YAML.dump(front)
    end

    def note_block
      note ? "#{note}\n" : ""
    end

    def render_section(section)
      "\n## #{section.kind} (#{section.provenance}, #{section.date})\n\n#{section.body}\n"
    end
  end
end
