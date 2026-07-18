# frozen_string_literal: true

module Nabu
  module Adapters
    # The wiki-template parser family (P29-3): Semantic-MediaWiki wikitext
    # as the Vienna wiki pair writes it (lexlep.univie.ac.at Lexicon
    # Leponticum / tir.univie.ac.at Thesaurus Inscriptionum Raeticarum —
    # MediaWiki 1.38 + SMW, identical machinery, censused 2026-07-18 via
    # api.php over 200+ pages of every entity category). One page = one
    # entity template block ({{inscription…}}, {{object…}}, {{site…}},
    # {{word…}}) followed by prose sections ("== Commentary ==",
    # {{bibliography}}). This class knows the SHAPES; the adapters decide
    # what they mean.
    #
    # == The reading grammar (the censused facts, none invented)
    #
    # The inscription template's +reading+ holds the transliterated text:
    # - lines are separated by " / " (BI·4 "esonius : urenti / akitu …");
    # - tokens by whitespace; a token "A!B" renders B — the diacritic-marked
    #   scholarly form with combining U+0323 under-dots and &#91;/&#93;
    #   brackets — while A is the wiki's Word-page link form (BI·8
    #   "koilios!koil&#91;": fragment koil[ links the word page koilios;
    #   verified against the wiki's own HTML rendering of AK-1.1/BI·8);
    # - the literal token "space" is the word-divider marker (renders as a
    #   gap); "unknown" as a WHOLE reading (or line) means no reading;
    #   an "unknown" link form beside a real display form (AK-1.10
    #   "unknown!k&#x0323;…") is not a word link;
    # - numeric character references and &nbsp; decode; a display token
    #   that decodes to whitespace only is dropped.
    #
    # Decoded text is NOT normalized here — NFC happens at the adapter
    # boundary (house rule), so the raw forms stay inspectable.
    class WikiTemplateParser
      # One reading line: +text+ = the rendered scholarly transliteration,
      # +words+ = the Word-page link forms riding the line's tokens (the
      # lexicon join surface, deduplicated nothing — order preserved).
      ReadingLine = Data.define(:text, :words)

      # The word-divider marker and the no-reading vocabulary (censused).
      SPACE_TOKEN = "space"
      UNKNOWN = "unknown"

      # Inline entity templates flattened by #plain: {{bib|X}}/{{bib|X|Y}},
      # {{m|morpheme}}/{{m|link|display}}, {{w|word}}/{{w||word}}, {{p|a}},
      # {{c|A|…}} — the LAST non-empty positional argument is the display
      # form (named arguments are configuration, never prose).
      TEMPLATE = /\{\{([^{}]*)\}\}/m

      # -- template blocks -----------------------------------------------------

      # The named entity template's parameters as a Hash (values verbatim
      # wikitext, nested inline templates kept), or nil when the page does
      # not carry the template. Params are one-per-line ("\n|key=value" —
      # the censused shape on every sampled page); the block is found by
      # brace balance so nested {{c|…}} calls never truncate it.
      def template_params(wikitext, name)
        block = template_block(wikitext, name) or return nil

        # The closing braces sit on their own line (the censused shape);
        # dropping them at the BLOCK level keeps a value that itself ends
        # in a nested template ("{{p|a}}{{p|e}}{{p|s}}") intact.
        body = block.sub(/\s*\}\}\z/, "")
        params = {}
        body.split("\n|").drop(1).each do |fragment|
          key, _, value = fragment.partition("=")
          next if key.strip.empty? || !fragment.include?("=")

          params[key.strip] = value.strip
        end
        params
      end

      # -- the reading grammar -------------------------------------------------

      # The reading parameter parsed into ReadingLines (class note). An
      # unknown/empty reading yields [] — the honest no-text answer the
      # adapters turn into a metadata-only document.
      def reading_lines(raw)
        return [] if raw.nil?

        raw.split(%r{\s+/\s+}).filter_map do |line|
          parse_reading_line(line)
        end
      end

      # -- prose ---------------------------------------------------------------

      # Wikitext prose flattened to plain text: inline templates reduced to
      # their display argument, [[link|label]]/[[link]] to the label,
      # ''italics'' unwrapped, HTML tags dropped, entities decoded.
      # Whitespace is collapsed per line group; blank-line structure kept.
      def plain(wikitext)
        text = wikitext.to_s.dup
        text.gsub!(TEMPLATE) { template_display(Regexp.last_match(1)) }
        # A second pass unwraps templates that contained only templates.
        text.gsub!(TEMPLATE) { template_display(Regexp.last_match(1)) }
        text.gsub!(/\[\[([^\]|]*)\|([^\]]*)\]\]/, '\2')
        text.gsub!(/\[\[([^\]]*)\]\]/, '\1')
        text.gsub!("''", "")
        text.gsub!(%r{</?[a-zA-Z][^>]*/?>}, "")
        decode_entities(text).split("\n").map(&:strip).join("\n").gsub(/\n{3,}/, "\n\n").strip
      end

      # The body of a "== Heading ==" section (raw wikitext, up to the next
      # heading or end of page); nil when absent. Tolerates the corpus's
      # own spacing drift ("== Commentary==").
      def section(wikitext, heading)
        match = wikitext.to_s.match(/^==\s*#{Regexp.escape(heading)}\s*==\s*\n(.*?)(?=^==[^=]|\z)/m)
        match && match[1].strip
      end

      # Numeric character references and the few named entities the corpus
      # uses (&#91; &#93; &#x0323; &nbsp; &amp;), decoded.
      def decode_entities(text)
        text.gsub(/&#x([0-9a-fA-F]+);/) { [Regexp.last_match(1).hex].pack("U") }
            .gsub(/&#(\d+);/) { [Regexp.last_match(1).to_i].pack("U") }
            .gsub("&nbsp;", " ")
            .gsub("&amp;", "&")
      end

      private

      # The balanced "{{name …}}" block's inner text, or nil.
      def template_block(wikitext, name)
        start = wikitext =~ /\{\{#{Regexp.escape(name)}\s*[\n|]/ or return nil

        depth = 0
        scanner = wikitext[start..]
        scanner.scan(/\{\{|\}\}/) do |braces|
          depth += braces == "{{" ? 1 : -1
          return scanner[0...Regexp.last_match.end(0)] if depth.zero?
        end
        nil
      end

      # One "A!B" (or bare) token's [display, word-link] pair; the line's
      # text joins displays with single spaces.
      def parse_reading_line(line)
        texts = []
        words = []
        line.split(/\s+/).each do |token|
          next if token.empty? || token == SPACE_TOKEN

          link, bang, display = token.partition("!")
          display = link if bang.empty?
          display = decode_entities(display)
          next if display.gsub(/[\s\u00A0]/, "").empty?

          texts << display
          words << link if word_link?(link)
        end
        text = texts.join(" ")
        return nil if text.empty? || text == UNKNOWN

        ReadingLine.new(text: text, words: words)
      end

      # Every reading token links its Word page — bare tokens by their own
      # form, "A!B" tokens by A. "unknown" and letterless markers ("?",
      # "$", "§") are notation, not words.
      def word_link?(link)
        !link.empty? && link != UNKNOWN && link.match?(/[[:alpha:]]/)
      end

      # An inline template's display form: the last non-empty positional
      # argument ({{bib|Morandi 2004|2004}} → "2004", {{w||aχvil}} →
      # "aχvil", {{m|akis-}} → "akis-"); named-argument-only blocks
      # ({{sig|user=…}}, {{bibliography}}) flatten to nothing.
      def template_display(inner)
        args = inner.split("|").drop(1).reject { |arg| arg.include?("=") || arg.strip.empty? }
        args.empty? ? "" : args.last.strip
      end
    end
  end
end
