# frozen_string_literal: true

require "cgi"

module Nabu
  module Adapters
    # Parser for Coptic Scriptorium's TreeTagger-SGML `.tt` layer (P17-1) —
    # the coptic-tt family, upstream's own "most complete representation":
    # one file carries the full metadata header, verse-grain CTS urns,
    # per-verse English (and sometimes Arabic) translation, diplomatic +
    # normalized + morph token layers, bound groups, lemma/POS/deprel,
    # entity spans with Wikification, language-of-origin tags and
    # manuscript page/column/line topology (docs/coptic-survey.md §4).
    #
    # == The format is a SPAN STACK, not a tree
    #
    # Every line is an open tag, a close tag, or a token-piece text line.
    # Spans overlap freely — a line break (lb_n) closes and reopens INSIDE
    # a norm token between its morphs (the ϣⲡ|ϩⲓⲥⲉ quirk), the older
    # dialect's translation element opens BEFORE the verse_n it translates,
    # and cpr.2.237's figure spans close in the wrong order (</figDesc>
    # before </figure>). So this parser treats tags as span EVENTS keyed by
    # name and never enforces nesting. Token-piece text lines are ignored:
    # every value this parser needs rides in attributes (orig/norm/morph),
    # which is also what makes the collapsed dialect (below) parse alike.
    #
    # == Three structural dialects, all fixture-verified
    #
    #   modern expanded   (besa, v4.5.0): <translation> elements inside the
    #                     verse, vid_n CTS urns, orig_group/orig spans.
    #   older expanded    (gold NT books, v4.1.0): <translation> element
    #                     opens BEFORE <verse_n>; attaches FORWARD.
    #   collapsed         (automatic NT books, v4.1.0): no orig_group/orig/
    #                     lang spans — orig_group rides as an ATTRIBUTE on
    #                     norm_group, orig/lang as attributes on norm, and
    #                     translation as an attribute on verse_n.
    #
    # Unknown span types fail loudly (Nabu::ParseError → quarantine): the
    # ORACC cdl-node guard stance — the dialect inventory is verified on the
    # fixture corpora, not all 77, and a surprise must never parse silently.
    #
    # == Units and citations
    #
    # The unit is upstream's own citable grain (survey §7): the verse
    # (verse_n — bible and literary texts alike; vid_n mints verse-grain CTS
    # urns even for Besa and the AP) or, when a document carries no verse_n
    # at all (doc.papyri), the translation unit in ordinal sequence, flagged
    # non-canonical via the "addressing" annotation (the GRETIL stance).
    # Citation: <meta chapter>.<verse> for chapter-file corpora, else the
    # vid_n urn tail, else <chapter_n>.<verse>, else the bare verse; plain
    # ordinals in translation mode.
    #
    # == Text layers (conventions §9, the ccmh-txt precedent)
    #
    # Unit text = the DIPLOMATIC reading: the bound-group (orig_group)
    # sequence, supralinear strokes and editorial marks kept — canonical
    # means canonical. The upstream-normalized layer rides per token
    # ("form" = the norm word); .search_source is the documented,
    # deterministic derivation text_normalized is minted from — the norm
    # WORD sequence, word grain so FTS tokenizes searchable words (a bound
    # group fuses clitics: ⲧⲁⲣⲭⲏ would hide ⲁⲣⲭⲏ) — recomputable from the
    # stored row alone, pinned by the adapter conformance suite.
    #
    # == Annotations (JSON-safe, all queryable from the stored row)
    #
    #   "tokens"   [{ "id", "form" (norm word), "orig" (diplomatic),
    #                "lemma" | "lemma_auto" (see below), "pos" (Scriptorium
    #                tagset), "func"/"head" (UD deprel, head verbatim
    #                "#uN"), "morphs" [..], "lang" (upstream language-of-
    #                origin value, verbatim), "group" (bound-group index),
    #                "line"/"line_split" (lb_n topology), "new_sent" }]
    #   "entities" [{ "type", "identity" (Wikification, when named),
    #                "head" ("#uN"), "text" }]
    #   "loans"    { iso-ish code => token count } — the language-contact
    #              layer's derived queryable shape: Greek→grc, Hebrew→hbo,
    #              Aramaic→arc, Latin→lat, Egyptian→egy, anything else
    #              verbatim. A future `search --loans grc` facet reads this
    #              (or per-token "lang") without a reparse.
    #   "translation" / "translation_ar" / "sbl_greek" / "sbl_apparatus"
    #              per-unit aligned spans, joined in order.
    #   "verse", "vid", "page", "column", "addressing"
    #
    # == The gold-lemma gate (survey §4b)
    #
    # lemmas: :gold (default) mints the passage_lemmas index key "lemma"
    # only for documents whose meta tagging is gold or checked (the
    # goo300k/IMP gold-only precedent); automatic documents keep their
    # lemmas under "lemma_auto" — nothing is lost, nothing pollutes the
    # gold index. lemmas: :all is the owner's "include automatic" flip
    # (2.38M words), a re-parse away.
    class CopticTtParser
      # One citable unit: citation tail, diplomatic text, annotations.
      Unit = Data.define(:citation, :text, :annotations)

      # A parsed TT chunk: the decoded meta header, the units in order, and
      # the count of structurally empty units dropped (honest residue).
      Result = Data.define(:meta, :units, :empty_units)

      OPEN_TAG = /\A<([\w:.-]+)((?:\s+[\w:.-]+="[^"]*")*)\s*>\z/
      CLOSE_TAG = %r{\A</([\w:.-]+)>\z}
      ATTR = /([\w:.-]+)="([^"]*)"/

      # Upstream language-of-origin names → the codes the loans facet keys
      # on. Unknown names pass through verbatim (carried, never guessed).
      LOAN_CODES = {
        "Greek" => "grc", "Hebrew" => "hbo", "Aramaic" => "arc",
        "Latin" => "lat", "Egyptian" => "egy"
      }.freeze

      # Every span type the fixture census surfaced across the three
      # dialects, plus the survey-verified gold-book extras (sbl_greek/
      # sbl_apparatus/verse_vid, Mark_04). Anything else is a surprise.
      KNOWN_TAGS = %w[
        meta pb_xml_id pb cb_n lb_n chapter_n p_n p verse_n vid_n verse_vid
        translation arabic sbl_greek sbl_apparatus lang source_lang
        orig_group norm_group orig norm morph multiword entity
        hi_rend note figure figDesc
      ].to_set.freeze

      # Spans that carry no parse state — known, deliberately unstored.
      IGNORED_TAGS = %w[multiword hi_rend note figure figDesc p_n p verse_vid].to_set.freeze

      GOLD_TAGGING = %w[gold checked].freeze

      # The documented search-form derivation (conventions §9): the norm
      # word sequence from the stored tokens, falling back to the pristine
      # text for a row without tokens. Pure and deterministic — pinned by
      # the conformance suite's search-source hook.
      def self.search_source(text, annotations)
        tokens = annotations["tokens"]
        return text unless tokens.is_a?(Array)

        forms = tokens.filter_map { |token| token["form"] }
        forms.empty? ? text : forms.join(" ")
      end

      # Decode one meta header line into its attribute hash (NFC, HTML
      # entities unescaped; a duplicate attribute — Mark_01's doubled
      # segmentation — takes the last value). Returns nil for a non-meta line.
      def self.meta(line)
        match = OPEN_TAG.match(line.strip)
        return nil unless match && match[1] == "meta"

        decode_attrs(match[2])
      end

      # Cheap header read: the first line of +path+, decoded. Nil when the
      # file does not open with a meta header.
      def self.header(path)
        first = File.open(path, "r", &:gets)
        first.nil? ? nil : meta(first)
      end

      def self.decode_attrs(raw)
        raw.scan(ATTR).to_h do |key, value|
          [key.delete_prefix("xml:"), Normalize.nfc(CGI.unescapeHTML(value))]
        end
      end

      def initialize(lemmas: :gold)
        raise ArgumentError, "lemmas must be :gold or :all, got #{lemmas.inspect}" unless %i[gold all].include?(lemmas)

        @lemmas = lemmas
      end

      # Parse one TT chunk (a file's or zip member's full content) into a
      # Result. +label+ names the chunk in error messages only.
      def parse(source, label:)
        events = read_events(source, label)
        meta = header_of(events, label)
        state = State.new(meta: meta, lemma_key: lemma_key(meta),
                          verse_mode: events.any? { |kind, name, _| kind == :open && name == "verse_n" },
                          label: label)
        events.each { |event| handle(state, event) }
        state.finish!
        Result.new(meta: meta, units: state.units, empty_units: state.empty_units)
      end

      private

      def lemma_key(meta)
        return "lemma" if @lemmas == :all

        GOLD_TAGGING.include?(meta["tagging"]) ? "lemma" : "lemma_auto"
      end

      # [[:open, name, attrs] | [:close, name, nil]] — token-piece text
      # lines are dropped here (class note: values ride in attributes).
      def read_events(source, label)
        source.each_line.with_index(1).filter_map do |raw, lineno|
          line = raw.strip
          next if line.empty?

          if (match = CLOSE_TAG.match(line))
            known!(match[1], label, lineno)
            [:close, match[1], nil]
          elsif (match = OPEN_TAG.match(line))
            known!(match[1], label, lineno)
            [:open, match[1], self.class.decode_attrs(match[2])]
          end
        end
      end

      def known!(name, label, lineno)
        return if KNOWN_TAGS.include?(name)

        raise ParseError, "#{label}:#{lineno}: unknown TT span type <#{name}> — " \
                          "the dialect inventory is fixture-verified; a surprise must not parse silently"
      end

      def header_of(events, label)
        kind, name, attrs = events.first
        raise ParseError, "#{label}: TT chunk does not open with a <meta> header" unless kind == :open && name == "meta"

        attrs
      end

      def handle(state, (kind, name, attrs))
        kind == :open ? handle_open(state, name, attrs) : handle_close(state, name)
      end

      def handle_open(state, name, attrs)
        case name
        when "meta" then nil # consumed by header_of
        when "verse_n" then state.open_verse(attrs)
        when "translation" then state.aligned_span("translation", attrs["translation"])
        when "arabic" then state.aligned_span("translation_ar", attrs["arabic"])
        when "sbl_greek" then state.aligned_span("sbl_greek", attrs["sbl_greek"])
        when "sbl_apparatus" then state.aligned_span("sbl_apparatus", attrs["sbl_apparatus"])
        when "vid_n" then state.vid(attrs["vid_n"])
        when "chapter_n" then state.chapter = attrs["chapter_n"]
        when "pb_xml_id" then state.page = attrs["pb_xml_id"]
        when "pb" then state.page = attrs["pb"]
        when "cb_n" then state.column = attrs["cb_n"]
        when "lb_n" then state.line_break(attrs["lb_n"])
        when "orig_group" then state.pending_group_orig = attrs["orig_group"]
        when "norm_group" then state.open_group(attrs)
        when "orig" then state.pending_orig = attrs["orig"]
        when "norm" then state.open_token(attrs)
        when "morph" then state.morph(attrs["morph"])
        when "lang", "source_lang" then state.open_lang(attrs["lang"] || attrs["source_lang"])
        when "entity" then state.entity(attrs)
        else
          raise ParseError, "#{state.label}: unhandled known tag <#{name}>" unless IGNORED_TAGS.include?(name)
        end
      end

      def handle_close(state, name)
        case name
        when "verse_n" then state.close_unit
        when "norm" then state.close_token
        when "lang", "source_lang" then state.close_lang
        end
      end

      # The parse-in-progress. Verse mode segments on verse_n; translation
      # mode (no verse_n anywhere — the documentary corpora) segments on
      # translation opens with ordinal citations. Aligned spans seen while
      # no unit is open (the older dialect's forward translation) are
      # PENDING and attach to the next unit.
      class State
        attr_reader :units, :empty_units, :label
        attr_accessor :pending_group_orig, :pending_orig
        attr_writer :chapter, :page, :column

        def initialize(meta:, lemma_key:, verse_mode:, label:)
          @meta = meta
          @lemma_key = lemma_key
          @verse_mode = verse_mode
          @label = label
          @units = []
          @empty_units = 0
          @pending = {}
          @pending_entities = []
          @group_index = -1
          @ordinal = 0
        end

        def open_verse(attrs)
          close_unit
          @unit = new_unit("verse" => attrs["verse_n"])
          # the collapsed dialect: translation rides as a verse_n attribute
          aligned_span("translation", attrs["translation"]) if attrs["translation"]
        end

        def aligned_span(key, value)
          return if value.nil?

          open_ordinal_unit if !@verse_mode && key == "translation"

          bucket = @unit ? @unit[:aligned] : @pending
          (bucket[key] ||= []) << value
        end

        def vid(value)
          if @unit
            @unit[:vid] ||= value
          else
            @pending["vid"] = value
          end
        end

        def line_break(value)
          @line = value
          @token["line_split"] = value if @token
        end

        def open_group(attrs)
          unit_required!("bound group")
          @group_index += 1
          @unit[:groups] << (@pending_group_orig || attrs["orig_group"] || attrs["norm_group"])
          @pending_group_orig = nil
        end

        def open_token(attrs)
          unit_required!("token")
          raise ParseError, "#{@label}: <norm> opened inside an open token" if @token

          @token = {
            "id" => attrs["id"], "form" => attrs["norm"],
            "orig" => @pending_orig || attrs["orig"],
            @lemma_key => attrs["lemma"], "pos" => attrs["pos"],
            "func" => attrs["func"], "head" => attrs["head"],
            "lang" => attrs["lang"] || @ambient_lang,
            "group" => @group_index, "line" => @line, "morphs" => []
          }
          @token["new_sent"] = true if attrs["new_sent"] == "true"
          @pending_orig = nil
        end

        def morph(value)
          @token["morphs"] << value if @token && value
        end

        def open_lang(value)
          @ambient_lang = value
          @token["lang"] ||= value if @token
        end

        def close_lang
          @ambient_lang = nil
        end

        def close_token
          return unless @token

          @token.delete("morphs") if @token["morphs"].empty?
          tally_loan(@token["lang"])
          @unit[:tokens] << @token.compact
          @token = nil
        end

        def entity(attrs)
          record = { "type" => attrs["entity"], "head" => attrs["head_tok"], "text" => attrs["text"] }
          record["identity"] = attrs["identity"] if attrs["identity"]
          (@unit ? @unit[:entities] : @pending_entities) << record.compact
        end

        def close_unit
          return unless @unit
          raise ParseError, "#{@label}: unit closed with a token still open" if @token

          unit = @unit
          @unit = nil
          text = unit[:groups].join(" ").strip
          if text.empty?
            @empty_units += 1
            return
          end
          @units << Unit.new(citation: citation(unit), text: text, annotations: annotations(unit))
        end

        def finish!
          close_unit
        end

        private

        def new_unit(extra = {})
          unit = { groups: [], tokens: [], entities: @pending_entities,
                   aligned: @pending, vid: @pending.delete("vid"), loans: Hash.new(0),
                   "page" => @page, "column" => @column, "chapter" => @chapter }.merge(extra)
          @pending = {}
          @pending_entities = []
          unit
        end

        def open_ordinal_unit
          close_unit
          @ordinal += 1
          @unit = new_unit("ordinal" => @ordinal)
        end

        def unit_required!(what)
          return if @unit

          raise ParseError, "#{@label}: #{what} outside any verse/translation unit — " \
                            "an unsegmented stretch must not vanish silently"
        end

        def tally_loan(lang)
          return if lang.nil?

          @unit[:loans][LOAN_CODES.fetch(lang, lang)] += 1
        end

        def citation(unit)
          return unit["ordinal"].to_s unless @verse_mode

          verse = unit["verse"]
          if @meta["chapter"]
            "#{@meta['chapter']}.#{verse}"
          elsif unit[:vid]
            unit[:vid].split(":").last
          elsif unit["chapter"]
            "#{unit['chapter']}.#{verse}"
          else
            verse
          end
        end

        def annotations(unit)
          result = {}
          result["verse"] = unit["verse"] if unit["verse"]
          result["vid"] = unit[:vid] if unit[:vid]
          unit[:aligned].each { |key, values| result[key] = values.join(" ") }
          result["tokens"] = unit[:tokens]
          result["entities"] = unit[:entities] unless unit[:entities].empty?
          result["loans"] = unit[:loans] unless unit[:loans].empty?
          result["page"] = unit["page"] if unit["page"]
          result["column"] = unit["column"] if unit["column"]
          result["addressing"] = "translation-ordinal" unless @verse_mode
          result
        end
      end
    end
  end
end
