# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for Språkbanken's Sparv corpus XML (P77-6) — the sparv
    # family, first registrant Fornsvenska textbanken: <corpus> →
    # <text title date datefrom dateto> → <paragraph> → <sentence id> →
    # <w> tokens. The files ship bzip2-compressed and a part decompresses
    # to tens of MB, so this is SAX over the decompressed stream (the
    # house >5 MB rule), one pass per part yielding every text.
    #
    # Sentence text = the <w> element texts joined by single spaces —
    # upstream is tokenized (punctuation stands alone); the rejoin is the
    # honest rendering of a token stream with no layout layer. The <w>
    # ATTRIBUTES (posset/lemma/lex/variants — automatic fsvm
    # morphology-lexicon candidate sets, often multi-valued) are
    # deliberately NOT carried in v1: a candidate set is not attestation.
    #
    # Citation = <paragraph ordinal>.<sentence ordinal within the
    # paragraph> (upstream's sentence @id is an opaque hex pair — carried
    # verbatim as the "sentence_id" annotation, never minted from).
    class SparvParser
      # One parsed text: the attrs verbatim plus its sentences in order.
      Text = Data.define(:title, :date, :datefrom, :dateto, :sentences)
      Sentence = Data.define(:id, :citation, :text)

      # Parse one decompressed Sparv XML stream (an IO or a String) into
      # [Text, ...] in file order.
      def parse(io)
        handler = Handler.new
        Nokogiri::XML::SAX::Parser.new(handler).parse(io)
        raise ParseError, handler.defect if handler.defect

        handler.texts
      end

      # The SAX assembly: flat, regular, no recursion.
      class Handler < Nokogiri::XML::SAX::Document
        attr_reader :texts, :defect

        def initialize
          super
          @texts = []
          @text = nil
          @paragraph = 0
          @sentence_in_paragraph = 0
          @sentence = nil
          @token = nil
          @defect = nil
        end

        def start_element(name, attrs = [])
          return if @defect

          case name
          when "text" then start_text(attrs.to_h)
          when "paragraph"
            @paragraph += 1
            @sentence_in_paragraph = 0
          when "sentence" then start_sentence(attrs.to_h)
          when "w" then @token = +""
          end
        end

        def characters(string)
          @token << string if @token
        end

        def end_element(name)
          return if @defect

          case name
          when "w"
            token = @token.strip
            @token = nil
            @sentence[:tokens] << token if @sentence && !token.empty?
          when "sentence" then finish_sentence
          when "text" then finish_text
          end
        end

        private

        def start_text(attrs)
          @text = { "title" => attrs["title"], "date" => attrs["date"],
                    "datefrom" => attrs["datefrom"], "dateto" => attrs["dateto"],
                    sentences: [] }
          @paragraph = 0
        end

        def start_sentence(attrs)
          @sentence_in_paragraph += 1
          @sentence = { id: attrs["id"], citation: "#{@paragraph}.#{@sentence_in_paragraph}",
                        tokens: [] }
        end

        def finish_sentence
          sentence = @sentence
          @sentence = nil
          return unless sentence && !sentence[:tokens].empty?

          @text[:sentences] << Sentence.new(id: sentence[:id], citation: sentence[:citation],
                                            text: sentence[:tokens].join(" "))
        end

        def finish_text
          text = @text
          @text = nil
          return unless text

          if text["title"].to_s.strip.empty?
            @defect = "a <text> without a title cannot mint a document"
            return
          end
          @texts << Text.new(title: text["title"], date: text["date"],
                             datefrom: text["datefrom"], dateto: text["dateto"],
                             sentences: text[:sentences])
        end
      end
    end
  end
end
