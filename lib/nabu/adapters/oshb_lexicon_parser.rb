# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The oshb-lexicon parser family (P30-1): the openscriptures/HebrewLexicon
    # XML files — the OSHB project's own namespace
    # (http://openscriptures.github.com/morphhb/namespace), DOM-parsed (the
    # largest file is 2.9 MB, under the no-DOM-over-5MB line). Two surfaces:
    #
    # == #strongs_entries — the augmented-Strong shelf (THE JOIN CONTRACT)
    #
    # One DictionaryEntry per AugIndex <w aug="…"> row, in file order. The
    # @aug value IS the entry id VERBATIM ("1254a", "7225", and the eight
    # non-numeric particle ids "b" "c" "d" "i" "k" "l" "m" "s") — exactly
    # what an OSHB lemma yields after the one mechanical normalization
    # (HebrewLexicon.normalize_lemma: final /-segment, spaces stripped,
    # trailing + stripped), so urn:nabu:dict:hebrew-lexicon:<id> is what an
    # OSHB token predicts. Survey-measured 100.000% token join on the live
    # catalog; 1,906/1,906 on the OSHB fixtures.
    #
    # Assembly per entry (chain measured 0-dangling upstream, kept loud here):
    # the aug target names the LexicalIndex entry (headword = its Hebrew
    # citation-form <w> BYTE-VERBATIM — the P26-3 Masoretic NFC exemption —
    # key_raw = the LexicalIndex id, gloss = its curated one-line <def>, a
    # complete lane over all 9,299 aug targets, measured); the entry language
    # comes from the LexicalIndex <part xml:lang> (heb → hbo, arc → arc — the
    # H/A number spaces share one shelf; HebrewStrong's own xml:lang also
    # tags proper nouns "x-pn", which is not a language, so the part is the
    # honest source). The body is one labeled line per upstream element:
    # LexicalIndex xlit and pos, the full HebrewStrong lanes (source /
    # meaning / usage / note, inline <w src> refs flattened to their display
    # text) for the H<base> entry of a numeric id — a numeric base without
    # its HebrewStrong entry is a ParseError (0 missing upstream), while the
    # non-numeric particle ids honestly have none — then the xref ids
    # verbatim (strong, aug, bdb, twot). The bdb line's id resolves on the
    # bdb shelf (urn:nabu:dict:bdb:<id>); no citation rows are minted here —
    # print pages belong to the BDB outline that carries them. The <etym>
    # scaffolding (LexicalIndex-internal root links) stays in canonical,
    # deliberately unmined this packet.
    #
    # == #bdb_entries — the BDB outline shelf
    #
    # One DictionaryEntry per BrownDriverBriggs <entry>, in file order,
    # language from the <part xml:lang> (23 heb + 23 arc parts upstream).
    # headword = the first <w> child byte-verbatim, gloss = the first <def>
    # at any depth (nil for the bare cross-reference entries), body = one
    # line per structural node: the entry's own attribute markers (mod — the
    # homograph numeral — and type) as labeled lines, the head text (every
    # non-sense child flattened in document order), then each <sense> at any
    # depth on its own line prefixed by its @n ("1. …"). <status> is
    # workflow metadata ("done"/"ref"/"base"/"made"/"new"/"added"), never
    # body text; its @p — the entry's print page in BDB 1906 — mints a
    # citation row (the aed Wb-pages pattern: cts_work nil, resolution
    # deferred until the 1906 scan lands in local-library), and the rare
    # mid-entry <page p="…"/> turn (×2 upstream) mints a second row.
    # Scripture <ref> elements keep their display text in the body; the
    # machine @r attribute is deliberately not minted this packet (P30-1
    # scope: print pages only — the verse-keyed citation lane is P30-2's).
    class OshbLexiconParser
      LANGUAGE_BY_PART = { "heb" => "hbo", "arc" => "arc" }.freeze

      HEAD_SKIP = %w[sense status].freeze
      private_constant :HEAD_SKIP

      # AugIndex + LexicalIndex + HebrewStrong → the augmented-Strong shelf's
      # DictionaryEntry values, in AugIndex file order.
      def strongs_entries(aug_path:, lexical_index_path:, strong_path:)
        lexical = lexical_index(lexical_index_path)
        strong = strong_index(strong_path)
        xml(aug_path).xpath("/index/w").map do |row|
          build_strong_entry(row, lexical: lexical, strong: strong, path: aug_path)
        end
      end

      # BrownDriverBriggs → the BDB outline shelf's DictionaryEntry values,
      # in file order.
      def bdb_entries(path)
        xml(path).xpath("/lexicon/part").flat_map do |part|
          language = part_language(part, path: path)
          part.xpath(".//entry").map { |entry| build_bdb_entry(entry, language: language, path: path) }
        end
      end

      private

      def xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "oshb-lexicon: malformed XML in #{path}: #{e.message}"
      end

      def part_language(part, path:)
        lang = part["lang"].to_s
        LANGUAGE_BY_PART.fetch(lang) do
          raise Nabu::ParseError, "oshb-lexicon: #{path}: part xml:lang #{lang.inspect} is neither heb nor arc"
        end
      end

      # LexicalIndex id → { entry:, language: } (language from the owning part).
      def lexical_index(path)
        xml(path).xpath("/index/part").each_with_object({}) do |part, index|
          language = part_language(part, path: path)
          part.xpath("entry").each do |entry|
            id = entry["id"].to_s
            raise Nabu::ParseError, "oshb-lexicon: #{path}: entry without @id" if id.empty?

            index[id] = { entry: entry, language: language }
          end
        end
      end

      def strong_index(path)
        xml(path).xpath("/lexicon/entry").to_h { |entry| [entry["id"].to_s, entry] }
      end

      def build_strong_entry(row, lexical:, strong:, path:)
        id = row["aug"].to_s
        raise Nabu::ParseError, "oshb-lexicon: #{path}: <w> row without @aug" if id.empty?

        target = row.text.strip
        entry = lexical.fetch(target) do
          raise Nabu::ParseError,
                "oshb-lexicon: aug id #{id.inspect} names missing LexicalIndex entry #{target.inspect}"
        end
        li = entry.fetch(:entry)
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: target, language: entry.fetch(:language),
          headword: headword(li, id: id),
          headword_folded: Nabu::Normalize.search_form(headword(li, id: id), language: entry.fetch(:language)),
          gloss: optional_text(li.at_xpath("def")),
          body: strong_body(id, index_entry: li, strong: strong)
        )
      end

      def headword(node, id:)
        text = node.at_xpath("w")&.text.to_s
        raise Nabu::ParseError, "oshb-lexicon: entry #{id} without a <w> headword" if text.strip.empty?

        text
      end

      def strong_body(id, index_entry:, strong:)
        lines = [labeled("xlit", index_entry.at_xpath("w")&.[]("xlit")),
                 labeled("pos", optional_text(index_entry.at_xpath("pos")))]
        lines.concat(strong_lines(id, strong: strong))
        xref = index_entry.at_xpath("xref")
        %w[strong aug bdb twot].each { |key| lines << labeled(key, xref&.[](key)) }
        lines.compact.join("\n")
      end

      # The full Strong's lanes for a numeric augmented id ("1254a" → H1254).
      # The eight non-numeric particle ids honestly have no HebrewStrong
      # entry; a NUMERIC base without one is damage (0 missing upstream).
      def strong_lines(id, strong:)
        base = id[/\A\d+/]
        return [] if base.nil?

        entry = strong.fetch("H#{base}") do
          raise Nabu::ParseError, "oshb-lexicon: aug id #{id.inspect} has no HebrewStrong entry H#{base}"
        end
        %w[source meaning usage note].filter_map { |name| labeled(name, optional_text(entry.at_xpath(name))) }
      end

      def build_bdb_entry(entry, language:, path:)
        id = entry["id"].to_s
        raise Nabu::ParseError, "oshb-lexicon: #{path}: BDB entry without @id" if id.empty?

        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: id, language: language,
          headword: headword(entry, id: id),
          headword_folded: Nabu::Normalize.search_form(headword(entry, id: id), language: language),
          gloss: optional_text(entry.at_xpath(".//def")),
          body: bdb_body(entry),
          citations: bdb_citations(entry)
        )
      end

      def bdb_body(entry)
        lines = [labeled("mod", entry["mod"]), labeled("type", entry["type"]), head_line(entry)]
        entry.xpath("sense").each { |sense| sense_lines(sense, lines) }
        lines.compact.reject(&:empty?).join("\n")
      end

      # The entry's own running text: every child except the sense tree and
      # the <status> workflow tail, flattened in document order.
      def head_line(entry)
        collapse(entry.children.reject { |node| HEAD_SKIP.include?(node.name) }.map(&:text).join)
      end

      # Depth-first: each sense contributes its OWN text (nested senses
      # excluded) as one line, "@n."-prefixed when numbered, then recurses.
      def sense_lines(sense, lines)
        own = collapse(sense.children.reject { |node| node.name == "sense" }.map(&:text).join)
        own = "#{sense['n']}. #{own}" if sense["n"] && !own.empty?
        lines << own
        sense.xpath("sense").each { |nested| sense_lines(nested, lines) }
      end

      # The print-page anchors (the aed Wb-pages pattern): the <status>'s @p
      # — the page this entry starts on in BDB 1906 — then any mid-entry
      # <page p/> turn. cts_work stays nil: nothing resolves until the 1906
      # scan lands in local-library; @p is the future deep-link key.
      def bdb_citations(entry)
        pages = [entry.at_xpath("status")&.[]("p"), *entry.xpath(".//page").map { |page| page["p"] }]
        pages.compact.reject(&:empty?).map do |page|
          Nabu::DictionaryCitation.new(urn_raw: "BDB p. #{page}", cts_work: nil,
                                       citation: page, label: "BDB p. #{page}")
        end
      end

      def labeled(label, value)
        text = collapse(value.to_s)
        text.empty? ? nil : "#{label}: #{text}"
      end

      def optional_text(node)
        return nil if node.nil?

        text = collapse(node.text)
        text.empty? ? nil : text
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
