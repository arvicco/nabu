# frozen_string_literal: true

require "cgi"

module Nabu
  module Adapters
    # The bim-tsv parser family: the token streams of the BIM/SAHCOBA
    # historical Basque corpus (HiTZ, University of the Basque Country;
    # BZENTROA-BIM.zip, 2026-06-17 deposit). One file per work, one token
    # per line, five TAB-separated columns and nothing else — no header,
    # no blank lines, no sentence or document boundaries (census of all 15
    # files, 669,109 lines):
    #
    #   form · standardized form · lemma · Basque POS (EUS tagset) · UPOS
    #   kausa   kausa   kausa   IZE   NOUN
    #   daiteiela   daitekeela   *edin   ADT   VERB
    #
    # The export XML-escaped its specials (&lt; &gt; &quot; &amp; &apos;,
    # 9,286 tokens) — decoded here at the boundary (an encoding layer, not
    # a text edit). Lemma and POS are machine output (the files are named
    # *_automatikoa, "automatic"); 67,709 tokens carry UPOS X with an empty
    # lemma — the stretches the tagger left alone (Axular's Latin
    # quotations and his marginal references above all) — and stay
    # lemma-less, honestly.
    #
    # == Markup that survived as tokens (censused)
    #
    # The texts were tokenized from a marked-up source, so a few tags ride
    # the stream as token runs:
    #   < N >          one token (or two: "I 17") between single brackets —
    #                  the page of the printed or manuscript source (Axular
    #                  3–621, Belapeire I 17 … II 135, Beriain 6v–126v,
    #                  Lazarraga 1142r–1201r …); 11 of 15 works carry them
    #   < lat > … < / lat >    a Latin span (Beriain)
    #   < gap > … < / gap >    a span outside the Basque text proper
    #                          (Materra's French dedication, Larramendi's
    #                          editorial elisions)
    #   < text > / < / text >  the source's text-division boundary
    #   < < … > >      doubled brackets: the corpus's quotation marks
    #
    # == The passage grain (the declared rule — the stream has none)
    #
    # A work whose stream carries page markers is cut at them: one Unit per
    # source page, cited p.<label> (non-alphanumerics → "_": "I 17" →
    # p.I_17, "126v" → p.126v); tokens before the first marker are "front";
    # a repeated label (Axular's 585, Lazarraga's re-foliated 1151r …) takes
    # the house :b2 suffix in document order. A work with NO page markers
    # (Chourio, Etxepare, Larramendi, Leizarraga, Maister, Pouvreau) is cut
    # into sentences: a Unit closes after a PUNCT token . ? or ! (any
    # immediately following > > or closing bracket stays with it), cited
    # s.<n> from 1. The sentence rule over-splits at abbreviation periods
    # ("M . Dcc . Lx .") — declared, the stream gives nothing better.
    #
    # Text: tokens joined by single spaces, punctuation glued to the word
    # before it (, . ; : ? ! ) ] > >), opening brackets to the word after
    # (( [ < <); the markup tags never reach the text. Annotations: the
    # token list ("tokens": form, norm when it differs, lemma, upos, xpos),
    # "latin" / "gaps" spans when a tagged span falls in the unit, and
    # "page" (the raw page label) on paged units.
    class BimTsvParser
      Unit = Data.define(:citation, :text, :annotations)

      COLUMNS = 5
      SENTENCE_END = [".", "?", "!"].freeze
      GLUE_LEFT = [",", ".", ";", ":", "?", "!", ")", "]", ">>"].freeze
      GLUE_RIGHT = ["(", "[", "<<"].freeze
      CLOSERS = [">>", ")", "]"].freeze
      TAGS = { "lat" => "latin", "gap" => "gaps", "text" => nil }.freeze

      # +text+ is one whole TSV file. Returns the Units in stream order.
      def units(text, label:)
        tokens = read_tokens(text, label)
        stream = events(tokens)
        cut = stream.any? { |event| event[:kind] == :page } ? method(:by_page) : method(:by_sentence)
        disambiguate(cut.call(stream).map { |unit| finish(unit) }.compact)
      end

      private

      Token = Data.define(:form, :norm, :lemma, :xpos, :upos)
      private_constant :Token

      def read_tokens(text, label)
        text.each_line.with_index(1).map do |line, number|
          cells = line.chomp.split("\t", -1)
          unless cells.size == COLUMNS
            raise Nabu::ParseError, "#{label}:#{number}: expected #{COLUMNS} TAB columns, got #{cells.size}"
          end

          form, norm, lemma, xpos, upos = cells.map { |cell| CGI.unescapeHTML(cell) }
          Token.new(form: form, norm: norm, lemma: lemma, xpos: xpos, upos: upos)
        end
      end

      # The token stream → events: {kind: :token, token:}, {kind: :page,
      # label:}, {kind: :open/:close, tag:}. Doubled brackets fold into one
      # "<<" / ">>" token.
      def events(tokens)
        out = []
        index = 0
        while index < tokens.size
          token = tokens[index]
          if token.form == "<" && tokens[index + 1]&.form == "<"
            out << { kind: :token, token: token.with(form: "<<", norm: "<<", lemma: "<<") }
            index += 2
          elsif token.form == ">" && tokens[index + 1]&.form == ">"
            out << { kind: :token, token: token.with(form: ">>", norm: ">>", lemma: ">>") }
            index += 2
          elsif token.form == "<" && (markup = markup_at(tokens, index))
            out << markup[:event]
            index = markup[:next]
          else
            out << { kind: :token, token: token }
            index += 1
          end
        end
        out
      end

      # A single-bracket group "< x [y] >" (at most two inner tokens) at
      # +index+, or nil when no ">" closes it in reach (then "<" is text).
      def markup_at(tokens, index)
        close = ((index + 1)..(index + 3)).find { |at| tokens[at]&.form == ">" } or return nil
        inner = tokens[(index + 1)...close].map(&:form)
        return nil if inner.empty?

        event = if inner.first == "/" && inner.size == 2 && TAGS.key?(inner.last)
                  { kind: :close, tag: inner.last }
                elsif inner.size == 1 && TAGS.key?(inner.first)
                  { kind: :open, tag: inner.first }
                else
                  { kind: :page, label: inner.join(" ") }
                end
        { event: event, next: close + 1 }
      end

      def by_page(stream)
        units = [new_unit("front")]
        walk(stream) do |event, open_tags|
          if event[:kind] == :page
            unit = new_unit("p.#{event[:label].gsub(/[^0-9A-Za-z]+/, '_')}")
            unit[:annotations]["page"] = event[:label]
            units << unit
          else
            add(units.last, event[:token], open_tags)
          end
        end
        units
      end

      def by_sentence(stream)
        units = [new_unit("s.1")]
        closing = false
        walk(stream) do |event, open_tags|
          token = event[:token]
          if closing && !CLOSERS.include?(token.form)
            units << new_unit("s.#{units.size + 1}")
            closing = false
          end
          add(units.last, token, open_tags)
          closing = true if token.upos == "PUNCT" && SENTENCE_END.include?(token.form)
        end
        units
      end

      # Yields token and page events with the open tag set; tag events only
      # move the set.
      def walk(stream)
        open_tags = []
        stream.each do |event|
          case event[:kind]
          when :open then open_tags << event[:tag]
          when :close then open_tags.delete_at(open_tags.rindex(event[:tag]) || open_tags.size)
          else yield event, open_tags
          end
        end
      end

      def new_unit(citation)
        { citation: citation, forms: [], tokens: [], spans: Hash.new { |h, k| h[k] = [] }, annotations: {} }
      end

      def add(unit, token, open_tags)
        unit[:forms] << token.form
        entry = { "form" => token.form }
        entry["norm"] = token.norm unless token.norm.empty? || token.norm == token.form
        entry["lemma"] = token.lemma unless token.lemma.empty?
        entry["upos"] = token.upos unless token.upos.empty?
        entry["xpos"] = token.xpos unless token.xpos.empty?
        unit[:tokens] << entry
        open_tags.uniq.each do |tag|
          key = TAGS[tag] or next
          unit[:spans][key] << (unit[:forms].size - 1)
        end
      end

      def finish(unit)
        return nil if unit[:forms].empty?

        text = render(unit[:forms])
        annotations = unit[:annotations]
        annotations["tokens"] = unit[:tokens].map { |entry| entry.transform_values { |v| Normalize.nfc(v) } }
        unit[:spans].each { |key, positions| annotations[key] = spans(unit[:forms], positions) }
        Unit.new(citation: unit[:citation], text: Normalize.nfc(text), annotations: annotations)
      end

      # Contiguous runs of token positions → their rendered strings.
      def spans(forms, positions)
        positions.slice_when { |a, b| b != a + 1 }.map { |run| Normalize.nfc(render(forms.values_at(*run))) }
      end

      def render(forms)
        out = +""
        glue_next = true
        forms.each do |form|
          out << " " unless glue_next || GLUE_LEFT.include?(form)
          out << form
          glue_next = GLUE_RIGHT.include?(form)
        end
        out.strip
      end

      def disambiguate(units)
        seen = Hash.new(0)
        units.map do |unit|
          seen[unit.citation] += 1
          count = seen[unit.citation]
          count == 1 ? unit : unit.with(citation: "#{unit.citation}:b#{count}")
        end
      end
    end
  end
end
