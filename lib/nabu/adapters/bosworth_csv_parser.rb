# frozen_string_literal: true

require "csv"
require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The bosworth-csv parser family (P12-3): the Bosworth-Toller LINDAT dump's
    # bosworth_entries_export.csv — the first NON-TEI dictionary path. One
    # semicolon-separated, all-fields-quoted CSV (id;headword;body) whose body
    # field is multi-line project-XML (records end CRLF, body newlines are bare
    # LF) — stdlib CSV streams it row by row; naive line-splitting would shred
    # the bodies. Dump v0.1 reality (deposit readme: "Not all entries have been
    # checked and/or tagged"): flat, sense-less bodies are the NORM, so every
    # XML expectation here is optional, never assumed.
    #
    # == What one row yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the CSV id verbatim — the upsert key AND the upstream
    #   back-link (bosworthtoller.com/<id>). Ids have gaps; never invented.
    # - key_raw: the CSV headword verbatim.
    # - headword: the same, NFC (the body's <orth> always matches it in the
    #   fixture census; the CSV column is authoritative).
    # - headword_folded: hyphens dropped (B-T's morpheme notation:
    #   "æfter-cweðan"), then Normalize.search_form with "ang" — the
    #   conventions §9 fold (æ→ae, þ/ð→th), the same both-sides contract as
    #   lemma search.
    # - gloss: the first <equiv lang="eng"> (B-T's tagged English equivalent),
    #   else the first <def>'s text; trailing comma/semicolon trimmed.
    #   Best-effort: nil is honest for untagged and cross-reference entries.
    # - body: the entry as plain text — <search>/<sort>/<checked> technical
    #   fields skipped, each <sense> starting a new line (its <snum> text
    #   carries the label), <br/> honored, whitespace collapsed, the dump's
    #   double-encoded entities (&amp;#39;, &amp;mdash;, &amp;para;) decoded,
    #   NFC. Untagged bodies fall through as their whole text.
    # - citations: always empty — B-T cites OE works by short title without
    #   urns; the crosswalk to ISWOC/ASPR urns is future work (architecture
    #   §11).
    class BosworthCsvParser
      LANGUAGE = "ang"
      CSV_OPTIONS = { col_sep: ";", quote_char: '"', headers: true }.freeze

      # The second decode pass for the dump's double-encoded entities: after
      # Nokogiri's XML decode the TEXT still carries &#39;/&mdash;/&para;.
      # Fixture-grounded whitelist — a bare & is legitimate text and stays.
      NAMED_ENTITIES = { "&mdash;" => "—", "&para;" => "¶" }.freeze

      # Technical <form> fields skipped by the body linearizer: <search> and
      # <sort> duplicate the headword in normalized spellings (they would
      # pollute the display text), <checked> is workflow metadata.
      SKIPPED_ELEMENTS = %w[search sort checked].freeze

      # Parse +path+ and return its DictionaryEntry values in file order.
      def entries(path)
        CSV.foreach(path, **CSV_OPTIONS).map { |row| build_entry(row, path) }
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "bosworth-csv: malformed CSV in #{path}: #{e.message}"
      end

      private

      def build_entry(row, path)
        id, headword, body = row.values_at("id", "headword", "body")
        fragment = Nokogiri::XML.fragment(body.to_s)
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: headword, language: LANGUAGE,
          headword: Nabu::Normalize.nfc(headword.to_s),
          headword_folded: fold(headword.to_s),
          gloss: gloss(fragment),
          body: body_text(fragment),
          citations: []
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "bosworth-csv: row id=#{id.inspect} in #{path}: #{e.message}"
      end

      def fold(headword)
        Nabu::Normalize.search_form(headword.delete("-"), language: LANGUAGE)
      end

      def gloss(fragment)
        node = fragment.at_xpath('.//equiv[@lang="eng"]') || fragment.at_xpath(".//def")
        return nil unless node

        text = decode_entities(collapse(node.text)).sub(/[\s,;]+\z/, "")
        text.empty? ? nil : Nabu::Normalize.nfc(text)
      end

      # Linearize the entry: text in document order minus the technical
      # fields, sense boundaries as line breaks (the <snum> text supplies the
      # "I." label), collapsed and NFC.
      def body_text(fragment)
        buffer = +""
        walk(fragment, buffer)
        text = decode_entities(buffer).gsub(/[ \t]+/, " ").gsub(/ *\n+ */, "\n").strip
        Nabu::Normalize.nfc(text)
      end

      def walk(node, buffer)
        node.children.each do |child|
          if child.text?
            buffer << child.text.gsub(/\s+/, " ")
          elsif child.element?
            next if SKIPPED_ELEMENTS.include?(child.name)

            buffer << "\n" if %w[sense br].include?(child.name)
            walk(child, buffer)
          end
        end
      end

      # The dump double-encodes some entities (&amp;#39; in the raw CSV →
      # &#39; after the XML decode). Numeric references plus the named
      # whitelist decode here; anything else stays verbatim.
      def decode_entities(text)
        text.gsub(/&#(\d+);/) { Integer(::Regexp.last_match(1)).chr(Encoding::UTF_8) }
            .gsub(/&(?:mdash|para);/, NAMED_ENTITIES)
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
