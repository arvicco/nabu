# frozen_string_literal: true

module Nabu
  module Adapters
    # The OpenITI .yml sidecar reader: the author sidecar
    # (data/<author>/<author>.yml) and the book sidecar
    # (data/<author>/<book>/<book>.yml) that travel with the release tree.
    #
    # == The format (censused over the 2025.1.9 tree)
    #
    # NOT YAML: one "<NN>#<TYPE>#<FIELD>###…: value" line per field, the
    # key padded with "#" to a fixed width, long values continued on
    # 4-space-indented lines. Every field ships pre-filled with upstream's
    # TEMPLATE text ("URIs from Althurayya, comma separated", "src@id",
    # "URI of a book from OpenITI, or [Author's Title], …") until a
    # cataloguer fills it — a template value is absence, never a value.
    #
    # Fields read (the rest — names, AH life dates, teachers/students,
    # bibliography, comments, book titles/editions — stay unread: the TSV
    # already carries names and the death year, and the AH life-date
    # fields are template-filled on all but a handful of authors):
    #
    # * 70#AUTH#EXTID — "wikidata@Q297913" (1,754 real Q-ids; one
    #   "wikidata@IGNORE" and one Wikipedia redlink URL never mint).
    # * 20#AUTH#DIED / 20#AUTH#RESIDED — comma-separated al-Ṯurayyā URIs
    #   (344 filled), settlement ids (QAHIRA_312E300N_S) mixed with region
    #   ids (Iraq_RE) and unfinished ids (SAFADXXXYYY); a trailing comma
    #   or a hedged token ("Khurasan_RE ?") is furniture/uncertainty —
    #   tokens with inner whitespace are dropped, never repaired.
    # * 40#BOOK#RELATED — ";"-separated "<book URI> (<relation>)" entries
    #   (422 filled books, 432 entries: COMM 248, PART 52, ABR 35, CONT 31,
    #   TRANSL 11 …). Only entries naming an OpenITI BOOK URI mint a work
    #   relation; author-only entries ("0241IbnHanbal"), bracketed titles
    #   and the template text mint none. A "> …" chain tail and a trailing
    #   full stop are furniture.
    module OpenitiSidecar
      KEY_LINE = /\A\d{2}#([A-Z]+)#([A-Z]+)#*\s*:(.*)\z/
      CONTINUATION = /\A\s+\S/

      TEMPLATE_PREFIXES = ["URIs from Althurayya", "URI of a book from OpenITI", "src@",
                           "viaf@id", "AUTH_URI from OpenITI", "YEAR-MON-DA", "permalink",
                           "a free running comment"].freeze

      WIKIDATA = /\Awikidata@(Q\d+)\z/
      PLACE_TOKEN = /\A[A-Za-z0-9_-]+\z/
      RELATED_ENTRY = /\A(\d{4}[A-Za-z]+\.[A-Za-z0-9]+)(?:\s*\(([^)]*)\))?/

      module_function

      # {"AUTH#DIED" => "…", …} — continuation lines joined with one
      # space; {} for a missing file.
      def fields(path)
        return {} unless File.file?(path)

        fields = {}
        current = nil
        File.foreach(path, encoding: Encoding::UTF_8, chomp: true) do |line|
          if (match = KEY_LINE.match(line))
            current = "#{match[1]}##{match[2]}"
            fields[current] = match[3].strip
          elsif current && CONTINUATION.match?(line)
            fields[current] = "#{fields[current]} #{line.strip}".strip
          end
        end
        fields
      end

      def template?(value)
        value.nil? || value.empty? || TEMPLATE_PREFIXES.any? { |prefix| value.start_with?(prefix) }
      end

      # The author sidecar's {"wikidata" => "Q…", "died" => […],
      # "resided" => […]} — only what is filled.
      def author_facts(path)
        fields = fields(path)
        facts = {}
        wikidata = wikidata_id(fields["AUTH#EXTID"])
        facts["wikidata"] = wikidata if wikidata
        { "died" => "AUTH#DIED", "resided" => "AUTH#RESIDED" }.each do |role, key|
          places = place_tokens(fields[key])
          facts[role] = places unless places.empty?
        end
        facts
      end

      def wikidata_id(value)
        return nil if template?(value)

        value.split(",").map(&:strip).filter_map { |token| token[WIKIDATA, 1] }.first
      end

      def place_tokens(value)
        return [] if template?(value)

        value.split(",").map(&:strip).grep(PLACE_TOKEN).uniq
      end

      # The book sidecar's RELATED value as [{"work", "relation"}].
      def related_works(path)
        parse_related(fields(path)["BOOK#RELATED"])
      end

      def parse_related(value)
        return [] if template?(value)

        value.split(";").filter_map do |entry|
          match = RELATED_ENTRY.match(entry.strip) or next
          { "work" => match[1], "relation" => match[2]&.strip }.compact
        end.uniq
      end
    end
  end
end
