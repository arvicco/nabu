# frozen_string_literal: true

require "cgi"
require "nokogiri"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Språkbanken Karp LMF parser family: a LexicalResource/Lexicon of
    # <LexicalEntry> records whose every datum is a <feat att= val=> pair —
    # the shape Språkbanken (University of Gothenburg) publishes its
    # historical Swedish dictionaries in (Söderwall, Söderwall's
    # supplement, Schlyter: the fsv-lexica shelves). Streamed with
    # Nokogiri::XML::Reader (the files run to 24 MB — the no-DOM-over-5MB
    # rule), one small DOM per entry.
    #
    # Per LexicalEntry, one DictionaryEntry:
    #
    # - entry_id / key_raw: the Lemma's lemgram verbatim
    #   ("fsvm--avisning..nn.1") — unique per file at census, and the SAME
    #   key across the three dictionaries (Söderwall and Schlyter share
    #   fsvm--avisning..nn.1), the Karp morphology's lemma id.
    # - headword: the lemgram's baseform (between "--" and ".."), "_" read
    #   as a space, whitespace collapsed. Deliberately NOT the printed
    #   writtenForm: upstream keyed the books by hand and its writtenForm
    #   carries the printed head line's grammar and, in some entries, the
    #   whole first sentence (census: the baseform differs from the
    #   writtenForm in 109 Söderwall / 311 supplement / 9 Schlyter
    #   entries — "argha  v fördefva försämra. skulum wy …"). The
    #   writtenForm stays verbatim as the body's first line.
    # - body: line 1 the printed head (writtenForm, hwtext, gram,
    #   information); one line per <WordForm> (its feat values joined
    #   " · " — the attested forms, whatever att upstream filed them
    #   under: writtenForm, gram, variant, or a morphosyntactic tag such as
    #   V0IPA**); one line per <Sense> (its own feat values, then its
    #   Definition texts). Whitespace collapsed; HTML entities decoded
    #   (upstream double-escapes quotation marks as &amp;quot;); NFC.
    # - gloss: the first non-empty Definition text, leading punctuation
    #   dropped, cut at its first ". " or ";" (the print's sense prose ends
    #   there and the source sigla begin), trailing punctuation trimmed,
    #   at most GLOSS_MAX characters; nil when no definition exists. Best
    #   effort: a definition opening with an abbreviation ("pres. ind.
    #   sing. af ägha") glosses as the abbreviation.
    # - annotations: {"pos" => [...]} — the Karp partOfSpeech tags
    #   verbatim (nn, vb, av, ab, pp …), when the entry carries any.
    #
    # Deliberately unmined (declared): the "se detta ord"/"Jfr" cross
    # references and the source sigla stay in the body as printed text
    # (no held resolution target; the abbreviations are the book's own).
    class SpraakbankenLmfParser
      ENTRY = "LexicalEntry"
      LEMGRAM = /\A[^-]+--(?<base>.+)\.\.[^.]*\.\d+\z/
      HEAD_ATTS = %w[writtenForm hwtext gram information].freeze
      GLOSS_MAX = 100
      private_constant :ENTRY, :LEMGRAM, :HEAD_ATTS, :GLOSS_MAX

      def initialize(language:)
        @language = language
      end

      def entries(path)
        collected = []
        xml = SourceRead.utf8_file(path, label: "spraakbanken-lmf")
        Nokogiri::XML::Reader(xml, path).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == ENTRY

          collected << build(Nokogiri::XML(node.outer_xml, &:strict).root, path)
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "spraakbanken-lmf: malformed XML in #{path}: #{e.message}"
      end

      private

      def build(elem, path)
        form = elem.at_xpath("Lemma/FormRepresentation")
        lemgram = form && feat(form, "lemgram").first
        raise Nabu::ParseError, "spraakbanken-lmf: #{path}: entry without a lemgram" if lemgram.nil?

        headword = headword(lemgram, path)
        Nabu::DictionaryEntry.new(
          entry_id: lemgram, key_raw: lemgram, language: @language,
          headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: @language),
          gloss: gloss(elem),
          body: body(elem, form, headword),
          annotations: annotations(form)
        )
      end

      def headword(lemgram, path)
        match = LEMGRAM.match(lemgram)
        raise Nabu::ParseError, "spraakbanken-lmf: #{path}: unreadable lemgram #{lemgram.inspect}" unless match

        base = plain(match[:base].tr("_", " "))
        raise Nabu::ParseError, "spraakbanken-lmf: #{path}: empty lemgram baseform #{lemgram.inspect}" if base.empty?

        base
      end

      def body(elem, form, headword)
        head = HEAD_ATTS.flat_map { |att| feat(form, att) }.map { |v| plain(v) }.reject(&:empty?).join(" ")
        lines = [head.empty? ? headword : head]
        elem.xpath("WordForm").each do |wordform|
          line = wordform.xpath("feat").map { |f| plain(f["val"]) }.reject(&:empty?).join(" · ")
          lines << line unless line.empty?
        end
        elem.xpath("Sense").each do |sense|
          parts = sense.xpath("feat") + sense.xpath("Definition/feat[@att='text']")
          line = parts.map { |f| plain(f["val"]) }.reject(&:empty?).join(" ")
          lines << line unless line.empty?
        end
        lines.join("\n")
      end

      def gloss(elem)
        definitions = elem.xpath("Sense/Definition/feat[@att='text']").map { |f| plain(f["val"]) }
        text = definitions.find { |t| t.match?(/\p{L}/) }
        return nil unless text

        cut = text.sub(/\A[\s\p{P}]+/, "").split(/\.\s|;/, 2).first.to_s.sub(/[\s\p{P}]+\z/, "")
        cut = "#{cut[0, GLOSS_MAX].sub(/\s+\S*\z/, '')}…" if cut.length > GLOSS_MAX
        cut.match?(/\p{L}/) ? cut : nil
      end

      def annotations(form)
        pos = feat(form, "partOfSpeech").map(&:strip).reject(&:empty?).uniq
        pos.empty? ? {} : { "pos" => pos }
      end

      def feat(node, att) = node.xpath("feat[@att='#{att}']").map { |f| f["val"].to_s }

      def plain(value)
        Nabu::Normalize.nfc(CGI.unescapeHTML(value.to_s).gsub(/\s+/, " ").strip)
      end
    end
  end
end
