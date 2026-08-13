# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for the HSMS verticalized lane (P77-2) — the hsms family's
    # lemma layer: OSTA's verticalized/TEXT.xxx.vrt.html token streams,
    # produced upstream with FreeLing + HSMS-app (Gago Jover & Pueyo
    # Mena, Scriptum Digital 7 — AUTOMATIC lemmatization, hence the
    # source's `lemma_tier: silver`, the GLAUx precedent).
    #
    # == The format (censused from the fixture)
    #
    # HTML-soup pages (unclosed <BR>/<META>, minimized attributes) whose
    # <DIV class="paleo"> carries the same HSMS structure as the
    # transcriptions, element-encoded: <RMK> groups (the header slots
    # and the {RMK: HSMS-NNNN-NNNN:} section markers, themselves token
    # streams), <FOL>/<folio> folio milestones, <CB2> column blocks,
    # <LN id> manuscript lines, and one <w data1='token•lemma•EAGLES'>
    # per word whose ELEMENT TEXT is the diplomatic surface (<ABB>
    # expansions, <SUP> superscripts, <EDITADD> editorial additions
    # flatten seamlessly; in-token wrap hyphens stay: "per-done").
    # Contractions ride composite fields ("del" → de·el / SPS00·DA0MS0)
    # and stay verbatim — the ReN chained-lemma precedent. RMK/PUNCT
    # pseudo-tags are structure, never citation forms.
    #
    # == Grain and the lemma contract
    #
    # Passage = the HSMS numbered section (the transcription lane's
    # grain; honest `head` for pre-section text, :b2 for collisions).
    # Passage text = the diplomatic surfaces in <LN> line layout. The
    # clean (token, lemma, pos) triples ride the "tokens" annotation —
    # exactly what the Indexer's lemma pass consumes — with lemma/pos
    # omitted on pseudo-tagged tokens so no RMK/PUNCT row can ever
    # reach the lemma index. text_normalized derives from the clean
    # token stream (.search_source — recomputable from the stored row's
    # text + annotations, the ccmh-txt contract; conventions §9).
    #
    # HTML soup at up to megabytes per file → SAX (Nokogiri::HTML4::SAX),
    # never a DOM; unknown structural tags are censused loud in document
    # metadata while parsing continues (the aozora posture).
    class HsmsVrtParser
      SECTION = /\AHSMS-(\d+)-(\d+):?\z/
      HSMS_ID = /\AHSMS-\d+\.?\z/

      # The documented derivation text_normalized is minted from: the
      # passage's clean token forms, space-joined — pure over the STORED
      # row (text + "tokens" annotation), the conformance pin.
      def self.search_source(text, annotations)
        tokens = annotations["tokens"] or return text
        forms = tokens.filter_map { |token| token["form"] }
        forms.empty? ? text : forms.join(" ")
      end

      def parse(path, urn:, language:, siglum:, extra_metadata: {})
        handler = Handler.new(path)
        Nokogiri::HTML4::SAX::Parser.new(handler).parse(File.read(path))
        handler.finish
        raise ParseError, handler.defect if handler.defect

        build_document(handler, path: path, urn: urn, language: language,
                                siglum: siglum, extra_metadata: extra_metadata)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def build_document(handler, path:, urn:, language:, siglum:, extra_metadata:)
        metadata = header_metadata(handler, siglum)
        metadata["sections"] = handler.passages.count { |p| p[:annotations].key?("hsms") }
        metadata["unrecognized_tags"] = handler.unrecognized.sort.to_h unless handler.unrecognized.empty?
        metadata["empty_sections"] = handler.empty_sections unless handler.empty_sections.empty?
        metadata.merge!(extra_metadata)
        document = Nabu::Document.new(
          urn: urn, language: language, title: metadata["title"] || siglum,
          canonical_path: File.expand_path(path), metadata: metadata
        )
        append_passages(document, handler, urn, language)
        raise ParseError, "#{path}: no passages parsed" if document.empty?

        document
      end

      def append_passages(document, handler, urn, language)
        citations = Hash.new(0)
        handler.passages.each do |raw|
          citations[raw[:citation]] += 1
          count = citations[raw[:citation]]
          citation = count == 1 ? raw[:citation] : "#{raw[:citation]}:b#{count}"
          document << passage(raw, urn: urn, language: language, citation: citation,
                                   sequence: document.size)
        end
      end

      def passage(raw, urn:, language:, citation:, sequence:)
        text = Normalize.nfc(raw[:lines].join("\n"))
        annotations = raw[:annotations]
        annotations["folios"] = raw[:folios] unless raw[:folios].empty?
        annotations["columns"] = raw[:columns] unless raw[:columns].empty?
        annotations["tokens"] = raw[:tokens] unless raw[:tokens].empty?
        Nabu::Passage.new(
          urn: "#{urn}:#{citation}", language: language, text: text,
          text_normalized: Normalize.search_form(self.class.search_source(text, annotations),
                                                 language: language),
          annotations: annotations, sequence: sequence
        )
      end

      def header_metadata(handler, siglum)
        meta = {}
        meta["header"] = handler.header.dup unless handler.header.empty?
        id_entry = handler.header.find { |entry| HSMS_ID.match?(entry) }
        meta["hsms_id"] = id_entry.sub(/\.\z/, "") if id_entry
        titled = handler.header.find { |entry| entry.start_with?("#{siglum} ") }
        if titled
          meta["siglum"] = siglum
          title = titled.delete_prefix("#{siglum} ").strip.sub(/\.\z/, "")
          meta["title"] = title unless title.empty?
        end
        meta
      end

      # The SAX state machine: assembles header lines and raw passage
      # hashes in document order. Defects are recorded (first wins) and
      # raised by the caller — a SAX callback is no place for control
      # flow across the C boundary.
      class Handler < Nokogiri::XML::SAX::Document
        PSEUDO_TAGS = %w[RMK PUNCT].freeze

        STRUCTURE_TAGS = %w[html head meta title link body div p fol cb lnc br
                            abb sup editadd].freeze

        attr_reader :header, :passages, :empty_sections, :unrecognized, :defect

        def initialize(path)
          super()
          @path = path
          @header = []
          @header_open = true
          @rmk = nil
          @token = nil
          @folio_text = nil
          @folio = nil
          @pending_columns = []
          @line = nil
          @current = nil
          @passages = []
          @empty_sections = []
          @unrecognized = Hash.new(0)
          @defect = nil
          @finished = false
        end

        def start_element(name, attrs = [])
          return if @defect

          case name.downcase
          when "rmk" then @rmk = []
          when "w" then @token = { data1: attrs.to_h["data1"], text: +"" }
          when "folio" then @folio_text = +""
          when "ln" then flush_line
          when /\Acb\d+\z/ then @pending_columns << name.upcase
          when *STRUCTURE_TAGS then nil
          else @unrecognized[name.upcase] += 1
          end
        end

        def characters(string)
          return if @defect

          if @token
            @token[:text] << string
          elsif @folio_text
            @folio_text << string
          end
        end

        def end_element(name)
          return if @defect

          case name.downcase
          when "w" then finish_token
          when "rmk" then finish_rmk
          when "folio"
            @folio = @folio_text.strip
            @folio_text = nil
          end
        end

        def end_document
          finish
        end

        # Idempotent final flush — called from the parser (and by SAX's
        # own end_document, whichever fires first).
        def finish
          return if @finished || @defect

          @finished = true
          close_current
        end

        private

        def finish_token
          token = @token
          @token = nil
          display = token[:text].strip
          fields = split_data1(token[:data1], display) or return
          entry = { display: display, form: fields[0], lemma: fields[1], pos: fields[2] }
          @rmk ? @rmk << entry : body_token(entry)
        end

        def split_data1(data1, display)
          fields = (data1 || "").split("•")
          return fields if fields.size == 3

          @defect = "#{@path}: token #{display.inspect}: data1 #{data1.inspect} does not split " \
                    "into token•lemma•PoS"
          nil
        end

        def body_token(entry)
          @line ||= { displays: [], tokens: [] }
          @line[:displays] << entry[:display]
          token = { "form" => entry[:form] }
          unless PSEUDO_TAGS.include?(entry[:lemma])
            token["lemma"] = entry[:lemma]
            token["pos"] = entry[:pos]
          end
          @line[:tokens] << token
        end

        def finish_rmk
          displays = @rmk.map { |entry| entry[:display] }
          @rmk = nil
          if (match = SECTION.match(displays.first || ""))
            @header_open = false
            start_section(match, displays.drop(1))
          elsif @header_open
            @header << flatten(displays)
          else
            note(flatten(displays))
          end
        end

        def flatten(displays)
          displays.join(" ").gsub(" .", ".")
        end

        def start_section(match, title_displays)
          flush_line
          close_current
          annotations = { "hsms" => match[0].sub(/:\z/, "") }
          title = flatten(title_displays).strip.sub(/\.\z/, "")
          annotations["title"] = title unless title.empty?
          @current = open_passage(Integer(match[2], 10).to_s, annotations)
        end

        def note(content)
          return if content == "." || content.empty?

          ensure_current
          (@current[:annotations]["notes"] ||= []) << content
        end

        def open_passage(citation, annotations)
          { citation: citation, annotations: annotations,
            lines: [], tokens: [], folios: [], columns: [] }
        end

        def ensure_current
          return if @current

          @current = open_passage("head", { "kind" => "head" })
        end

        def flush_line
          line = @line
          @line = nil
          return unless line && line[:displays].any?

          @header_open = false
          ensure_current
          @current[:lines] << line[:displays].join(" ")
          @current[:tokens].concat(line[:tokens])
          @current[:folios] << @folio if @folio && @current[:folios].last != @folio
          @current[:columns].concat(@pending_columns)
          @pending_columns = []
        end

        def close_current
          flush_line
          passage = @current
          @current = nil
          return unless passage

          if passage[:lines].empty?
            @empty_sections << passage[:annotations]["hsms"] if passage[:annotations]["hsms"]
            return
          end
          @passages << passage
        end
      end
    end
  end
end
