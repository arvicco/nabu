# frozen_string_literal: true

require "strscan"

module Nabu
  module Adapters
    # The lila-ttl parser family (P18-6): a minimal Turtle-subset triple
    # reader for the CIRCSE/LiLa lexical-resource files — LIV.ttl (657 KB)
    # and BrillEDL.ttl (3.9 MB), nabu's first RDF inputs. Deliberately NOT a
    # general Turtle parser and NOT a gem (docs/pie-survey.md §2 costed this
    # at "a ~150-line extraction akin to a JSONL walk"; the rdf-turtle gem
    # would pull the whole rdf dependency family through the CLAUDE.md gem
    # bar for two small, regular files). The subset was censused first-hand
    # against both upstream files (2026-07-14):
    #
    #   - @prefix declarations; prefixed names (numeric/underscore locals)
    #     and <>-wrapped IRIs (unicode + fragment '#' inside);
    #   - subject blocks with ';'-separated predicate-object lists and
    #     ','-separated object lists; repeated subjects (LIV's Lexicon node
    #     accretes lime:entry across statements);
    #   - the 'a' keyword (rdf:type);
    #   - quoted literals with \" \\ \n \t \r \uXXXX escapes, optional
    #     ^^datatype / @lang annotations (annotation dropped, lexical value
    #     kept — "NaN"^^xsd:double reads "NaN");
    #   - blank-node property lists in OBJECT position (BrillEDL's
    #     canonicalForm), minted as stable _:bN ids with inner triples.
    #
    # NOT in the census, therefore NOT parsed — triple-quoted strings,
    # collections (), bare numeric/boolean literals, @base, blank-node
    # subjects: any of them fails LOUDLY as Nabu::ParseError with a line
    # number, never a silent skip (the coptic-tt unknown-span precedent).
    class LilaTtlParser
      RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

      # One parsed triple. +kind+ says what +object+ is: :iri (expanded),
      # :literal (unescaped lexical value) or :blank (a minted _:bN id whose
      # own triples follow in the stream).
      Statement = Data.define(:subject, :predicate, :object, :kind)

      # The read-side index both adapters walk: statements grouped by
      # subject and predicate, DOCUMENT ORDER preserved everywhere (entry
      # ids and body lines derive from it — the stability the loader's
      # upsert rests on). rdf:type is additionally inverted so "every
      # etymon, in file order" is one call.
      class Graph
        def initialize(statements)
          @by_subject = Hash.new { |hash, key| hash[key] = Hash.new { |inner, pred| inner[pred] = [] } }
          @subjects_by_type = Hash.new { |hash, key| hash[key] = [] }
          statements.each do |statement|
            @by_subject[statement.subject][statement.predicate] << statement.object
            if statement.predicate == RDF_TYPE && !@subjects_by_type[statement.object].include?(statement.subject)
              @subjects_by_type[statement.object] << statement.subject
            end
          end
        end

        def objects(subject, predicate)
          @by_subject.fetch(subject, {}).fetch(predicate, [])
        end

        def first(subject, predicate)
          objects(subject, predicate).first
        end

        def subjects_of_type(type_iri)
          @subjects_by_type.fetch(type_iri, [])
        end
      end

      # Local names may contain dots but not end with one ("liv_etymologies:1 ."
      # must leave the statement terminator alone).
      PNAME = /([A-Za-z][\w.-]*)?:((?:[\w%-]|\.(?=[\w.%-]))*)/
      ESCAPES = { '"' => '"', "\\" => "\\", "n" => "\n", "t" => "\t", "r" => "\r" }.freeze

      def statements(text)
        @scanner = StringScanner.new(text)
        @prefixes = {}
        @blank_serial = 0
        out = []
        loop do
          skip_ws
          break if @scanner.eos?

          @scanner.check(/@prefix/) ? parse_prefix : parse_statement(out)
        end
        out
      end

      private

      def parse_prefix
        fail!("malformed @prefix") unless @scanner.scan(/@prefix\s+#{PNAME.source}\s*<([^>]*)>\s*\./)

        @prefixes[@scanner[1].to_s] = @scanner[3]
      end

      def parse_statement(out)
        subject, kind = parse_term
        fail!("expected an IRI subject") unless kind == :iri
        parse_predicate_object_list(out, subject)
        skip_ws
        fail!("expected '.'") unless @scanner.scan(".")
      end

      def parse_predicate_object_list(out, subject)
        loop do
          predicate = parse_predicate
          parse_object_list(out, subject, predicate)
          skip_ws
          break unless @scanner.scan(";")

          skip_ws
          break if @scanner.check(/[.\]]/) # tolerate a trailing ';'
        end
      end

      def parse_object_list(out, subject, predicate)
        loop do
          object, kind = parse_object(out)
          out << Statement.new(subject: subject, predicate: predicate, object: object, kind: kind)
          skip_ws
          break unless @scanner.scan(",")
        end
      end

      def parse_predicate
        skip_ws
        return RDF_TYPE if @scanner.scan(/a(?=[\s<])/)

        term, kind = parse_term
        fail!("expected a predicate IRI") unless kind == :iri
        term
      end

      # An object may additionally be a literal or a blank-node property list.
      def parse_object(out)
        skip_ws
        if @scanner.scan("[")
          parse_blank_node(out)
        elsif @scanner.check(/"/)
          parse_literal
        else
          parse_term
        end
      end

      def parse_blank_node(out)
        node = "_:b#{@blank_serial += 1}"
        skip_ws
        parse_predicate_object_list(out, node) unless @scanner.check(/\]/)
        skip_ws
        fail!("expected ']'") unless @scanner.scan("]")
        [node, :blank]
      end

      def parse_literal
        fail!("malformed literal") unless @scanner.scan(/"((?:[^"\\]|\\.)*)"/m)
        value = unescape(@scanner[1])
        skip_ws
        if @scanner.scan("^^") # datatype annotation: consume, keep lexical value
          parse_term
        else
          @scanner.scan(/@[A-Za-z][A-Za-z0-9-]*/) # language tag: consume
        end
        [value, :literal]
      end

      def parse_term
        skip_ws
        if @scanner.scan(/<([^>]*)>/)
          [@scanner[1], :iri]
        elsif @scanner.scan(PNAME)
          prefix = @scanner[1].to_s
          base = @prefixes.fetch(prefix) { fail!("unknown prefix #{prefix.inspect}") }
          ["#{base}#{@scanner[2]}", :iri]
        else
          fail!("unexpected token #{@scanner.peek(20).inspect}")
        end
      end

      def unescape(raw)
        raw.gsub(/\\(u\h{4}|U\h{8}|.)/m) do |match|
          code = match[1..]
          case code
          when /\Au(\h{4})\z/, /\AU(\h{8})\z/ then Regexp.last_match(1).to_i(16).chr(Encoding::UTF_8)
          else ESCAPES.fetch(code) { fail!("unsupported string escape \\#{code}") }
          end
        end
      end

      def skip_ws
        @scanner.skip(/(?:\s+|#[^\n]*)+/)
      end

      def fail!(message)
        line = @scanner.string[0, @scanner.pos].count("\n") + 1
        raise Nabu::ParseError, "lila-ttl: #{message} at line #{line}"
      end
    end
  end
end
