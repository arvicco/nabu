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
    # facs-only five read at their only attested level. A token with NO
    # level children (bare <pc> punctuation, fully <supplied> words —
    # level-invariant text the encoders write once, unwrapped; Q45) reads
    # at the level the document's stored text reads at, or at the
    # header's declared me:level when the document carries no level
    # markup at all. Every attested level rides annotations["tokens"]
    # verbatim (with lemma, me:msa, xml:id and the chosen text_level), so
    # nothing is lost. NFC at this boundary; PUA codepoints are
    # NFC-stable.
    #
    # == The citation scheme
    #
    # Passage = one manuscript LINE (the corpus's own layout grain, the
    # ReF rule): <page><column>.<line> — 1rB.1, 2v.24. Only the
    # manuscript's OWN layout mints refs: pb/cb/lb with ed="ms" or no ed
    # (Q45) — milestones carrying any other ed replay a printed edition,
    # another hand, or a parallel manuscript and never advance the
    # position. Duplicate refs take the house :b<n> positional
    # disambiguator; a token stream with no milestones at all falls back
    # to s<n> segment refs.
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
      ENTITY_DECLARATION = /<!ENTITY\s+(\S+)\s+(?:"([^"]*)"|'([^']*)')\s*>/
      NUMERIC_CHARACTER = /&#x([0-9A-Fa-f]+);|&#(\d+);/
      DOCTYPE = /<!DOCTYPE[^\[>]*(?:\[[^\]]*\]\s*)?>/m
      COMMENT = /<!--.*?-->/m
      # Split-with-capture: comment segments survive verbatim, everything
      # else goes through entity resolution (XML: a reference inside a
      # comment is NOT a reference — the P82-r1 census found &aum;, &zzz;,
      # &fish; etc. ONLY inside editorial comments).
      COMMENT_SPLIT = /(<!--.*?-->)/m
      # One internal-subset binding, in document order: either the
      # %Menota_entities; parameter reference (which binds the fetched
      # table) or a local general-entity declaration (either quote style).
      SUBSET_BINDING = /%[A-Za-z][A-Za-z0-9._-]*;|#{ENTITY_DECLARATION.source}/

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

      # Strip the DOCTYPE — after honoring its INTERNAL SUBSET: local
      # <!ENTITY> declarations are upstream's own data (Codex Wormianus
      # declares its runic entities there) and bind per XML's
      # first-declaration-wins rule, the %Menota_entities; reference
      # binding the fetched table at its document position. Then resolve
      # every Menota entity OUTSIDE comments (XML never recognizes
      # references inside them). Unknown entities in content quarantine
      # loudly — a silent drop would fake a cleaner manuscript than
      # upstream published.
      def resolved_source(path, entities)
        text = File.read(path, encoding: Encoding::UTF_8)
        entities = merge_internal_subset(text[DOCTYPE], entities)
        unknown = []
        resolved = text.sub(DOCTYPE, "").split(COMMENT_SPLIT).map do |segment|
          segment.start_with?("<!--") ? segment : substitute(segment, entities, unknown)
        end.join
        return resolved if unknown.empty?

        raise ParseError, "#{path}: unknown Menota entities #{unknown.uniq.sort.join(', ')} — " \
                          "the menota-entities.txt table may be stale (delete it and re-sync)"
      end

      def substitute(segment, entities, unknown)
        segment.gsub(ENTITY_REFERENCE) do
          name = Regexp.last_match(1)
          if XML_BUILTIN_ENTITIES.include?(name)
            Regexp.last_match(0)
          else
            value = entities[name]
            unknown << name if value.nil?
            xml_safe(value.to_s)
          end
        end
      end

      # The internal-subset merge: bindings apply in document order (every
      # censused file references %Menota_entities; FIRST, so the shared
      # table wins over any local re-declaration — exactly what a
      # validating XML parser would do). Local values may nest numeric
      # references, table entities, or other locals; a value that cannot
      # be fully resolved (unknown reference, cycle) stays UNBOUND, so its
      # use in content still quarantines by name.
      def merge_internal_subset(doctype, table)
        return table if doctype.nil?

        bound = {}
        raw = {}
        doctype.gsub(COMMENT, "").scan(SUBSET_BINDING) do |name, double_quoted, single_quoted|
          if name.nil? # the parameter reference — bind the fetched table
            table.each { |key, value| bound[key] = value unless bound.key?(key) || raw.key?(key) }
          elsif !bound.key?(name) && !raw.key?(name)
            raw[name] = double_quoted || single_quoted
          end
        end
        return table if raw.empty? # nothing local — spare the copy

        raw.each_key { |name| resolve_local(name, raw, bound, []) }
        bound
      end

      def resolve_local(name, raw, bound, stack)
        return bound[name] if bound.key?(name)
        return nil unless raw.key?(name) # unknown reference target
        return nil if stack.include?(name) # cycle — unresolvable

        failed = false
        value = raw[name].gsub(NUMERIC_CHARACTER) do
          (Regexp.last_match(1) ? Regexp.last_match(1).to_i(16) : Regexp.last_match(2).to_i)
            .chr(Encoding::UTF_8)
        end
        value = value.gsub(ENTITY_REFERENCE) do
          inner = resolve_local(Regexp.last_match(1), raw, bound, stack + [name])
          failed = true if inner.nil?
          inner.to_s
        end
        bound[name] = value unless failed
        failed ? nil : value
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
        # Subtrees suppressed from a BARE token's reading text (the
        # single-level shape): editorial commentary (<note>), the
        # editor's emendation (<corr> — the manuscript's <sic> is the
        # diplomatic reading), and the unexpanded abbreviation mark
        # (<am> — the <ex> expansion is the diplomatic reading). Each
        # rides the token record under its own key instead. Level-bearing
        # tokens are untouched — the 83 loaded documents stay bit-stable.
        EXTRA_ELEMENTS = %w[note corr am].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :TOKEN_ELEMENTS, :MILESTONES,
                         :EXTRA_ELEMENTS

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
          @level = nil
          @extra = nil
          @bare_break = false
          @rdg = nil
          @apparatus = []
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

          # P88-B1 (№R-45 flaw 1): a critical apparatus interleaves OTHER
          # manuscripts' readings — <app><lem>own text</lem><rdg wit="…">
          # witness text</rdg></app> (AM 36 fol: 4,241 apps). <app>/<lem>
          # are transparent (the lem IS the manuscript's reading); a <rdg>
          # subtree suppresses WHOLESALE — its words never become tokens,
          # its <lb ed="ms"/> never advances the line counter — and its
          # text rides the line's `apparatus` annotation, sigla labeled.
          return if @rdg
          return open_rdg(node) if name == "rdg"

          case name
          when *MILESTONES then milestone(node, name)
          when *TOKEN_ELEMENTS then open_token(node, name)
          when *MenotaTeiParser::LEVELS then open_level(node, name)
          when *EXTRA_ELEMENTS then open_extra(node, name)
          end
        end

        def end_element(node)
          name = local_name(node)
          return header_end(name) unless @seen_body
          return unless @in_body

          if @rdg
            close_rdg if name == "rdg" && node.depth == @rdg.fetch(:depth)
            return
          end

          case name
          when "body" then @in_body = false
          when *TOKEN_ELEMENTS then close_token(node, name)
          when *MenotaTeiParser::LEVELS then @level = nil if menota_ns?(node)
          when *EXTRA_ELEMENTS then close_extra(node, name)
          end
        end

        def text_node(node)
          if !@seen_body
            @capture << node.value.to_s if @capture
          elsif @in_body && @rdg
            @rdg[:text] << node.value.to_s
          elsif @in_body && @token
            if @level
              @token[:levels][@level] << node.value.to_s
            elsif @extra
              @token[:extras][@extra.fetch(:name)] << node.value.to_s
            else
              bare_text(node.value.to_s)
            end
          end
        end

        # Milestone-adjacent whitespace inside a bare token is XML layout
        # (gaf<lb/>lak wrapped across source lines), never reading text;
        # a REAL internal space ("hæilsu hialp") is preserved.
        def bare_text(value)
          if @bare_break
            value = value.lstrip
            @bare_break = false unless value.empty?
          end
          @token[:bare] << value
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
          when "normalization" then @header[:me_level] ||= presence(node.attribute("me:level"))
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
        # But ONLY the manuscript's own layout counts (Q45): ed="ms" or
        # no ed at all (AM 36's main text numbers its lines with ed-less
        # <lb n="06"/>). Any other ed names ANOTHER source's layout —
        # a printed edition (<pb ed="Unger" n="0001"/> interleaves with
        # <lb ed="ms" n="6"/> in DG 4-7 Streng and would overwrite the
        # folio in an ms-line ref), another hand (ed="younger hand"
        # inside <add>), the transcriber's lacuna markers (ed="added"),
        # a parallel manuscript (ed="AM 237a fol") — and never advances
        # the citation. Whitespace around ANY milestone inside a bare
        # token is XML layout either way.
        def milestone(node, name)
          if ms_layout?(node)
            value = presence(node.attribute("n"))
            case name
            when "pb" then @page = value
            when "cb" then @column = value
            when "lb" then @line = value
            end
          end
          return unless @token && @level.nil? && @extra.nil?

          @token[:bare].rstrip!
          @bare_break = true
        end

        # The witness reading capture: its raw text nodes concatenate
        # (AM 36's witnesses carry a single me:dipl level, so this IS the
        # diplomatic reading), whitespace squeezed at close; a rdg with no
        # text at all (the <!--no parallel--> comment shape) contributes
        # nothing. Attached at the position current when the rdg opens —
        # the app straddles its lem's trailing line break, so the entry
        # annotates the line the apparatus follows.
        def open_rdg(node)
          return if node.empty_element?

          @rdg = { depth: node.depth, wit: presence(node.attribute("wit")),
                   text: +"", position: [@page, @column, @line] }
        end

        def close_rdg
          rdg = @rdg
          @rdg = nil
          text = rdg[:text].gsub(/\s+/, " ").strip
          return if text.empty?

          @apparatus << { position: rdg[:position], "wit" => rdg[:wit], "text" => text }
        end

        def ms_layout?(node)
          ed = node.attribute("ed")
          ed.nil? || ed == "ms"
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
            levels: MenotaTeiParser::LEVELS.to_h { |level| [level, +""] },
            bare: +"", extras: {}
          }
          @level = nil
          @extra = nil
          @bare_break = false
        end

        def open_level(node, name)
          return unless @token && menota_ns?(node) && !node.empty_element?

          @level = name
        end

        def open_extra(node, name)
          return unless @token && @level.nil? && @extra.nil? && !node.empty_element?

          @extra = { name: name, depth: node.depth }
          @token[:extras][name] ||= +""
        end

        def close_extra(node, name)
          @extra = nil if @extra && @extra.fetch(:name) == name && @extra.fetch(:depth) == node.depth
        end

        def close_token(node, name)
          return unless @token && @token[:name] == name && @token[:depth] == node.depth

          token = @token
          @token = nil
          @level = nil
          @extra = nil
          finalize_token(token)
        end

        def finalize_token(token)
          levels = token[:levels].transform_values { |text| flatten(text).to_s }
          text_level = MenotaTeiParser::TEXT_LEVEL_ORDER.find { |level| !levels[level].empty? }
          if text_level.nil?
            queue_bare_token(token)
            return
          end

          levels.each { |level, text| @levels_census[level] += 1 unless text.empty? }
          @tokens << {
            record: token_record(token, levels, text_level),
            text: levels[text_level],
            position: token[:position]
          }
        end

        # A token with NO me: level readings: in a single-level document
        # (the DG 4-7 shape — bare text straight in <w>) it IS the
        # transcription, at the level the header itself declares; in a
        # level-bearing document it stays dropped (the status quo for the
        # loaded corpus). The verdict falls at line-assembly time.
        # Whitespace-only stays dropped via flatten; marks-only likewise
        # (the P83/Q47 A15970 lesson): a token of bare combining marks
        # has no base characters — blank, never reading text.
        def queue_bare_token(token)
          text = flatten(token[:bare])
          return if text.nil? || text.match?(/\A[[:space:]\p{M}]*\z/)

          extras = token[:extras].filter_map do |name, value|
            flattened = flatten(value)
            [name, flattened] if flattened
          end.to_h
          @tokens << { record: token_record(token, {}, nil), text: text,
                       position: token[:position], bare: true, extras: extras }
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
          groups = materialized_tokens.slice_when { |a, b| a[:position] != b[:position] }.to_a
          seen = Hash.new(0)
          groups.each_with_index.map do |group, index|
            ref = position_ref(group.first[:position], index)
            count = (seen[ref] += 1)
            ref = "#{ref}:b#{count}" if count > 1
            build_line(ref, group)
          end
        end

        # Bare tokens are reading text at the level the encoder left
        # implicit (Q45 census 2026-08-27: 30 of 91 documents leave
        # 98,575 tokens bare — 99.9% punctuation, plus fully <supplied>
        # words; level-invariant text is written ONCE, unwrapped). In a
        # document with me: levels they read at the level the document's
        # stored text reads at (the dominant attested level — the
        # header's own me:level claim wherever the two could be compared,
        # but HolmPerg 4 fol declares "dipl" while attesting all three,
        # so the census is the trusted witness); in a document with NONE,
        # at the single level the header itself declares.
        def materialized_tokens
          level = dominant_level
          @tokens.each do |token|
            next unless token[:bare]

            level ||= declared_single_level
            token[:record] = token[:record].merge(
              { "text_level" => level, level => token[:text] }, token[:extras]
            )
            @levels_census[level] += 1
          end
          @tokens
        end

        def dominant_level
          MenotaTeiParser::TEXT_LEVEL_ORDER.find { |level| @levels_census[level].positive? }
        end

        # Never guess the level: the header's own <normalization
        # me:level="dipl"> claim serves, and only when it names exactly
        # one known level.
        def declared_single_level
          declared = @header[:me_level].to_s.split
          return declared.first if declared.size == 1 && MenotaTeiParser::LEVELS.include?(declared.first)

          raise ParseError, "#{@path}: tokens carry no me: reading levels and the header's " \
                            "<normalization me:level=#{@header[:me_level].to_s.inspect}> does " \
                            "not name exactly one level — cannot attribute the transcription " \
                            "level honestly"
        end

        def position_ref(position, index)
          page, column, line = position
          folio = "#{page}#{column}"
          ref = [presence(folio), line].compact.join(".")
          ref.empty? ? "s#{index + 1}" : ref
        end

        def build_line(ref, group)
          page, column, line = group.first[:position]
          apparatus = @apparatus.select { |entry| entry[:position] == group.first[:position] }
                                .map { |entry| entry.except(:position) }
          Line.new(
            ref: ref,
            text: group.map { |token| token[:text] }.join(" "),
            annotations: {
              "addressing" => "ms-line",
              "page" => page, "column" => column, "line" => line,
              "apparatus" => (apparatus if apparatus.any?),
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
