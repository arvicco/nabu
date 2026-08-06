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
    #   ["Chapter","Verse","Paragraph"] on Targum Sheni; ["Daf","Line"] on
    #   the Bavli shelves; ["Chapter","Halakhah","Segment"] on Yerushalmi), or
    # - a DICT keyed by schema-node enTitle (complex titles: Targum
    #   Jerusalem spans the five Torah books under one title, no
    #   sectionNames, a `schema.nodes` list carrying the node order), whose
    #   values are jagged arrays OR nested node dicts (Sifra's per-parashah
    #   chapters, TDEZ's Additions — P60 rider); nested levels walk in the
    #   dict's own key order, stacking slug segments, and sibling keys the
    #   frozen slug fold collapses disambiguate "-2" in walk order (see
    #   #walk_nodes).
    # The parser walks whatever nesting is actually there rather than
    # trusting a declared depth: citation = the 1-based index path joined
    # with "." ("1.2", "1.2.9"), prefixed with the node slug for dict texts
    # ("genesis.1.2"); a DEFAULT node (enTitle "" — the P55-3 Rabbah shape,
    # Petichta + "") cites bare, mirroring upstream's own "Ruth Rabbah 1:1".
    # Passage urn = <doc-urn>:<citation>. EMPTY LEAVES are
    # the corpus's honest lacunae (Targum Jerusalem attests fragments only;
    # a Bavli tractate's pre-start dafs) and never mint passages.
    #
    # == Daf citation mode (P46-1; FROZEN once minted)
    #
    # When `sectionNames[0] == "Daf"` the TOP level of the jagged array is
    # positional from daf 1a — 1-based position p is daf ceil(p/2), amud
    # "a" for odd p — and the citation's first token is `<daf><amud>`
    # ("25b.1" = daf 25 amud b line 1). Verified against the live bucket
    # 2026-07-25: Wikisource Tamid's first non-empty position is 50 → 25b
    # (Tamid's real Vilna start) and its last 66 → 33b; Davidson Chagigah
    # runs 2a..27a. Deeper levels stay numeric.
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

      # Daf-mode top-level citation token (see the class note): 1-based
      # position → "<daf><amud>". FROZEN — changing this re-mints every
      # Bavli passage urn.
      def self.daf_citation(position)
        "#{(position + 1) / 2}#{position.odd? ? 'a' : 'b'}"
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
      def each_leaf(data, path, language, &)
        text = data["text"]
        daf = daf_mode?(data)
        case text
        in Hash
          walk_nodes(text, node_order(data, text), [], language, path, &)
        in Array
          walk(text, [], language, path, daf: daf, &)
        else
          raise ParseError, "#{path}: text must be a jagged array or a schema-node dict, " \
                            "got #{text.class}"
        end
      end

      # sectionNames serializes AFTER text in the bucket files but rides the
      # same object; ["Daf", ...] flips the top level to daf.amud citations.
      def daf_mode?(data)
        sections = data["sectionNames"]
        sections.is_a?(Array) && sections.first == "Daf"
      end

      def node_order(data, text)
        nodes = data.dig("schema", "nodes")
        return text.keys unless nodes.is_a?(Array)

        listed = nodes.filter_map { |node| node["enTitle"] if node.is_a?(Hash) }.select { |key| text.key?(key) }
        listed + (text.keys - listed)
      end

      def walk(value, indices, language, path, daf: false, &block)
        case value
        in String
          text, footnotes = clean(value, language)
          yield(indices.join("."), text, footnotes) unless text.empty?
        in Array
          value.each_with_index do |element, i|
            # Node dicts nest only as NODE VALUES (Sifra's per-parashah
            # chapters, TDEZ's Additions) — a dict INSIDE section content is
            # unattested upstream and stays loud, never silently invented.
            reject_leaf(element, indices + [i + 1], path) if element.is_a?(Hash)
            token = daf && indices.empty? ? self.class.daf_citation(i + 1) : i + 1
            walk(element, indices + [token], language, path, &block)
          end
        in Hash
          # A nested schema-node dict (Sifra's per-parashah chapters, TDEZ's
          # Additions), in ITS OWN key order — upstream's writing order
          # (Sifra interleaves "Chapter n"/"Section n"; schema lookup or
          # sorting would misorder).
          walk_nodes(value, value.keys, indices, language, path, &block)
        else
          reject_leaf(value, indices, path)
        end
      end

      # One schema-node dict level, top or nested. The P55-3 default-node
      # rule holds at every depth: enTitle "" (the Rabbah shape — Petichta
      # + "") cites bare, an empty slug adds NO prefix segment. Sibling
      # keys the FROZEN slug fold collapses ("Chapter 2" beside Silverstein
      # Sifra's variant "Chapter 2*") disambiguate by walk order — the
      # second same-slugged sibling mints "-2" (the DSS twin-scroll
      # precedent); safe to add because a colliding document could never
      # have synced before this rule (duplicate urns are a ParseError).
      def walk_nodes(dict, keys, indices, language, path, &block)
        minted = Hash.new(0)
        keys.each do |key|
          prefix = self.class.slug(key)
          minted[prefix] += 1 unless prefix.empty?
          prefix = "#{prefix}-#{minted[prefix]}" if minted[prefix] > 1
          walk(dict.fetch(key), prefix.empty? ? indices : indices + [prefix], language, path, &block)
        end
      end

      def reject_leaf(value, indices, path)
        raise ParseError, "#{path}: text leaf at #{indices.join('.')} must be a String or Array, " \
                          "got #{value.class}"
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
