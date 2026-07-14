# frozen_string_literal: true

require "yaml"

module Nabu
  # One language dossier (P19-1, architecture §16): the Markdown + YAML
  # front-matter file at canonical/local-language/<code>.md that is the
  # PERMANENT home of everything nabu knows about a language code. Human-first
  # by design — greppable, editable in any editor, one file per concept — and
  # machine-parsed into the catalog's derived language_records at sync/rebuild.
  #
  # == The shape
  #
  #   ---
  #   code: chu                    # required; must equal the filename base
  #   name: Old Church Slavonic    # optional — the curated name lane
  #   family: South Slavic < …     # optional — the curated family lane
  #   period: 9th–11th c.          # any other scalar key is an extra lane,
  #   scripts: [Cyrs, Glag]        #   rendered on the card as "key: value"
  #   provenance:                  # optional documentation block — recorded
  #     exported: 2026-07-14       #   nowhere; git + section headers carry
  #   ---                          #   the real history
  #   Free prose up to the first "## " heading is the curated CONTEXT lane.
  #
  #   ## witness:liv (liv, 2026-07-14)
  #   One accretion SECTION per kind — the P18-4 append-only
  #   latest-per-(code, kind) contract mapped onto files: the section body IS
  #   the latest, the header carries (kind, provenance source, date), and
  #   supersession means a writer replacing its OWN section, never someone
  #   else's (kinds are writer-owned: "iecor", "witness:<slug>").
  #
  # #records flattens the dossier into the derived (kind, body, source) rows
  # the catalog indexes. Parsing normalizes to NFC at this boundary (the
  # adapter-boundary rule); #render is the deterministic inverse used by the
  # sanctioned write paths (LanguageShelf accretion, the migration exporter),
  # so parse(render(d)) round-trips.
  class LanguageDossier
    # The curated front-matter lanes with dedicated keys; anything else scalar
    # becomes an extra lane. `code` and `provenance` are structural, not lanes.
    CURATED_KEYS = %w[name family].freeze
    STRUCTURAL_KEYS = %w[code provenance].freeze

    # A parse failure (malformed front matter, code mismatch, duplicate
    # section kind). Adapters wrap it in Nabu::ParseError → quarantine.
    class FormatError < Nabu::Error; end

    # One accretion section: kind ("iecor", "witness:liv"), the provenance
    # source, the date it last changed, and the body prose.
    Section = Data.define(:kind, :source, :date, :body)

    # One derived record row (the catalog shape, minus lang_code).
    Record = Data.define(:kind, :body, :source)

    SECTION_HEADER = /\A##\s+(?<kind>\S+)\s+\((?<source>[^,()]+),\s*(?<date>[^)]+)\)\s*\z/
    FRONT_MATTER = /\A---\n(?<yaml>.*?)\n---\n?(?<body>.*)\z/m

    # Provenance source recorded for the owner-curated lanes (front matter +
    # context prose) — the dossier itself is their authority.
    CURATED_SOURCE = "dossier"

    attr_reader :code, :name, :family, :context, :extras, :sections, :provenance

    def initialize(code:, name: nil, family: nil, context: nil, extras: {}, sections: [], provenance: nil)
      @code = code
      @name = name
      @family = family
      @context = context
      @extras = extras
      @sections = sections
      @provenance = provenance
    end

    # Parse dossier +text+. +code+ (when given — the adapter passes the
    # filename base) must match the front matter's code: a renamed file whose
    # front matter still says something else is a real integrity defect.
    def self.parse(text, code: nil)
      match = FRONT_MATTER.match(text)
      raise FormatError, "missing YAML front matter (--- … ---)" unless match

      front = load_front_matter(match[:yaml])
      declared = front["code"].to_s
      raise FormatError, "front matter has no code:" if declared.empty?
      raise FormatError, "code #{declared.inspect} does not match filename #{code.inspect}" if code && declared != code

      context, sections = split_body(match[:body])
      new(code: declared, name: presence(front["name"]), family: presence(front["family"]),
          context: context, extras: extras_from(front), sections: sections,
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

    # Context prose (everything before the first "## " heading) + the
    # sections. A "## " line that does not parse as a section header is a
    # format defect — silent tolerance would drop an accretion on re-render.
    def self.split_body(body)
      chunks = body.split(/^(?=## )/)
      section_chunks = chunks
      context = nil
      unless chunks.empty? || chunks.first.start_with?("## ")
        context = presence(chunks.first)
        section_chunks = chunks.drop(1)
      end
      sections = section_chunks.map { |chunk| parse_section(chunk) }
      duplicate = sections.map(&:kind).tally.find { |_kind, count| count > 1 }
      raise FormatError, "duplicate section kind #{duplicate.first.inspect} — one section per kind" if duplicate

      [context, sections]
    end
    private_class_method :split_body

    def self.parse_section(chunk)
      header, _sep, rest = chunk.partition("\n")
      match = SECTION_HEADER.match(header)
      raise FormatError, "malformed section header #{header.inspect} — expected '## kind (source, date)'" unless match

      body = normalize(rest.strip)
      raise FormatError, "section #{match[:kind].inspect} has an empty body" if body.empty?

      Section.new(kind: match[:kind], source: match[:source].strip, date: match[:date].strip, body: body)
    end
    private_class_method :parse_section

    # Non-structural, non-curated scalar front-matter keys become extra lanes
    # (period, scripts, …); list values join with ", ".
    def self.extras_from(front)
      front.except(*STRUCTURAL_KEYS, *CURATED_KEYS).filter_map do |key, value|
        body = value.is_a?(Array) ? value.join(", ") : value.to_s.strip
        [key.to_s, normalize(body)] unless body.empty?
      end.to_h
    end
    private_class_method :extras_from

    def self.presence(value)
      text = value.to_s.strip
      text.empty? ? nil : normalize(text)
    end
    private_class_method :presence

    def self.normalize(text)
      Nabu::Normalize.nfc(text)
    end

    # The derived rows the catalog indexes: curated lanes (name/family/context
    # + front-matter extras) under CURATED_SOURCE, one row per section under
    # its own provenance source.
    def records
      rows = []
      rows << Record.new(kind: "name", body: name, source: CURATED_SOURCE) if name
      rows << Record.new(kind: "family", body: family, source: CURATED_SOURCE) if family
      rows << Record.new(kind: "context", body: context, source: CURATED_SOURCE) if context
      extras.each { |kind, body| rows << Record.new(kind: kind, body: body, source: CURATED_SOURCE) }
      sections.each { |s| rows << Record.new(kind: s.kind, body: s.body, source: s.source) }
      rows
    end

    def section(kind)
      sections.find { |s| s.kind == kind }
    end

    # A copy with +section+ replacing its own kind's section (or appended).
    # The own-section supersession contract: only the matching kind is
    # touched; every other section and every curated lane is carried verbatim.
    def with_section(section)
      kept = sections.reject { |s| s.kind == section.kind }
      self.class.new(code: code, name: name, family: family, context: context,
                     extras: extras, sections: kept + [section], provenance: provenance)
    end

    # Deterministic Markdown render — the inverse of .parse.
    def render
      "#{front_matter_yaml}---\n#{context_block}#{sections.map { |s| render_section(s) }.join}"
    end

    private

    def front_matter_yaml
      front = { "code" => code }
      front["name"] = name if name
      front["family"] = family if family
      extras.each { |key, value| front[key] = value }
      front["provenance"] = provenance if provenance
      YAML.dump(front)
    end

    def context_block
      context ? "#{context}\n" : ""
    end

    def render_section(section)
      "\n## #{section.kind} (#{section.source}, #{section.date})\n\n#{section.body}\n"
    end
  end
end
