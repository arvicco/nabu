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
    #                "head" ("#uN"), "text", "subtype"/"ref" (the PATHS
    #                entity-detail spans, P18-1) }] — quote records
    #                ({"type" => "quote", "ref", "subtype"}) ride here too.
    #   "loans"    { iso-ish code => token count } — the language-contact
    #              layer's derived queryable shape: Greek→grc, Hebrew→hbo,
    #              Aramaic→arc, Latin→lat, Egyptian→egy, anything else
    #              verbatim. A future `search --loans grc` facet reads this
    #              (or per-token "lang") without a reparse.
    #   "translation" / "translation_ar" / "translation_de" /
    #   "translation_horner" / "sbl_greek" / "sbl_apparatus" /
    #   "section_title"   per-unit aligned spans, joined in order.
    #   "editorial" [{ "mark" => gap|supplied|surplus|unclear|abbr|sic|del|
    #              add, + verbatim sub-attrs (reason/unit/quantity/extent/
    #              evidence/source/type/rend/place…) }] — the transcription-
    #              status layer (P18-1).
    #   "notes"    editorial note texts (<note>/<note_note>, P18-1 upgrade).
    #   "cit_marcion" / "cit_petermann"  alternate-versification citation
    #              lists (Pistis Sophia, P18-1).
    #   "verse", "vid", "verse_name", "page", "column", "ed_page",
    #   "ed_chapter", "page_coptic", "addressing" — per-token "ed_line"
    #   rides in tokens (edition-line topology, P18-1).
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

      # Attribute whitespace is tolerated around `=` (P18-1): 18 release
      # files (helias/theodosius parts, acts-pilate, lament-mary) write
      # `msItem_title ="…"` — a space before the equals — and were
      # "unrecognized: no usable TT meta header" until the census named the
      # variant. Same dialect, one lexical quirk.
      OPEN_TAG = /\A<([\w:.-]+)((?:\s+[\w:.-]+\s*=\s*"[^"]*")*)\s*>\z/
      CLOSE_TAG = %r{\A</([\w:.-]+)>\z}
      ATTR = /([\w:.-]+)\s*=\s*"([^"]*)"/

      # Upstream language-of-origin names → the codes the loans facet keys
      # on. Unknown names pass through verbatim (carried, never guessed).
      LOAN_CODES = {
        "Greek" => "grc", "Hebrew" => "hbo", "Aramaic" => "arc",
        "Latin" => "lat", "Egyptian" => "egy"
      }.freeze

      # == The P18-1 span inventory (census over the full v6.2.0 release)
      #
      # P17-1 verified the inventory on the 5-doc fixture corpora; the first
      # full sync quarantined 277 of 465 documents on 66 span types the
      # fixtures never saw. The P18-1 census swept every TT chunk in the
      # release (2,497 files) and gave EACH type a verdict — the constants
      # below (occurrence × file counts in comments are the census). The
      # strict-inventory principle stands: anything not named here still
      # quarantines loudly.

      # Alternate names for layers already carried — folded, same surface.
      VID_TAGS = %w[vid_n verse_n_vid_n v_id vid__n].freeze # jonah 48×/4f, abraham 63×/1f, AP 3×/1f
      PAGE_TAGS = %w[pb_xml_id pb pb_n pb_id].freeze # mercurius/thomas 60×/2f, AP 3×/3f
      CHAPTER_TAGS = %w[chapter_n ch_n].freeze # AP 1×/1f
      ED_PAGE_TAGS = %w[ed_page_n ed_pg_n ed_page].freeze # 869×/80f, 274×/14f, 14×/2f
      ED_LINE_TAGS = %w[ed_line_n ed_lb_n].freeze # 38,285×/113f, 216×/2f
      PAGE_COPTIC_TAGS = %w[pb_coptic_id pb_coptic_xml].freeze # pistis-sophia 714×/27f + 1×

      # Per-unit aligned spans: tag → annotation key. trans_horner is the
      # Horner translation riding beside the primary one in Pistis Sophia;
      # german is Besa's on_vigilance German translation layer (20×/1f);
      # arabic_translation is the AP attribute-form Arabic (3×/1f);
      # section_title is bohairic-life-shenoute's section headings (18×/2f).
      ALIGNED_TAGS = {
        "translation" => "translation", "arabic" => "translation_ar",
        "arabic_translation" => "translation_ar", "german" => "translation_de",
        "trans_horner" => "translation_horner", "section_title" => "section_title",
        "sbl_greek" => "sbl_greek", "sbl_apparatus" => "sbl_apparatus"
      }.freeze

      # Editorial transcription marks (TEI-echo spans) → per-unit
      # annotations["editorial"] records {"mark" => family, <key> => value}.
      # A bare family tag starts a record from its real attributes (gap
      # reason="lacuna"; supplied source= reason=; abbr type="nomSac" — the
      # nomina-sacra layer, 1,620×/337f across the sahidic OT); an X_suffix
      # tag merges into the last record of the same family or starts one.
      # Upstream typo suffixes (gap_exent, gap_reasaon, gap_reasonn) are
      # carried VERBATIM — canonical means canonical.
      EDITORIAL_TAGS = {
        "gap" => %w[gap], "gap_reason" => %w[gap reason], # 1,154×/165f + 1,011×/54f
        "gap_unit" => %w[gap unit], "gap_extent" => %w[gap extent], # 165×/17f + 75×/11f
        "gap_quantity" => %w[gap quantity], "gap_exent" => %w[gap exent], # 89×/10f + 20×/1f
        "gap_reasaon" => %w[gap reasaon], "gap_reasonn" => %w[gap reasonn], # 2×/2f each
        "supplied" => %w[supplied], "supplied_reason" => %w[supplied reason], # 1,865×/138f + 728×/73f
        "supplied_evidence" => %w[supplied evidence], "supplied_source" => %w[supplied source], # 67×/5f + 99×/4f
        "supplied_unit" => %w[supplied unit], "supplied_quantity" => %w[supplied quantity], # 14×/1f each
        "surplus" => %w[surplus], "surplus_reason" => %w[surplus reason], # 10×/7f + 2×/2f
        "unclear" => %w[unclear], "unclear_reason" => %w[unclear reason], # 27×/3f + 64×/5f
        "abbr" => %w[abbr], "sic" => %w[sic], # 1,620×/337f + 5×/1f
        "del_rend" => %w[del rend], "add_place" => %w[add place] # 1×/1f + 2×/2f
      }.freeze

      # PATHS-project entity markup (life-aphou/-longinus-lucius/-paul-tamma/
      # -phib): subtype/gazetteer-ref spans opening just inside their
      # <entity>, plus standalone quotation-reference spans. Folded into the
      # entities annotation: tag → [entity type, record key].
      ENTITY_DETAIL_TAGS = {
        "persName_type" => %w[person subtype], "roleName_type" => %w[role subtype], # 245×/11f + 80×/9f
        "placeName_type" => %w[place subtype], "placeName_ref" => %w[place ref], # 140×/11f + 85×/11f
        "date_type" => %w[date subtype], "org_type" => %w[organization subtype], # 50×/10f + 4×/2f
        "rs_type" => %w[rs subtype], # 18×/6f
        "quote_type" => %w[quote subtype], "quote_ref" => %w[quote ref] # 22×/7f each
      }.freeze

      # Alternate versification schemes (Pistis Sophia: Petermann pages vs
      # Schmidt/Marcion chapters ride beside the primary verse_n) → per-unit
      # citation lists annotations["cit_marcion"/"cit_petermann"].
      ALT_CITATION_TAGS = {
        "marcion_verse_n" => %w[marcion verse], "marcion_chapter_n" => %w[marcion chapter], # 10,117× + 403×/28f
        "petermann_verse_n" => %w[petermann verse], "petermann_chapter_n" => %w[petermann chapter] # 2,320×+248×
      }.freeze

      # Spans that carry no parse state — known, deliberately unstored, each
      # with its census verdict:
      #   multiword/hi_rend/figure/figDesc/p_n/p/verse_vid — P17-1 verdicts.
      #   hi (2×/2f)             attribute-form of hi_rend, same rendering-only layer.
      #   sup/sub (14×/6f, 3×/1f) superscript/subscript rendering.
      #   cb (1×/1f)             bare column marker, value "cb" — no content.
      #   ignore_note (15×/2f)   upstream annotator work-notes; upstream's own
      #                          name says ignore.
      #   p_source (157×/3f)     constant per-paragraph PATHS project credit.
      #   chapter/chapter_name/chapter_2 (1-2× each) duplicate chapter naming;
      #                          the citation already comes from the meta
      #                          chapter field in those corpora.
      IGNORED_TAGS = %w[
        multiword hi_rend figure figDesc p_n p verse_vid
        hi sup sub cb ignore_note p_source chapter chapter_name chapter_2
      ].to_set.freeze

      # Every span type with a census verdict. Anything else is a surprise
      # and still fails loudly — the widened inventory keeps the tripwire.
      KNOWN_TAGS = (%w[
        meta cb_n lb_n verse_n verse ed_chapter_n
        lang source_lang orig_group norm_group orig norm morph
        entity entity_identity note note_note verse_n_vname
      ] + VID_TAGS + PAGE_TAGS + CHAPTER_TAGS + ED_PAGE_TAGS + ED_LINE_TAGS +
        PAGE_COPTIC_TAGS + ALIGNED_TAGS.keys + EDITORIAL_TAGS.keys +
        ENTITY_DETAIL_TAGS.keys + ALT_CITATION_TAGS.keys + IGNORED_TAGS.to_a).to_set.freeze

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
                          verse_mode: events.any? { |kind, name, _| kind == :open && %w[verse_n verse].include?(name) },
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
        when "verse" then state.open_verse("verse_n" => attrs["verse"]) # verse-as-unit files (1Cor, shenoute-house)
        when *ALIGNED_TAGS.keys then state.aligned_span(ALIGNED_TAGS.fetch(name), attrs[name])
        when *VID_TAGS then state.vid(attrs[name])
        when "verse_n_vname" then state.verse_name(attrs[name])
        when *CHAPTER_TAGS then state.chapter = attrs[name]
        when *PAGE_TAGS then state.page = attrs[name]
        when *PAGE_COPTIC_TAGS then state.page_coptic = attrs[name]
        when *ED_PAGE_TAGS then state.ed_page = attrs[name]
        when "ed_chapter_n" then state.ed_chapter = attrs[name]
        when *ED_LINE_TAGS then state.ed_line = attrs[name]
        when "cb_n" then state.column = attrs["cb_n"]
        when "lb_n" then state.line_break(attrs["lb_n"])
        when "orig_group" then state.pending_group_orig = attrs["orig_group"]
        when "norm_group" then state.open_group(attrs)
        when "orig" then state.pending_orig = attrs["orig"]
        when "norm" then state.open_token(attrs)
        when "morph" then state.morph(attrs["morph"])
        when "lang", "source_lang" then state.open_lang(attrs["lang"] || attrs["source_lang"])
        when "entity" then state.entity(attrs)
        when "entity_identity" then state.token_identity(attrs[name])
        when *ENTITY_DETAIL_TAGS.keys then state.entity_detail(*ENTITY_DETAIL_TAGS.fetch(name), attrs[name])
        when *ALT_CITATION_TAGS.keys
          scheme, grain = ALT_CITATION_TAGS.fetch(name)
          grain == "chapter" ? state.alt_chapter(scheme, attrs[name]) : state.alt_verse(scheme, attrs[name])
        when "note", "note_note" then state.note(attrs["note"] || attrs["note_note"])
        when *EDITORIAL_TAGS.keys
          family, key = EDITORIAL_TAGS.fetch(name)
          key ? state.editorial_detail(family, key, attrs[name]) : state.editorial_mark(family, name, attrs)
        else
          raise ParseError, "#{state.label}: unhandled known tag <#{name}>" unless IGNORED_TAGS.include?(name)
        end
      end

      def handle_close(state, name)
        case name
        when "verse_n", "verse" then state.close_unit
        when "norm" then state.close_token
        when "norm_group", "orig_group" then state.close_group
        when "lang", "source_lang" then state.close_lang
        end
      end

      # The parse-in-progress. Verse mode segments on verse_n (or its
      # verse-as-unit alias); translation mode (no verse anywhere — the
      # documentary corpora) segments on translation opens with ordinal
      # citations. Aligned spans, entities, editorial marks and citations
      # seen while no unit is open (the older dialect's forward translation)
      # are PENDING and attach to the next unit. Bound groups and tokens
      # opened while no unit is open buffer as STRAYS — the omitted-verse
      # lacuna shape (P18-1: Mark 7:16, John 5:4, Acts 8:37, Rom 16:24,
      # Rev 1:1-2, bohairic Acts 24:7, OCrum's final Amen) opens the group
      # BEFORE the verse_n it contains — and flush into the unit that opens
      # inside them; a stray that CLOSES with no unit having opened is still
      # the loud unsegmented-stretch error (the tripwire stays).
      class State
        attr_reader :units, :empty_units, :label
        attr_accessor :pending_group_orig, :pending_orig
        attr_writer :chapter, :page, :column, :ed_page, :ed_chapter, :ed_line, :page_coptic

        def initialize(meta:, lemma_key:, verse_mode:, label:)
          @meta = meta
          @lemma_key = lemma_key
          @verse_mode = verse_mode
          @label = label
          @units = []
          @empty_units = 0
          @pending = {}
          @pending_entities = []
          @pending_extras = {}
          @stray_groups = []
          @alt_chapters = {}
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

        def verse_name(value)
          if @unit
            @unit[:verse_name] ||= value
          else
            @pending["verse_name"] = value
          end
        end

        def line_break(value)
          @line = value
          @token["line_split"] = value if @token
        end

        def open_group(attrs)
          @group_index += 1
          value = @pending_group_orig || attrs["orig_group"] || attrs["norm_group"]
          @pending_group_orig = nil
          # no unit open: the omitted-verse lacuna shape — buffer the group,
          # it flushes into the unit that opens inside it (or dies loudly)
          (@unit ? @unit[:groups] : @stray_groups) << value
        end

        def close_group
          unsegmented! "bound group" if @unit.nil? && !@stray_groups.empty?
        end

        def open_token(attrs)
          unsegmented! "token" if @unit.nil? && @stray_groups.empty?
          raise ParseError, "#{@label}: <norm> opened inside an open token" if @token

          @token = {
            "id" => attrs["id"], "form" => attrs["norm"],
            "orig" => @pending_orig || attrs["orig"],
            @lemma_key => attrs["lemma"], "pos" => attrs["pos"],
            "func" => attrs["func"], "head" => attrs["head"],
            "lang" => attrs["lang"] || @ambient_lang,
            "group" => @group_index, "line" => @line, "ed_line" => @ed_line, "morphs" => []
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

          unsegmented! "token" if @unit.nil?

          finalize_token(@unit)
        end

        def entity(attrs)
          record = { "type" => attrs["entity"], "head" => attrs["head_tok"], "text" => attrs["text"] }
          record["identity"] = attrs["identity"] if attrs["identity"]
          entities_list << record.compact
        end

        # The v6.0 attribute-form Wikification (abraham, shenoute-those, …):
        # <entity_identity> wraps the current TOKEN — mint an entities record
        # anchored to it.
        def token_identity(value)
          record = { "identity" => value }
          if @token
            record["head"] = "##{@token['id']}" if @token["id"]
            record["text"] = @token["orig"] || @token["form"]
          end
          entities_list << record.compact
        end

        # PATHS subtype/ref spans open just inside the entity they qualify:
        # merge into the last record of the matching type, else stand alone.
        def entity_detail(type, key, value)
          last = entities_list.last
          if last && last["type"] == type && !last.key?(key)
            last[key] = value
          else
            entities_list << { "type" => type, key => value }
          end
        end

        def note(value)
          extras("notes") << value if value
        end

        def alt_chapter(scheme, value)
          @alt_chapters[scheme] = value
        end

        def alt_verse(scheme, value)
          chapter = @alt_chapters[scheme]
          extras("cit_#{scheme}") << (chapter ? "#{chapter}.#{value}" : value)
        end

        def editorial_mark(family, tag, attrs)
          # drop the self-named no-content attribute (<gap gap="gap">), keep
          # real payloads (<gap reason="lacuna">, <abbr type="nomSac">)
          payload = attrs.reject { |key, value| key == tag && value == tag }
          extras("editorial") << { "mark" => family }.merge(payload)
        end

        def editorial_detail(family, key, value)
          last = extras("editorial").last
          if last && last["mark"] == family && !last.key?(key)
            last[key] = value
          else
            extras("editorial") << { "mark" => family, key => value }
          end
        end

        def close_unit
          return unless @unit

          # A token still open at unit close belongs to the unit it OPENED
          # in (span-stack semantics: the token span simply overlaps the
          # verse span). Two upstream shapes hit this: the omitted-verse
          # lacuna (the verse nests INSIDE the `[..]` token) and the
          # verse-boundary-inside-a-token split (Luke 13:20|21 breaks
          # mid-word ⲟⲩ|ⲉⲥ; helias breaks at chapter boundaries) — the
          # lb_n morph-split quirk at verse grain.
          finalize_token(@unit) if @token
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
          unsegmented! "bound group" unless @stray_groups.empty?
        end

        private

        def finalize_token(unit)
          @token.delete("morphs") if @token["morphs"].empty?
          tally_loan(unit, @token["lang"])
          unit[:tokens] << @token.compact
          @token = nil
        end

        def entities_list
          @unit ? @unit[:entities] : @pending_entities
        end

        # List-valued unit annotations (notes, editorial, cit_*): pending
        # buckets attach to the next unit, like pending entities.
        def extras(key)
          bucket = @unit ? @unit[:extras] : @pending_extras
          bucket[key] ||= []
        end

        def new_unit(extra = {})
          unit = { groups: @stray_groups, tokens: [], entities: @pending_entities,
                   aligned: @pending, vid: @pending.delete("vid"),
                   verse_name: @pending.delete("verse_name"),
                   extras: @pending_extras, loans: Hash.new(0),
                   "page" => @page, "column" => @column, "chapter" => @chapter,
                   "ed_page" => @ed_page, "ed_chapter" => @ed_chapter,
                   "page_coptic" => @page_coptic }.merge(extra)
          @pending = {}
          @pending_entities = []
          @pending_extras = {}
          @stray_groups = []
          unit
        end

        def open_ordinal_unit
          close_unit
          @ordinal += 1
          @unit = new_unit("ordinal" => @ordinal)
        end

        def unsegmented!(what)
          raise ParseError, "#{@label}: #{what} outside any verse/translation unit — " \
                            "an unsegmented stretch must not vanish silently"
        end

        def tally_loan(unit, lang)
          return if lang.nil?

          unit[:loans][LOAN_CODES.fetch(lang, lang)] += 1
        end

        def citation(unit)
          return unit["ordinal"].to_s unless @verse_mode

          verse = unit["verse"]
          if (fused = verse&.match(/\s(\d+):(\d+)\z/))
            # verse-as-unit files label the verse "1 Corinthians 14:1" —
            # normalize OUR citation grain to chapter.verse (the verbatim
            # label still rides in annotations["verse"])
            "#{fused[1]}.#{fused[2]}"
          elsif @meta["chapter"]
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
          result["verse_name"] = unit[:verse_name] if unit[:verse_name]
          unit[:aligned].each { |key, values| result[key] = values.join(" ") }
          result["tokens"] = unit[:tokens]
          result["entities"] = unit[:entities] unless unit[:entities].empty?
          result["loans"] = unit[:loans] unless unit[:loans].empty?
          unit[:extras].each { |key, values| result[key] = values unless values.empty? }
          %w[page column ed_page ed_chapter page_coptic].each do |key|
            result[key] = unit[key] if unit[key]
          end
          result["addressing"] = "translation-ordinal" unless @verse_mode
          result
        end
      end
    end
  end
end
