# frozen_string_literal: true

require "json"
require "nokogiri"

module Nabu
  module Adapters
    # The `sefaria-json` parser family (P30-3): Sefaria's per-version export
    # files, one JSON object per title/version as served from the public GCS
    # bucket (json/{categories}/{title}/{language}/{versionTitle}.json).
    # Each file is SELF-DESCRIBING: its own title/versionTitle/license/
    # sectionNames metadata rides beside `text`.
    #
    # == The section structure (probed against the real bucket, 2026-07-18)
    #
    # `text` is either
    # - a JAGGED ARRAY of strings — nested to the depth `sectionNames`
    #   declares (["Chapter","Verse"] across the Tanakh shelf;
    #   ["Chapter","Verse","Paragraph"] on Targum Sheni), or
    # - a DICT of jagged arrays keyed by schema-node enTitle (complex titles:
    #   Targum Jerusalem spans the five Torah books under one title, no
    #   sectionNames, a `schema.nodes` list carrying the node order).
    # The parser walks whatever nesting is actually there rather than
    # trusting a declared depth: citation = the 1-based index path joined
    # with "." ("1.2", "1.2.9"), prefixed with the node slug for dict texts
    # ("genesis.1.2"). Passage urn = <doc-urn>:<citation>. EMPTY LEAVES are
    # the corpus's honest lacunae (Targum Jerusalem attests fragments only)
    # and never mint passages.
    #
    # == Text discipline
    #
    # Aramaic (`arc`) is NFC-EXEMPT (Normalize::NFC_EXEMPT_LANGUAGES — the
    # P26-3 owner ruling): bytes verbatim, edge whitespace stripped only.
    # English is NFC at the boundary. Inline HTML — Sefaria embeds footnote
    # apparatus (<sup class="footnote-marker">/<i class="footnote">) and
    # formatting tags (<b>, <i>, <br>) in some versions — is resolved at
    # parse: footnote bodies move to annotations["footnotes"] (apparatus in
    # the middle of a verse would corrupt the reading — the USFX <f> rule),
    # markers vanish, formatting tags unwrap keeping their text.
    #
    # A malformed file, a missing/mis-shaped `text`, a non-string leaf, or a
    # file with zero non-empty leaves is damage → Nabu::ParseError.
    class SefariaJsonParser
      # The shared identity fold (adapter urns + node citation tokens):
      # Sefaria titles/versionTitles are prose ("Targum Onkelos, vocalized
      # according to the Yemenite Taj " — upstream's own trailing space
      # included) folded to lowercase hyphen slugs. Minting is frozen once
      # used (standing rule) — changing this fold re-mints every urn.
      def self.slug(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      end

      def parse(path, urn:, language:, metadata: {}, license_override: nil)
        data = read_version(path)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title(data),
          canonical_path: path.to_s, metadata: metadata, license_override: license_override
        )
        sequence = 0
        each_leaf(data, path, language) do |citation, text, footnotes|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{citation}", language: language, text: text, sequence: sequence,
            annotations: footnotes.empty? ? {} : { "footnotes" => footnotes }
          )
          sequence += 1
        end
        raise ParseError, "#{path}: no non-empty text leaves" if document.empty?

        document
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def read_version(path)
        parsed = JSON.parse(File.read(path))
        raise ParseError, "#{path}: not a version object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed JSON: #{e.message}"
      end

      def title(data)
        [data["title"], data["versionTitle"]].map { |part| part.to_s.strip }.reject(&:empty?).join(" — ")
      end

      # Yield [citation, cleaned text, footnotes] for every non-empty leaf,
      # in reading order. Dict texts iterate in schema-node order (falling
      # back to the dict's own key order when a node is not listed).
      def each_leaf(data, path, language, &block)
        text = data["text"]
        case text
        in Hash
          node_order(data, text).each do |key|
            walk(text.fetch(key), [self.class.slug(key)], language, path, &block)
          end
        in Array
          walk(text, [], language, path, &block)
        else
          raise ParseError, "#{path}: text must be a jagged array or a schema-node dict, " \
                            "got #{text.class}"
        end
      end

      def node_order(data, text)
        nodes = data.dig("schema", "nodes")
        return text.keys unless nodes.is_a?(Array)

        listed = nodes.filter_map { |node| node["enTitle"] if node.is_a?(Hash) }.select { |key| text.key?(key) }
        listed + (text.keys - listed)
      end

      def walk(value, indices, language, path, &block)
        case value
        in String
          text, footnotes = clean(value, language)
          yield(indices.join("."), text, footnotes) unless text.empty?
        in Array
          value.each_with_index { |element, i| walk(element, indices + [i + 1], language, path, &block) }
        else
          raise ParseError, "#{path}: text leaf at #{indices.join('.')} must be a String or Array, " \
                            "got #{value.class}"
        end
      end

      # [running text, footnote bodies]. The HTML path runs only when markup
      # is actually present; NFC languages normalize at the boundary, the
      # exempt ones (arc) keep upstream bytes verbatim beyond edge strips.
      def clean(raw, language)
        text, footnotes = raw.include?("<") ? strip_markup(raw) : [raw, []]
        text = text.gsub(/[ \t]+/, " ").strip
        text = Normalize.nfc(text) unless text.empty? || Normalize.nfc_exempt?(language)
        [text, footnotes]
      end

      def strip_markup(raw)
        fragment = Nokogiri::HTML::DocumentFragment.parse(raw)
        footnotes = fragment.css("i.footnote").map { |node| node.text.strip }.reject(&:empty?)
        fragment.css("sup.footnote-marker, i.footnote").each(&:remove)
        fragment.css("br").each { |node| node.replace(" ") }
        [fragment.text, footnotes]
      end
    end
  end
end
