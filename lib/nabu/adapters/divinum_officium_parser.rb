# frozen_string_literal: true

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The divinum-officium-txt parser family: Divinum Officium's own data
    # format (web/www/{horas,missa}/<language>/**/*.txt), read FILE-LOCAL —
    # nothing that needs another file is resolved here.
    #
    # == The format (read from the real files, census 2026-11-04 @85183a9b)
    #
    # Upstream's reader is web/cgi-bin/DivinumOfficium/SetupString.pl; this
    # family mirrors its file-local grammar and stops where it starts
    # resolving across files:
    #
    # - SECTIONS: a line that begins with "[" and matches upstream's own
    #   header regex /^\s*\[([\pL\pN_ #,:-]+)\]/ opens a section, optionally
    #   followed by a conditional ("[Rank] (rubrica 1960)"). One file may
    #   repeat a section name under different conditions (836 repeats in
    #   500 files) — each occurrence is its own passage. A bracketed line
    #   that fails the regex ("[Agnus Dei is said *only* …].") is text.
    # - PREAMBLE: lines before the first header (upstream's "__preamble");
    #   in practice whole-file inheritances ("@Commune/C10" — 1,569 files)
    #   → metadata "inherits". A file with NO header at all (527: the
    #   psalms, the Rule, the necrology, the Mass ordinaries) is all body.
    # - @-REFERENCES: "@file:section:substitutions" (file omitted = self)
    #   pull text from elsewhere at render time. They are NEVER resolved:
    #   each rides verbatim in the passage's "includes" annotation, and a
    #   section that is nothing but references (no own text) mints no
    #   passage — its directives ride the document's "reference_sections".
    # - CONDITIONALS: a line opening with "(…)" whose first word belongs to
    #   upstream's conditional vocabulary (the stopwords sed/vero/atque/
    #   attamen/si/deinde and the SetupString subjects rubrica, tempore,
    #   feria, communi …, plus nisi/numquam/semper/hora) is a directive —
    #   raw text into "conditions", the sequel after ")" processed as its
    #   own line. Capitalized parentheticals ("(Canticum Isaiæ)",
    #   "(Percutit sibi pectus ter, dicens:)") are text and stay.
    # - CALLS: "$Per Dominum" (a named prayer) and "&Gloria" (a script
    #   function) → "calls", verbatim with the sigil; "#Psalmi"-style
    #   template headings inside a section → "headings".
    # - RUBRICS: "!…" lines are the books' rubrics and citations ("!Ps
    #   44:3", "!Liber 1, post initium") — kept IN the text (marker
    #   stripped: they are printed text of the books) and listed in
    #   "rubrics". "!*…" lines are display directives → "directives".
    # - "_" (also "_ `") and blank lines are paragraph furniture, dropped;
    #   an antiphon slot with no words (";;" among @-references, a bare
    #   psalm assignment ";;88(2-37)") → "placeholders".
    # - Everything else is text verbatim: "R."/"V."/"v." versicle
    #   prefixes, the "*" mediant and "†" flex, "+" cross signs, the
    #   ";;8" psalm assignments on antiphons — canonical means canonical.
    #
    # == Passage grains (the +layout+ the adapter picks per tree)
    #
    # :sections (default) —
    # - [Officium] → the document title AND a passage (the office's name);
    #   [Rank], [Rule] and [Name] are machine data (";;Duplex;;3;;vide
    #   C6-1", "9 lectiones", the saint's name forms that fill the commons'
    #   "N." — "Floriáni / Postcommunio=Floriáno") → metadata "rank" /
    #   "rule" / "name", never passages (a file
    #   without [Officium] takes its title from the rank line's own name
    #   field when it carries one).
    # - every other section with own text → one passage keyed by its name
    #   (spaces → "_"; a repeat takes "~2", "~3" in file order).
    # - header-bearing preamble text (only Ordo/OrdoOP has any) → "preamble".
    # - a header-less file is segmented on its "#Heading" lines (the Mass
    #   ordinaries' own division — "# Incipit", "#Canon"); text before the
    #   first heading keys "preamble"; with no heading, one passage "text".
    # :verses — the psalter: one passage per verse line "1:3a …", keyed by
    #   the verse ref with ":" → "." (…/Psalm1:1.3a).
    # :necrology — one passage per day ("Die 1. mensis januarii …"), keyed
    #   by the day number; the entries' "Anno 1746" death years ride
    #   "entry_years" (event dates of the commemorated — never the text's).
    class DivinumOfficiumParser
      LANGUAGE = "lat"
      LAYOUTS = %i[sections verses necrology].freeze

      HEADER = /\A\[(?<name>[\p{L}\p{N}_ #,:-]+)\]\s*(?<condition>\(.*\))?/
      # Upstream's conditional vocabulary (SetupString.pl %stopword_weights
      # + %subjects, and the forms its files actually open with).
      CONDITION_WORDS = %w[
        sed vero atque attamen si deinde nisi numquam semper
        rubrica rubricis tempore missa communi commune die feria votiva officio ad mense anno
        dioecesis tonus toni hora
      ].freeze
      CONDITIONAL = /\A\(\s*(?<cond>(?:#{CONDITION_WORDS.join('|')})\b[^()]*)\)\s*(?<sequel>.*)\z/
      VERSE = /\A(?<ref>\d+:\d+[a-z]?)\s+(?<text>.+)\z/
      ORDO_HEADING = /\A#\s*(?<name>\S.*?)\s*\z/
      NECROLOGY_DAY = /\ADie (?<name>\d+)\. mensis\b/
      ANNO = /\bAnno\s+(\d{3,4})\b/
      # An antiphon slot with no antiphon text — ";;" beside @-references,
      # or a bare psalm assignment (";;88(2-37)", ";;142('8a'-'12b')"):
      # list furniture, no word in it.
      PLACEHOLDER = /\A;;(?!.*\p{L}{2})/
      # The paragraph separator, also in its "_ `" form.
      SEPARATOR = /\A_\s*`?\z/
      METADATA_SECTIONS = %w[Rank Rule Name].freeze
      TITLE_SECTION = "Officium"

      Section = Struct.new(:name, :condition, :lines)
      Parsed = Data.define(:title, :passages, :metadata)
      Body = Data.define(:text, :annotations)

      # The file's own-text census, cheap enough for discovery: true iff
      # parsing would mint at least one passage.
      def self.own_text?(path, layout: :sections)
        !new.read(path, layout: layout).passages.empty?
      end

      # +fallback_title+ names a file whose own text states no title (a
      # psalm, a Rule chapter, a necrology month).
      def parse(path, urn:, metadata: {}, layout: :sections, fallback_title: nil)
        parsed = read(path, layout: layout)
        if parsed.passages.empty?
          raise Nabu::DocumentSkipped,
                "#{urn}: no own text (an inclusion stub — every section is an @-reference or machine data)"
        end

        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, title: parsed.title || fallback_title, canonical_path: path,
          metadata: metadata.merge(parsed.metadata)
        )
        parsed.passages.each_with_index do |(key, body), index|
          document << Nabu::Passage.new(urn: "#{urn}:#{key}", language: LANGUAGE, text: body.text,
                                        annotations: body.annotations, sequence: index)
        end
        document
      end

      # Parsed(title, [[key, Body]…], metadata) for one file.
      def read(path, layout: :sections)
        raise ArgumentError, "unknown layout #{layout.inspect}" unless LAYOUTS.include?(layout)

        preamble, sections = split(lines_of(path))
        metadata = {}
        passages = []
        keys = Hash.new(0)
        add = lambda do |name, body, extra = {}|
          slug = name.tr(" ", "_")
          keys[slug] += 1
          key = keys[slug] == 1 ? slug : "#{slug}~#{keys[slug]}"
          passages << [key, Body.new(text: body.text, annotations: extra.merge(body.annotations))]
        end

        if sections.empty?
          header_less(preamble, layout: layout, add: add, metadata: metadata)
        else
          read_preamble(preamble, metadata, add)
          read_sections(sections, metadata, add)
        end
        Parsed.new(title: metadata.delete(:title), passages: passages, metadata: metadata)
      end

      private

      def lines_of(path)
        raw = SourceRead.utf8_file(path, label: "divinum-officium")
        Nabu::Normalize.nfc(raw.delete_prefix("﻿")).split("\n").map { |line| line.delete_suffix("\r").rstrip }
      end

      # [preamble lines, [Section…]] — upstream's own split: only a line
      # whose FIRST character is "[" and that matches the header regex.
      def split(lines)
        preamble = []
        sections = []
        lines.each do |line|
          match = line.start_with?("[") && HEADER.match(line)
          if match
            sections << Section.new(match[:name], match[:condition], [])
          elsif sections.empty?
            preamble << line
          else
            sections.last.lines << line
          end
        end
        [preamble, sections]
      end

      def read_preamble(lines, metadata, add)
        body = classify(lines)
        inherits = body.annotations["includes"]
        if inherits
          metadata["inherits"] = inherits
          metadata["inherits_conditions"] = body.annotations["conditions"] if body.annotations["conditions"]
        end
        add.call("preamble", body) unless body.text.empty?
      end

      def read_sections(sections, metadata, add)
        references = {}
        sections.each do |section|
          extra = { "section" => section.name, "condition" => section.condition }.compact
          if METADATA_SECTIONS.include?(section.name)
            (metadata[section.name.downcase] ||= []) << { "lines" => section.lines.reject(&:empty?) }.merge(extra)
            next
          end

          body = classify(section.lines)
          if body.text.empty?
            directives = body.annotations.except("rubrics").values.flatten
            label = [section.name, section.condition].compact.join(" ")
            references[label] = (references[label] || []) + directives unless directives.empty?
            next
          end
          metadata[:title] ||= body.text.lines.first.strip if section.name == TITLE_SECTION
          add.call(section.name, body, extra)
        end
        metadata["reference_sections"] = references unless references.empty?
        rank_fields(metadata)
      end

      # The first unconditioned [Rank] line ("Name;;Duplex;;3;;vide C6-1"):
      # its class → "rank_class" (the facet value), its own name field →
      # the title fallback. Every variant rides "rank" whole.
      def rank_fields(metadata)
        plain = metadata["rank"]&.find { |rank| rank["condition"].nil? } or return
        fields = plain["lines"].first.to_s.split(";;").map(&:strip)
        metadata["rank_class"] = fields[1] unless fields[1].to_s.empty?
        metadata[:title] ||= fields[0] unless fields[0].to_s.empty?
      end

      def header_less(lines, layout:, add:, metadata:)
        return verses(lines, add) if layout == :verses

        marker = layout == :necrology ? NECROLOGY_DAY : ORDO_HEADING
        chunks = [["text", []]]
        lines.each do |line|
          heading = marker.match(line)
          if heading
            chunks.first[0] = "preamble" if chunks.size == 1
            chunks << [heading[:name], layout == :necrology ? [line] : []]
          else
            chunks.last[1] << line
          end
        end
        references = {}
        chunks.each do |name, chunk|
          body = classify(chunk)
          body = with_entry_years(body) if layout == :necrology
          if body.text.empty?
            directives = body.annotations.values.flatten
            references[name] = directives unless directives.empty?
          else
            add.call(name, body)
          end
        end
        metadata["reference_sections"] = references unless references.empty?
      end

      # A psalm file: "1:3a Et erit tamquam lignum …" per line; a line off
      # the verse grammar joins the verse before it (a continuation must
      # never be dropped), or keys "0" before the first verse.
      def verses(lines, add)
        current = nil
        flush = lambda do
          next if current.nil?

          body = classify(current[1])
          add.call(current[0].tr(":", "."), body, { "verse" => current[0] }) unless body.text.empty?
        end
        lines.each do |line|
          verse = VERSE.match(line)
          if verse
            flush.call
            current = [verse[:ref], [verse[:text]]]
          elsif current
            current[1] << line
          else
            current = ["0", [line]]
          end
        end
        flush.call
      end

      # The necrology day's entry years — the deaths it commemorates.
      def with_entry_years(body)
        years = body.text.scan(ANNO).flatten.map(&:to_i).uniq.sort
        return body if years.empty?

        Body.new(text: body.text, annotations: body.annotations.merge("entry_years" => years))
      end

      # Lines → Body(text, annotations) under the class-note grammar.
      def classify(lines)
        text = []
        notes = Hash.new { |hash, key| hash[key] = [] }
        lines.each { |line| classify_line(line.strip, text, notes) }
        Body.new(text: text.join("\n"), annotations: notes.to_h.reject { |_key, value| value.empty? })
      end

      def classify_line(line, text, notes)
        return if line.empty? || SEPARATOR.match?(line)

        if (conditional = CONDITIONAL.match(line))
          notes["conditions"] << "(#{conditional[:cond].strip})"
          return classify_line(conditional[:sequel].strip, text, notes)
        end

        return notes["placeholders"] << line if PLACEHOLDER.match?(line)

        case line[0]
        when "@" then notes["includes"] << line
        when "$", "&" then notes["calls"] << line
        when "#" then notes["headings"] << line
        when "!" then classify_rubric(line, text, notes)
        else text << line
        end
      end

      def classify_rubric(line, text, notes)
        return notes["directives"] << line if line.start_with?("!*")

        rubric = line.delete_prefix("!").strip
        return if rubric.empty?

        notes["rubrics"] << rubric
        text << rubric
      end
    end
  end
end
