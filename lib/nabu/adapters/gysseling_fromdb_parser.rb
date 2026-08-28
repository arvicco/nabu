# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "gysseling-fromdb" (P84-7): the Corpus Gysseling .fromdb
    # coding scheme (INT/IvdNT) — the 13th-century originals that sourced the
    # Vroegmiddelnederlands Woordenboek, Early Middle Dutch (dum), lemma + POS
    # annotated. The format is documented in the corpus's own corpus_codering.txt.
    #
    # == The document scaffold (pseudo-tags, one per physical line)
    #
    #   <header> <docId>… <genre>… <bron><bron_afk>…<bron_oms>… </header>
    #   <datering jaar_van='1240' jaar_tot='1240' …>   dating region marker
    #   <lokalisering plaats_1='41' regio_1='9' …>     localisation marker
    #   <statushand statushandkode='mn'>               scribal-hand marker
    #   <L page:line> …tokens…                          a manuscript line
    #   <end-datering …> <end-lokalisering …> …         closing markers
    #
    # Most files are one charter with a single header block; a cartulary (e.g.
    # Corpus I, the Liber Traditionum) interleaves MANY datering/lokalisering
    # regions among the lines. So the document date-span is [min jaar_van,
    # max jaar_tot] over ALL <datering> markers, and the place is the first
    # <lokalisering>/<atlas_lokalisering> plaats_1 (resolved via plaats.txt).
    #
    # == A line's tokens (the coding, verbatim from corpus_codering.txt)
    #
    #   <C (tagnums)_(lemmata)> (token)   e.g. <C 810_DAT> dat
    #   <C 0+470_HOOFD+HET> thouet          a portmanteau: joined tags/lemmata
    #   des<A >er</A>                       an abbreviation expanded → "deser"
    #   <q> word                            non-Middle-Dutch (Latin) matrix text
    #   <VN type=1>                         an inline milestone (no token)
    #
    # Per the scheme's own reference perl: abbreviation <A>…</A> spans are
    # written out FIRST, then each <C …> token yields (form, tagnums, lemmata),
    # and a bare <q> word is foreign text. This parser keeps that exactly:
    # <A> expanded inline, <C> → a token carrying form + lemma (the CAPS
    # citation form, portmanteaux joined with '+' as upstream writes them) +
    # pos (the tag numbers, separable-word #/*/@ markers kept), and <q> → a
    # form-only FOREIGN token (no lemma, so the dum lemma index stays Dutch).
    # Anything else between angle brackets leaves no residue. The reading text
    # is the space-join of the token forms (Latin matrix included — the
    # diplomatic line); a line with no tokens is skipped.
    class GysselingFromdbParser
      Doc = Data.define(:doc_id, :genre, :bron_afk, :bron_oms, :not_before, :not_after,
                        :date_raw, :plaats_code, :regio_code, :place, :region, :lines)
      DocLine = Data.define(:page, :line, :suffix, :text, :tokens)

      # <A >…</A> abbreviation expansion (the content is written into the form).
      ABBR = %r{<A\s*>([^<]*)</A>}
      # A line: <L page:line> then the rest.
      LINE = /\A<L\s+(\d+):(\d+)>\s*(.*)\z/
      # A token: a <C tagnums_lemmata> form, OR a foreign <q> form.
      TOKEN = /<C\s+([0-9#*@+]+)_([^>]*)>\s*([^\s<]+)|<q>\s*([^\s<]+)/
      private_constant :ABBR, :LINE, :TOKEN

      def initialize(plaats: {}, regio: {})
        @plaats = plaats
        @regio = regio
      end

      # The corpus is a 1980s deposit: ~97% of the .fromdb files (and the code
      # tables) are ASCII, but ~3% carry Latin-1 accented bytes. Decode at the
      # boundary — UTF-8 when valid, ISO-8859-1 otherwise — never guess per byte.
      def self.decode(bytes)
        utf8 = bytes.dup.force_encoding(Encoding::UTF_8)
        utf8.valid_encoding? ? utf8 : bytes.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      end

      # Parse one .fromdb document from its (undecoded) bytes; +name+ is for
      # errors only.
      def document(bytes, name:) # rubocop:disable Lint/UnusedMethodArgument
        text = self.class.decode(bytes)

        plaats_code = first_attr(text, "lokalisering", "plaats_1") ||
                      first_attr(text, "atlas_lokalisering", "plaats_1")
        regio_code = first_attr(text, "lokalisering", "regio_1") ||
                     first_attr(text, "atlas_lokalisering", "regio_1")
        nb, na, raw = date_span(text)
        Doc.new(
          doc_id: tag_text(text, "docId"), genre: tag_text(text, "genre"),
          bron_afk: tag_text(text, "bron_afk"), bron_oms: tag_text(text, "bron_oms"),
          not_before: nb, not_after: na, date_raw: raw,
          plaats_code: plaats_code, regio_code: regio_code,
          place: @plaats[plaats_code], region: @regio[regio_code],
          lines: lines(text)
        )
      end

      private

      def lines(text)
        seen = Hash.new(0)
        text.each_line.filter_map do |physical|
          m = LINE.match(physical.chomp) or next

          page = m[1]
          line = m[2]
          tokens = tokenize(m[3])
          next if tokens.empty?

          suffix = uniquify("#{page}.#{line}", seen)
          DocLine.new(page: page, line: line, suffix: suffix,
                      text: reading_text(tokens), tokens: tokens)
        end
      end

      # A manuscript coordinate is normally unique per document; a cartulary
      # could in principle repeat one — append an occurrence tie-breaker so the
      # passage urn/sequence stay unique AND deterministic (document order).
      def uniquify(base, seen)
        seen[base] += 1
        seen[base] == 1 ? base : "#{base}.#{seen[base]}"
      end

      def tokenize(body)
        body = body.gsub(ABBR) { Regexp.last_match(1) }
        body.scan(TOKEN).map do |c_tags, c_lemma, c_form, q_form|
          if q_form
            { "form" => Nabu::Normalize.nfc(q_form), "foreign" => true }
          else
            token = { "form" => Nabu::Normalize.nfc(c_form), "lemma" => c_lemma.strip, "pos" => c_tags }
            token.delete("lemma") if token["lemma"].empty?
            token
          end
        end
      end

      def reading_text(tokens)
        Nabu::Normalize.nfc(tokens.map { |t| t["form"] }.join(" ").gsub(/\s+/, " ").strip)
      end

      # Min jaar_van / max jaar_tot over every <datering …> START marker
      # (never the mirrored <end-datering>).
      def date_span(text)
        vans = []
        tots = []
        text.scan(/<datering\s+([^>]*)>/) do |attrs|
          v = attr_value(attrs.first, "jaar_van")
          t = attr_value(attrs.first, "jaar_tot")
          vans << Integer(v, 10) if v && !v.empty?
          tots << Integer(t, 10) if t && !t.empty?
        end
        nb = vans.min
        na = tots.max
        raw = [nb, na].compact.uniq.join("-")
        [nb, na, (raw.empty? ? nil : raw)]
      end

      def first_attr(text, tag, attr)
        m = /<#{tag}\s+([^>]*)>/.match(text) or return nil

        v = attr_value(m[1], attr)
        v && !v.empty? ? v : nil
      end

      def attr_value(attrs, key)
        m = /\b#{key}\s*=\s*'([^']*)'/.match(attrs)
        m && m[1]
      end

      def tag_text(text, tag)
        m = %r{<#{tag}>([^<]*)</#{tag}>}.match(text) or return nil

        v = Nabu::Normalize.nfc(m[1].strip)
        v.empty? ? nil : v
      end
    end
  end
end
