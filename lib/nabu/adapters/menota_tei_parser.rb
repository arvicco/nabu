# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one Menota-TEI document (P82-1) — a NEW parser
    # family. The compose-an-existing-family bet was refuted from the real
    # bytes (census 2026-08-23, 91 documents):
    #
    # 1. The reading text lives in MULTI-LEVEL word markup no other family
    #    reads: <w lemma me:msa><choice><me:facs>…<me:dipl>…<me:norm>…
    #    </choice></w> (86/91 documents), or facs-only <w><me:facs>…</w>
    #    without <choice> (5/91). Punctuation is <pc> or <me:punct>, same
    #    level structure.
    # 2. Every file's DOCTYPE pulls the MUFI entity table
    #    (menota-entities.txt, ~1,977 entities, many into the Private Use
    #    Area): &inodot; → ı, &vins; → ꝩ, &slong; → ſ. Entities are
    #    resolved against the table landed beside texts/; an UNKNOWN
    #    entity quarantines loudly, never drops.
    # 3. Layout is milestone-based (<pb ed="ms" n="1r"/>, <cb n="B"/>,
    #    <lb n="7"/>) and milestones occur INSIDE word levels
    #    (þur<lb/>fu): a word broken across lines is cited where it
    #    starts, and a mid-word <pb>/<lb> advances the position for the
    #    tokens that follow.
    #
    # == The stored text (the ReF/ReM diplomatic precedent, per token)
    #
    # Per token: the DIPLOMATIC reading when attested, else FACSIMILE, else
    # NORMALIZED — so dipl-bearing documents read diplomatically and the
    # facs-only five read at their only attested level. Every attested
    # level rides annotations["tokens"] verbatim (with lemma, me:msa,
    # xml:id and the chosen text_level), so nothing is lost. NFC at this
    # boundary; PUA codepoints are NFC-stable.
    #
    # == The citation scheme
    #
    # Passage = one manuscript LINE (the corpus's own layout grain, the
    # ReF rule): <page><column>.<line> — 1rB.1, 2v.24. Duplicate refs
    # take the house :b<n> positional disambiguator; a token stream with
    # no milestones at all falls back to s<n> segment refs.
    #
    # == Header capture
    #
    # titleStmt title, msIdentifier (msName, settlement, repository,
    # country, idno = the manuscript signature), history origPlace +
    # origDate (@notBefore/@notAfter → the P81-1 structured envelope, raw
    # text preserved), textLang @mainLang with langUsage <language @ident>
    # as the fallback ladder, availability <licence> text + @target — the
    # caller maps the licence statement onto a license_override class.
    #
    # == Streaming
    #
    # Nokogiri::XML::Reader over the entity-resolved string: the largest
    # document (Holm D 4) runs ~25 MB and the house DOM threshold is 5 MB.
    class MenotaTeiParser
      TEI_NS = "http://www.tei-c.org/ns/1.0"
      MENOTA_NS = "http://www.menota.org/ns/1.0"

      # XML's own five stay unsubstituted — Nokogiri resolves them.
      XML_BUILTIN_ENTITIES = %w[amp lt gt quot apos].freeze

      LEVELS = %w[facs dipl norm].freeze
      # The stored-text preference order (the class note).
      TEXT_LEVEL_ORDER = %w[dipl facs norm].freeze

      ENTITY_REFERENCE = /&([A-Za-z][A-Za-z0-9._-]*);/
      ENTITY_DECLARATION = /<!ENTITY\s+(\S+)\s+"([^"]*)"\s*>/
      NUMERIC_CHARACTER = /&#x([0-9A-Fa-f]+);|&#(\d+);/
      DOCTYPE = /<!DOCTYPE[^\[>]*(?:\[[^\]]*\]\s*)?>/m

      # name => resolved UTF-8 string, from a menota-entities.txt table.
      # First declaration wins (upstream keeps a few alternative spellings
      # of the same entity, never conflicting redefinitions).
      def self.load_entities(path)
        table = {}
        File.read(path, encoding: Encoding::UTF_8).scan(ENTITY_DECLARATION) do |name, value|
          table[name] ||= value.gsub(NUMERIC_CHARACTER) do
            (Regexp.last_match(1) ? Regexp.last_match(1).to_i(16) : Regexp.last_match(2).to_i).chr(Encoding::UTF_8)
          end
        end
        raise ParseError, "#{path}: no <!ENTITY declarations — not a Menota entity table" if table.empty?

        table
      end

      # +entities+: the loaded MUFI table. +language_fallback+ serves when
      # the header carries neither textLang @mainLang nor a langUsage
      # ident. +license_mapper+ maps the captured licence statement (or
      # nil) onto a license_override class or nil — the adapter owns the
      # policy, the parser the capture.
      def parse(path, urn:, entities:, language_fallback:, license_mapper: nil)
        extraction = extract(path, entities)
        language = extraction.main_lang || extraction.lang_usage || language_fallback
        build_document(extraction, urn: urn, language: language, path: path,
                                   license_override: license_mapper&.call(extraction.metadata["license"]))
      end

      private

      def extract(path, entities)
        source = resolved_source(path, entities)
        Extraction.new(reader: Nokogiri::XML::Reader(source, path), path: path).call
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # Strip the DOCTYPE (its external entity set is the table we already
      # hold) and resolve every Menota entity from the table. Unknown
      # entities quarantine loudly — a silent drop would fake a cleaner
      # manuscript than upstream published.
      def resolved_source(path, entities)
        text = File.read(path, encoding: Encoding::UTF_8).sub(DOCTYPE, "")
        unknown = []
        resolved = text.gsub(ENTITY_REFERENCE) do
          name = Regexp.last_match(1)
          if XML_BUILTIN_ENTITIES.include?(name)
            Regexp.last_match(0)
          else
            value = entities[name]
            unknown << name if value.nil?
            xml_safe(value.to_s)
          end
        end
        return resolved if unknown.empty?

        raise ParseError, "#{path}: unknown Menota entities #{unknown.uniq.sort.join(', ')} — " \
                          "the menota-entities.txt table may be stale (delete it and re-sync)"
      end

      # An entity resolving to a markup-significant character re-enters as
      # a numeric character reference, never as raw markup.
      def xml_safe(value)
        value.gsub(/[&<>]/) { |char| "&##{char.ord};" }
      end

      def build_document(extraction, urn:, language:, path:, license_override:)
        document = Document.new(urn: urn, language: language,
                                title: extraction.title && Normalize.nfc(extraction.title),
                                canonical_path: path, metadata: extraction.metadata,
                                license_override: license_override)
        extraction.lines.each_with_index do |line, sequence|
          document << Passage.new(
            urn: "#{urn}:#{line.ref}", language: language,
            text: Normalize.nfc(line.text),
            annotations: line.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: no manuscript lines with readable tokens in <body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # One emitted manuscript line: citation ref, joined text, annotations.
      Line = Data.define(:ref, :text, :annotations)
      private_constant :Line

      # The single-pass Reader state machine: a header phase captures
      # provenance, a body phase tracks pb/cb/lb milestones and assembles
      # multi-level tokens.
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        TOKEN_ELEMENTS = %w[w pc punct].freeze
        MILESTONES = %w[pb cb lb].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :TOKEN_ELEMENTS, :MILESTONES

        Result = Data.define(:lines, :title, :main_lang, :lang_usage, :metadata)

        def initialize(reader:, path:)
          @reader = reader
          @path = path
          @seen_body = false
          @in_body = false
          @page = nil
          @column = nil
          @line = nil
          @token = nil
          @tokens = []
          @header = {}
          @capture = nil
          @contexts = []
          @levels_census = MenotaTeiParser::LEVELS.to_h { |level| [level, 0] }
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <body> found — not a Menota-TEI text" unless @seen_body

          Result.new(lines: lines, title: @header[:ms_name] || @header[:title],
                     main_lang: presence(@header[:main_lang]),
                     lang_usage: presence(@header[:lang_usage]),
                     metadata: metadata)
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        # -- dispatch ---------------------------------------------------------

        def start_element(node)
          name = local_name(node)
          return enter_body(node) if name == "body" && !@seen_body
          return header_start(node, name) unless @seen_body
          return unless @in_body

          case name
          when *MILESTONES then milestone(node, name)
          when *TOKEN_ELEMENTS then open_token(node, name)
          when *MenotaTeiParser::LEVELS then open_level(node, name)
          end
        end

        def end_element(node)
          name = local_name(node)
          return header_end(name) unless @seen_body
          return unless @in_body

          case name
          when "body" then @in_body = false
          when *TOKEN_ELEMENTS then close_token(node, name)
          when *MenotaTeiParser::LEVELS then @level = nil if menota_ns?(node)
          end
        end

        def text_node(node)
          if !@seen_body
            @capture << node.value.to_s if @capture
          elsif @in_body && @token && @level
            @token[:levels][@level] << node.value.to_s
          end
        end

        # -- header -----------------------------------------------------------
        #
        # Context-flagged single-pass capture (the corpus-corporum-tei
        # mold): the enclosing element decides what a <title>/<idno> means;
        # self-closing elements never open a capture; first value wins.

        CONTEXT_ELEMENTS = %w[titleStmt msIdentifier history availability langUsage].freeze
        private_constant :CONTEXT_ELEMENTS

        def header_start(node, name)
          if CONTEXT_ELEMENTS.include?(name) && !node.empty_element?
            @contexts.push(name)
            return
          end
          header_field(node, name)
        end

        def header_field(node, name)
          case name
          when "title" then open_capture(:title) if context?("titleStmt") && !node.empty_element?
          when "msName" then open_capture(:ms_name) if context?("msIdentifier") && !node.empty_element?
          when "idno" then open_capture(:signature) if plain_idno?(node)
          when "settlement", "repository", "country"
            open_capture(name.to_sym) if context?("msIdentifier") && !node.empty_element?
          when "origPlace" then open_capture(:orig_place) if context?("history") && !node.empty_element?
          when "origDate" then orig_date(node)
          when "textLang" then @header[:main_lang] ||= presence(node.attribute("mainLang"))
          when "language" then @header[:lang_usage] ||= presence(node.attribute("ident")) if context?("langUsage")
          when "licence"
            @header[:license_url] ||= presence(node.attribute("target"))
            open_capture(:license) unless node.empty_element?
          end
        end

        # The signature is the PLAIN msIdentifier idno ("AM 1056 IX 4to");
        # typed idnos (type="Menota" shelf numbers) ride nothing.
        def plain_idno?(node)
          context?("msIdentifier") && node.attribute("type").nil? && !node.empty_element?
        end

        def orig_date(node)
          return if @header.key?(:orig_date_seen)

          @header[:orig_date_seen] = true
          @header[:not_before] = year(node.attribute("notBefore"))
          @header[:not_after] = year(node.attribute("notAfter"))
          open_capture(:orig_date) unless node.empty_element?
        end

        def year(value)
          Integer(value, 10) if value&.match?(/\A-?\d{1,4}\z/)
        end

        CAPTURE_CLOSERS = %w[title msName idno settlement repository country
                             origPlace origDate licence].freeze
        private_constant :CAPTURE_CLOSERS

        def header_end(name)
          @capture = nil if CAPTURE_CLOSERS.include?(name)
          @contexts.pop if CONTEXT_ELEMENTS.include?(name) && @contexts.last == name
        end

        def context?(name) = @contexts.include?(name)

        def open_capture(key)
          return if @header.key?(key)

          @capture = (@header[key] = +"")
        end

        def metadata
          {
            "signature" => flatten(@header[:signature]),
            "ms_name" => flatten(@header[:ms_name]),
            "repository" => flatten(@header[:repository]),
            "settlement" => flatten(@header[:settlement]),
            "country" => flatten(@header[:country]),
            "orig_place" => flatten(@header[:orig_place]),
            "date" => date_envelope,
            "license" => flatten(@header[:license]),
            "license_url" => @header[:license_url],
            "levels" => @levels_census,
            "facets" => language_facet
          }.compact
        end

        # The P81-1 structured envelope: upstream's own notBefore/notAfter
        # attributes bound; the raw text always rides; neither → nothing
        # minted (never guessed).
        def date_envelope
          raw = flatten(@header[:orig_date])
          bounds = { "not_before" => @header[:not_before], "not_after" => @header[:not_after] }.compact
          return nil if raw.nil? && bounds.empty?

          bounds.merge({ "raw" => raw }.compact)
        end

        def language_facet
          value = presence(@header[:main_lang]) || presence(@header[:lang_usage])
          { "language" => { "value" => value } } if value
        end

        # -- body: milestones + tokens ----------------------------------------

        def enter_body(node)
          @seen_body = true
          @capture = nil
          @in_body = !node.empty_element?
        end

        # Milestones advance position wherever they occur — INCLUDING
        # inside an open token's levels (þur<lb/>fu): the token keeps the
        # position it OPENED at, the next token starts on the new line.
        def milestone(node, name)
          value = presence(node.attribute("n"))
          case name
          when "pb" then @page = value
          when "cb" then @column = value
          when "lb" then @line = value
          end
        end

        def open_token(node, name)
          return if @token || node.empty_element?
          return if name == "punct" && !menota_ns?(node)

          @token = {
            name: name, depth: node.depth,
            kind: name == "punct" ? "me:punct" : name,
            id: presence(node.attribute("xml:id")),
            lemma: presence(node.attribute("lemma")),
            msa: presence(node.attribute("me:msa")),
            position: [@page, @column, @line],
            levels: MenotaTeiParser::LEVELS.to_h { |level| [level, +""] }
          }
          @level = nil
        end

        def open_level(node, name)
          return unless @token && menota_ns?(node) && !node.empty_element?

          @level = name
        end

        def close_token(node, name)
          return unless @token && @token[:name] == name && @token[:depth] == node.depth

          token = @token
          @token = nil
          @level = nil
          finalize_token(token)
        end

        def finalize_token(token)
          levels = token[:levels].transform_values { |text| Normalize.nfc(text.gsub(/[[:space:]]+/, " ").strip) }
          text_level = MenotaTeiParser::TEXT_LEVEL_ORDER.find { |level| !levels[level].empty? }
          return if text_level.nil? # a fully empty token carries no reading

          levels.each { |level, text| @levels_census[level] += 1 unless text.empty? }
          @tokens << {
            record: token_record(token, levels, text_level),
            text: levels[text_level],
            position: token[:position]
          }
        end

        def token_record(token, levels, text_level)
          {
            "kind" => token[:kind], "id" => token[:id],
            "lemma" => presence(token[:lemma] && Normalize.nfc(token[:lemma])),
            "msa" => token[:msa], "text_level" => text_level
          }.merge(levels.reject { |_level, text| text.empty? }).compact
        end

        # -- lines ------------------------------------------------------------

        # Consecutive tokens sharing a (page, column, line) position form
        # one passage; refs disambiguate with the house :b<n> belt.
        def lines
          groups = @tokens.slice_when { |a, b| a[:position] != b[:position] }.to_a
          seen = Hash.new(0)
          groups.each_with_index.map do |group, index|
            ref = position_ref(group.first[:position], index)
            count = (seen[ref] += 1)
            ref = "#{ref}:b#{count}" if count > 1
            build_line(ref, group)
          end
        end

        def position_ref(position, index)
          page, column, line = position
          folio = "#{page}#{column}"
          ref = [presence(folio), line].compact.join(".")
          ref.empty? ? "s#{index + 1}" : ref
        end

        def build_line(ref, group)
          page, column, line = group.first[:position]
          Line.new(
            ref: ref,
            text: group.map { |token| token[:text] }.join(" "),
            annotations: {
              "addressing" => "ms-line",
              "page" => page, "column" => column, "line" => line,
              "tokens" => group.map { |token| token[:record] }
            }.compact
          )
        end

        # -- helpers ----------------------------------------------------------

        def menota_ns?(node)
          node.namespace_uri.nil? || node.namespace_uri == MenotaTeiParser::MENOTA_NS
        end

        def flatten(value)
          return nil if value.nil?

          presence(Normalize.nfc(value.gsub(/[[:space:]]+/, " ").strip))
        end

        def presence(value)
          value if value && !value.empty?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
