# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "otdo-html" (P48-5): one critical edition page of Old
    # Tibetan Documents Online (otdo.aa-ken.jp) — a server-rendered HTML
    # page per document, Wylie transliteration at the edition's own line
    # grain. DOM-based: pages are 9–130 KB (census 2026-07-28), far under
    # the >5 MB Reader rule.
    #
    # == Page shape (census + fixture evidence)
    #
    #   <h2><slug></h2>                          the document's OTDO id
    #   <div><b>N. Label :</b> value</div>       numbered metadata fields —
    #     the field set varies by document kind (Content/Note on
    #     manuscripts; Content/Location/Date/Condition/Photos/References
    #     on inscriptions). Block-valued fields (References, Photos /
    #     Rubbings — bibliographic apparatus in FOLLOWING divs) carry no
    #     inline value and are dropped.
    #   <div class="textBody1">                  the transliteration:
    #     <span class="text-xs text-gray-400">(label) </span>text<br>
    #     one span-labelled run per line; labels are the edition's own
    #     numbering — plain "1"…"536" (Pt_1287), "r1"/"v2" recto-verso
    #     (Or.15000, OZ), "e1"/"n12"/"s3" inscription faces (Zhol).
    #
    # == Passage = the LINE, label-scoped
    #
    #   urn = <document-urn>:<label>   (urn:nabu:otdo:Pt_1287:1,
    #                                   urn:nabu:otdo:insc_Zhol:e1)
    #
    # Labels are unique per document in the census; a repeated label takes
    # the house :b2 disambiguator (the ReM/EDR precedent), and any
    # whitespace inside a label folds to dots (the oracc label rule).
    #
    # == Text policy — VERBATIM Wylie
    #
    # OTDO's transliteration conventions are the corpus (reversed gi-gu as
    # capital I, editorial brackets [---]/[']/(x/y), $ head marks, / shad):
    # the line's visible text is kept byte-verbatim modulo whitespace
    # folding and the NFC boundary. The site's tooltip glosses
    # (<span class="tooltip">bgyisna<span class="tooltip-content">bgyis
    # na</span></span> — OTDO's own normalized re-segmentation of the
    # surface form) keep the SURFACE form in the text; the gloss rides the
    # line's annotations as {"readings" => [{"surface", "reading"}]} —
    # never spliced into the text, canonical means canonical.
    #
    # A line with no letter or digit in any script once read (a pure
    # lacuna) is not citable and mints no passage. A page whose text block
    # is missing, or parses to ZERO citable lines, raises ValidationError —
    # every catalogued document carries a transliteration in the census
    # (all 414 catalog rows have the text checkbox), so absence means the
    # page shape drifted, and that must stay loud (quarantine), never a
    # silent empty document.
    #
    # == Language
    #
    # Old Tibetan, ISO 639-3 "otb" (the P48 registry convention) — except
    # the five OZ_* documents, which OTDO's own catalog and editions
    # describe as Old Zhangzhung ("a medical text in Old Zhangzhung
    # language") → ISO 639-3 "xzh" (Zhangzhung).
    #
    # == Header → Document#metadata
    #
    #   title = the "Content" field verbatim; metadata keeps the inline
    #   fields ("content", "note", "location", "date_text", "condition" —
    #   only those present, honest sparsity) plus OTDO's own categorization:
    #   "category" ("inscription" for insc_*, else "manuscript") and, for
    #   manuscripts, "pressmark" (the slug de-underscored — "Pt 1287",
    #   "ITJ 0750", OTDO's own sigla). Dating is FREE TEXT ("post 763",
    #   "9th c.") → date_text, never a structured claim.
    class OtdoHtmlParser
      URN_PREFIX = "urn:nabu:otdo:"

      # Old Tibetan (ISO 639-3); the P48 registry convention.
      DEFAULT_LANGUAGE = "otb"

      # The OZ_* documents — OTDO's Old Zhangzhung texts (ISO 639-3 xzh).
      ZHANGZHUNG_LANGUAGE = "xzh"
      ZHANGZHUNG_PREFIX = "OZ_"

      INSCRIPTION_PREFIX = "insc_"

      # Inline metadata fields captured (downcased, de-spaced); block-valued
      # apparatus fields (References, Photos / Rubbings) are dropped.
      FIELD_KEYS = {
        "content" => "content",
        "note" => "note",
        "location" => "location",
        "date" => "date_text",
        "condition" => "condition"
      }.freeze

      LABEL_SPAN_CSS = "span.text-xs.text-gray-400"
      TEXT_BODY_CSS = "div.textBody1"

      def parse(path, urn:)
        slug = expected_slug(urn)
        page = Nokogiri::HTML(File.read(path, encoding: Encoding::UTF_8))
        check_identity!(page, slug, path)
        fields = field_values(page)
        document = Nabu::Document.new(
          urn: urn, language: language_for(slug), canonical_path: path,
          title: title_for(fields), metadata: metadata_for(fields, slug)
        )
        append_lines!(document, page, urn)
        document
      end

      private

      def expected_slug(urn)
        unless urn.start_with?(URN_PREFIX)
          raise Nabu::ValidationError, "urn #{urn.inspect} does not carry the #{URN_PREFIX} prefix"
        end

        urn.delete_prefix(URN_PREFIX)
      end

      # The page's own <h2> header is the document id — drift between the
      # filename-minted urn and the served page quarantines.
      def check_identity!(page, slug, path)
        header = page.at_css("h2")&.text&.strip
        return if header == slug

        raise Nabu::ValidationError,
              "page header #{header.inspect} does not match the expected document id #{slug.inspect} " \
              "(#{path}) — the crawl landed a different page under this slug"
      end

      def language_for(slug)
        slug.start_with?(ZHANGZHUNG_PREFIX) ? ZHANGZHUNG_LANGUAGE : DEFAULT_LANGUAGE
      end

      def title_for(fields)
        value = fields["content"]
        value unless value.nil? || value.empty?
      end

      def metadata_for(fields, slug)
        metadata = {}
        fields.each do |label, value|
          key = FIELD_KEYS[label] or next
          metadata[key] = value unless value.empty?
        end
        metadata["category"] = slug.start_with?(INSCRIPTION_PREFIX) ? "inscription" : "manuscript"
        metadata["pressmark"] = slug.tr("_", " ") unless slug.start_with?(INSCRIPTION_PREFIX)
        metadata
      end

      # {"content" => "Old Tibetan Chronicle.", "date" => "post 763", …} —
      # each numbered <b>N. Label :</b> div whose value is inline (block-
      # valued apparatus fields yield "" and are skipped by the callers).
      def field_values(page)
        page.css("div > b").each_with_object({}) do |bold, fields|
          match = bold.text.match(/\A\s*\d+\.\s*(.+?)\s*:\s*\z/) or next
          label = match[1].downcase
          value = bold.parent.text.sub(bold.text, "").strip.gsub(/\s+/, " ")
          fields[label] = value
        end
      end

      # Walk the text block in document order: a label span opens a line,
      # <br> closes it, everything between accumulates as the line's text
      # (tooltip glosses diverted to annotations).
      def append_lines!(document, page, urn)
        body = page.at_css(TEXT_BODY_CSS)
        raise Nabu::ValidationError, "no #{TEXT_BODY_CSS} transliteration block — the page shape drifted" if body.nil?

        sequence = 0
        suffixes = Hash.new(0)
        each_line(body) do |label, text, readings|
          folded = Nabu::Normalize.nfc(text.gsub(/\s+/, " ").strip)
          next unless folded.match?(/[\p{L}\p{N}]/) # a pure lacuna is not citable

          annotations = { "line" => label }
          annotations["readings"] = readings unless readings.empty?
          document << Nabu::Passage.new(
            urn: "#{urn}:#{suffix_for(label, suffixes)}", language: document.language,
            text: folded, annotations: annotations, sequence: sequence
          )
          sequence += 1
        end
        return unless document.empty?

        raise Nabu::ValidationError,
              "zero citable transliteration lines — every catalogued OTDO document carries text " \
              "(census 2026-07-28), so this page's shape drifted"
      end

      # Yields [label, raw_text, readings] per labelled line.
      def each_line(body)
        label = nil
        buffer = +""
        readings = []
        body.children.each do |node|
          if (opened = line_label(node))
            yield(label, buffer, readings) if label
            label = opened
            buffer = +""
            readings = []
          elsif node.name == "br"
            yield(label, buffer, readings) if label
            label = nil
          elsif label
            buffer << node_text(node, readings)
          end
        end
        yield(label, buffer, readings) if label
      end

      # "(e1) " in the census's label span; nil for every other node.
      def line_label(node)
        return nil unless node.element? && node.name == "span" &&
                          node.matches?(LABEL_SPAN_CSS)

        node.text.match(/\A\s*\(([^)]+)\)\s*\z/)&.captures&.first
      end

      # A node's visible text: tooltip spans contribute their SURFACE form;
      # the gloss (tooltip-content) rides +readings+, never the text. Works
      # on a deep copy so gloss removal never mutates the parsed page.
      def node_text(node, readings)
        return node.text unless node.element?

        fragment = node.dup
        fragment.css("span.tooltip-content").each do |gloss|
          surface = gloss.parent
          reading = gloss.text.strip
          gloss.remove
          readings << { "surface" => surface.text.strip, "reading" => reading }
        end
        fragment.text
      end

      # Whitespace in a label folds to dots (the oracc rule); a repeated
      # label takes :b2, :b3 … (the ReM/EDR precedent).
      def suffix_for(label, suffixes)
        base = label.strip.gsub(/\s+/, ".")
        suffixes[base] += 1
        count = suffixes[base]
        count == 1 ? base : "#{base}:b#{count}"
      end
    end
  end
end
