# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "oudfries-tei": the Corpus Oudfries witness files
    # (INT/IvdNT v1.0, Rita van de Poel's lemmatised + PoS-tagged Old
    # Frisian corpus). One file = one text witness — one text as one
    # manuscript transmits it.
    #
    # == The layout (censused over all 177 files, 2026-10-27)
    #
    #   <TEI><teiHeader xmlns="…tei…">          (only the header is namespaced)
    #     …<listBibl id="inlMetadata"><bibl>
    #        <interpGrp type="manuscript_region"><interp>Emsingo</interp></interpGrp>
    #        …                                   (20 typed groups, some <interp/>)
    #   </teiHeader><text><body><div>
    #     <l n="5:18">                           the edition's line (n on 6,638 of
    #       <w lemma="thî" type="DET" gloss="de, die">Thi</w>    14,154; NOT unique —
    #       <pc type="post">.</pc>               duplicated in 22 files)
    #     </l>
    #
    # The header's interpGrp/interp pairs become a flat metadata Hash
    # (type → value), empty interps dropped. Each <l> becomes one line:
    # text = the reading with punctuation re-joined by its own @type —
    # "post" (27,331) glues to the preceding word, "pre" (394) to the
    # following word, "floating" (53) stands alone — and one token per <w>
    # carrying form, lemma (verbatim, homonym suffixes like "forma_2" and
    # portmanteau joins like "hiat_hit" included), pos (@type) and gloss.
    # A blank lemma/type (numerals: lemma="" type="") carries no claim; the
    # token is form-only. @multiw marks a multiword unit ("multiword" true).
    #
    # Lines carry a dense 1-based seq (the citation the adapter mints) and
    # the edition's @n when present. A line with no <w> (16 lines holding
    # only a full stop, 2 empty <l/>) is no passage: skipped and counted.
    #
    # Upstream's one mis-nested line (E1-Bro: <l n="5:16"> opened inside
    # <l n="5:15">) is read as the bytes run: a nested <l> START closes the
    # line in progress and opens its own, and only the OUTERMOST </l> closes
    # — the tokens after the inner </l> ("londriuchte.") finish the inner
    # line's sentence, so they stay with it.
    #
    # Streaming (Nokogiri::XML::Reader): Ro-JF.exported.xml is 6.4 MB.
    class OudfriesTeiParser
      Text = Data.define(:meta, :lines, :skipped_lines)
      Line = Data.define(:seq, :n, :text, :tokens)

      ELEMENT = Nokogiri::XML::Reader::TYPE_ELEMENT
      END_ELEMENT = Nokogiri::XML::Reader::TYPE_END_ELEMENT
      CHARACTERS = [Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA,
                    Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE,
                    Nokogiri::XML::Reader::TYPE_WHITESPACE].freeze
      private_constant :ELEMENT, :END_ELEMENT, :CHARACTERS

      # Parse one witness from an XML String; +name+ is for error messages.
      def text(xml, name:)
        @name = name
        reset
        Nokogiri::XML::Reader(xml).each { |node| visit(node) }
        raise ParseError, "#{name}: unclosed <l> at end of file" if @depth.positive?

        Text.new(meta: @meta, lines: @lines, skipped_lines: @skipped)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{name}: malformed Oudfries TEI: #{e.message}"
      end

      private

      def reset
        @meta = {}
        @lines = []
        @skipped = 0
        @depth = 0
        @segment = nil
        @group = nil
        @capture = nil
      end

      def visit(node)
        case node.node_type
        when ELEMENT then open_element(node)
        when END_ELEMENT then close_element(node.local_name)
        else
          @capture[:buffer] << node.value.to_s if @capture && CHARACTERS.include?(node.node_type)
        end
      end

      def open_element(node)
        case node.local_name
        when "interpGrp" then @group = node.attribute("type")
        when "interp" then start_capture(:interp, node)
        when "l" then open_line(node)
        when "w", "pc" then start_capture(node.local_name.to_sym, node)
        end
      end

      def close_element(local_name)
        case local_name
        when "interp" then finish_interp if @capture&.fetch(:kind) == :interp
        when "w" then finish_word if @capture&.fetch(:kind) == :w
        when "pc" then finish_punct if @capture&.fetch(:kind) == :pc
        when "l" then close_line
        end
      end

      # An empty element (<interp/>, <w/>) has no END node and no text.
      def start_capture(kind, node)
        return if node.empty_element?

        attrs = %w[type lemma gloss multiw].to_h { |a| [a, node.attribute(a)] }
        @capture = { kind: kind, attrs: attrs, buffer: +"" }
      end

      def finish_interp
        value = clean(@capture[:buffer])
        @meta[@group] = value if @group && !value.empty? && !@meta.key?(@group)
        @capture = nil
      end

      def finish_word
        attrs = @capture[:attrs]
        form = clean(@capture[:buffer])
        @capture = nil
        return if form.empty?

        token = { "form" => form }
        { "lemma" => "lemma", "pos" => "type", "gloss" => "gloss" }.each do |key, attr|
          value = clean(attrs[attr].to_s)
          token[key] = value unless value.empty?
        end
        token["multiword"] = true if attrs["multiw"]
        current_segment.fetch(:tokens) << token
        current_segment.fetch(:pieces) << [:word, form]
      end

      GLUES = { "post" => :post, "pre" => :pre }.freeze
      private_constant :GLUES

      # Punctuation is reading text, never a token; any type other than
      # post/pre (upstream's "floating") stands alone.
      def finish_punct
        mark = clean(@capture[:buffer])
        glue = GLUES.fetch(@capture[:attrs]["type"], :floating)
        @capture = nil
        current_segment.fetch(:pieces) << [glue, mark] unless mark.empty?
      end

      def open_line(node)
        flush
        @segment = { n: node.attribute("n"), tokens: [], pieces: [] }
        if node.empty_element?
          flush
        else
          @depth += 1
        end
      end

      def close_line
        @depth -= 1
        flush if @depth.zero?
      end

      def current_segment
        @segment or raise ParseError, "#{@name}: a <w>/<pc> outside any <l>"
      end

      def flush
        segment = @segment
        @segment = nil
        return if segment.nil?

        if segment[:tokens].empty?
          @skipped += 1
          return
        end

        n = segment[:n].to_s.strip
        @lines << Line.new(seq: @lines.size + 1, n: n.empty? ? nil : n,
                           text: reading(segment[:pieces]), tokens: segment[:tokens])
      end

      def reading(pieces)
        out = +""
        pending = +""
        pieces.each do |kind, value|
          case kind
          when :word
            out = join(out, pending + value)
            pending = +""
          when :post then out << value
          when :pre then pending << value
          else out = join(out, value)
          end
        end
        join(out, pending)
      end

      def join(left, right)
        return left if right.empty?
        return +right if left.empty?

        "#{left} #{right}"
      end

      def clean(value)
        Nabu::Normalize.nfc(value.to_s.gsub(/\s+/, " ").strip)
      end
    end
  end
end
