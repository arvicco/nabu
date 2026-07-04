# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one DDbDP (Duke Databank of Documentary Papyri)
    # EpiDoc file — the fourth parser family (architecture §3), sibling to
    # EpidocParser, ConlluParser and ProielParser, and the project's first
    # confrontation with Leiden/documentary markup. A standalone,
    # individually tested component that adapters (Papyri) compose. Same call
    # shape as the other parsers:
    # #parse(source, urn:, language:, title:, canonical_path:).
    #
    # DDbDP is EpiDoc TEI but NOT CapiTainS: no __cts__.xml, no refsDecl, no
    # CTS urns — hence a new family, not EpidocParser reuse. Identity lives in
    # the header <idno> elements (types filename / ddb-perseus-style /
    # ddb-hybrid / HGV / TM); the text lives in <div type="edition"
    # xml:lang="…" xml:space="preserve"> containing <ab> with <lb n="…"/>
    # line-begin milestones, optionally wrapped in <div type="textpart"
    # n="r|v|…"> for recto/verso/columns.
    #
    # The parser is streaming by contract like its siblings: the only Nokogiri
    # entry point is Nokogiri::XML::Reader — a whole-document DOM is never
    # built (enforced structurally by the test suite). DDbDP files are small,
    # but the family rule is the family rule.
    #
    # == The Leiden text-extraction policy (FIXED here; conventions.md §5)
    #
    # A damaged papyrus arrives wrapped in editorial markup, and the question
    # "what counts as text?" has one governing answer: WHAT A PRINT EDITION'S
    # MAIN TEXT WOULD READ. A print edition prints the editor's lemma, the
    # regularized spelling, the restored letters (in square brackets), the
    # expanded abbreviations (in parentheses), the uncertain letters (under
    # dots) — all as continuous reading text; variant readings, original
    # (pre-regularization) spellings and erasures live in the apparatus.
    # Mirroring that:
    #
    # KEEP (reading text):
    #   <lem>       the editor's accepted reading (its <rdg> siblings drop)
    #   <reg>       the regularized spelling (its <orig> sibling drops)
    #   <add>       scribal additions — inside <subst> it is the scribe's
    #               final intent (the paired <del> drops); standalone
    #               (place="above" insertions) it is equally part of the text
    #   <supplied>  editorial restorations ARE the readable text — print
    #               editions read straight through their square brackets
    #   <unclear>   dotted-but-read letters
    #   <expan>     full content INCLUDING the <ex> expansions — abbreviations
    #               read expanded ("plur(imam)" reads "plurimam")
    #   <num>       the numeral's text content (@value is metadata)
    #
    # DROP (apparatus/metadata, never reading text):
    #   <rdg>       rejected variant readings
    #   <orig>      pre-regularization spellings
    #   <del>       erased text — both inside <subst> and standalone; erasure
    #               may nest (<del><del>…</del></del>) and drops wholesale
    #   <note>, <figure>   editorial noise
    #   <handShift> a metadata milestone — the hand id goes to annotations
    #   <g>         glyph placeholders (interpuncts, <g type="middot"/>):
    #               empty elements contributing nothing; word boundaries come
    #               from the editorial spacing already in the text nodes, and
    #               a middot INSIDE a regularized word (de<g/>monstrabit) must
    #               not tear the word apart
    #
    # <gap> contributes the single marker "[…]" regardless of quantity/unit —
    # the length data goes to annotations, not text. Rationale: a search hit
    # must not match across a lacuna as if the text were contiguous; the
    # marker keeps word boundaries honest ("Αἴλιος […]θως" — the marker sits
    # exactly where the lost letters sat, fused mid-word when the damage is
    # mid-word). Any children of <gap> (<desc>, <certainty>) are dropped.
    #
    # A dropped subtree drops EVERYTHING inside it: a <supplied> inside a
    # dropped <orig> counts nothing, a <gap> inside a dropped <del> marks
    # nothing, an <lb> inside a dropped branch is NOT a line boundary. The
    # nested-markup reality (choice inside lem inside app; subst>add>choice>
    # reg with an lb inside) is handled by a keep/drop depth stack: once a
    # drop element opens, the stream is discarded until its matching end
    # (nested same-name elements end at deeper depths and cannot close it).
    #
    # == Passage = the LINE
    #
    # The citable unit of papyrology is the line ("P.Oxy. 123, line 7"). A
    # passage is everything extracted between consecutive <lb> milestones:
    #
    #   urn = <document-urn>[:<textpart-path>]:<lb n>
    #
    # The textpart path (ancestor div[@type="textpart"]/@n values, in order)
    # appears only when textpart divs exist — :r:3 for recto line 3, plain :3
    # for an unpartitioned papyrus. <lb break="no"/> means the word continues
    # across the boundary; in the line-passage model both lb forms delimit
    # identically (the split word simply ends line n and continues on line
    # n+1, exactly as the print edition's margins have it) — break="no" only
    # matters to consumers re-joining lines, so it needs no marker here.
    # Upstream guarantees that when a regularization spans a line break, BOTH
    # branches of the choice/subst carry their own copy of the <lb> (see
    # bgu.1.100's revision history); only the kept branch's copy fires.
    #
    # xml:space="preserve" on the edition div means upstream whitespace is
    # significant for RECONSTRUCTING the markup stream (word spacing lives in
    # text nodes between elements, and we honor every one of them while
    # accumulating) — but the final passage text still gets the house
    # whitespace treatment: runs collapse to one space, ends strip, NFC, and
    # text_normalized = NFC(text.downcase). The tension is deliberate: inside
    # extraction the preserved spacing decides word boundaries; after
    # extraction the passage is normal prose and follows house rules.
    #
    # Lines that end empty after extraction (all content dropped/lost) are
    # skipped; a document with zero citable lines is a ParseError. Content
    # inside <ab> before the first <lb> is not citable (upstream puts only
    # whitespace there) and is discarded.
    #
    # == Annotations (lean; only non-empty keys)
    #
    #   {"leiden" => {"gaps" => [{"reason","quantity","unit"}…],   # kept gaps
    #                 "supplied_chars" => <grapheme count>,        # restored
    #                 "unclear_chars"  => <grapheme count>,        # dotted
    #                 "hands" => ["m2", …]},                       # handShift
    #    "languages" => ["lat", …]}   # inline xml:lang scopes differing from
    #                                 # the document language, mapped (la→lat)
    #
    # supplied_chars/unclear_chars count non-whitespace grapheme clusters —
    # "letters restored", the number a print edition's brackets would enclose.
    #
    # == Identity cross-checks (honest mismatch surfacing, sibling spirit)
    #
    # - <idno type="ddb-hybrid"> (e.g. "bgu;1;102") mints the urn by the
    #   FROZEN rule ";"→":" — urn:nabu:ddbdp:bgu:1:102. The caller-supplied
    #   urn must equal that minting (mismatch → ParseError); the adapter mints
    #   from the same idno, so a divergence means the file is not the document
    #   the caller asked for. Empty segments survive verbatim: c.epist.lat's
    #   hybrid "c.epist.lat;;10" (no volume) mints …:c.epist.lat::10.
    # - Missing ddb-hybrid → ParseError (checked on entering the edition div).
    # - div[@type="edition"]/@xml:lang, mapped la→lat (our tags are ISO 639-3;
    #   subtags survive: la-Grek → lat-Grek), must agree with the caller's
    #   language — disagreement is a cataloguing error, surfaced not smoothed.
    # - Malformed XML, no edition div, <lb> without @n, textpart without @n →
    #   ParseError.
    class DdbdpParser
      # DDbDP tags languages with ISO 639-1 "la"; Nabu uses ISO 639-3 "lat"
      # (conventions.md §4). Script subtags survive the mapping (la-Grek →
      # lat-Grek). "grc" is already 639-3 and passes through.
      LANGUAGE_MAP = { "la" => "lat" }.freeze

      # The single lacuna marker every <gap> contributes (see file header).
      GAP_MARKER = "[…]"

      # Map an upstream xml:lang tag to Nabu's ISO 639-3 form. nil-safe.
      def self.normalize_language(tag)
        return nil if tag.nil? || tag.empty?

        primary, rest = tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary, primary)
        rest ? "#{mapped}-#{rest}" : mapped
      end

      # One extracted line: urn_suffix is "<textpart-path?>:<lb n>" joined
      # with ":", text is final (collapsed, NFC), leiden/languages feed the
      # passage annotations.
      Line = Data.define(:urn_suffix, :text, :leiden, :languages)
      private_constant :Line

      # Same signature family as the sibling parsers.
      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        lines = extract_lines(source, path: path, urn: urn, language: language)
        build_document(lines, urn: urn, language: language, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract_lines(source, path:, urn:, language:)
        with_io(source) do |io|
          Extraction.new(
            reader: Nokogiri::XML::Reader(io, path), path: path, urn: urn, language: language
          ).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(lines, urn:, language:, title:, path:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        lines.each_with_index do |line, sequence|
          document << Passage.new(
            urn: "#{urn}:#{line.urn_suffix}",
            language: language,
            text: line.text,
            text_normalized: Normalize.nfc(line.text.downcase),
            annotations: annotations(line),
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable lines (<lb>) found in div[@type=\"edition\"]" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def annotations(line)
        result = {}
        result["leiden"] = line.leiden unless line.leiden.empty?
        result["languages"] = line.languages unless line.languages.empty?
        result
      end

      # The single-pass Reader state machine. Header phase captures the
      # ddb-hybrid idno; body phase reacts only inside div[@type="edition"],
      # where it maintains the textpart path, the keep/drop state and the
      # current line buffer (see the policy in the file header).
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # Subtrees that are never reading text (see file header). <gap> is
        # handled separately: marker first, then its children drop too.
        DROPPED_ELEMENTS = %w[rdg orig del note figure].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        def initialize(reader:, path:, urn:, language:)
          @reader = reader
          @path = path
          @urn = urn
          @language = language
          @hybrid = nil
          @capture_idno = false
          @edition_seen = false
          @edition_depth = nil
          @textparts = [] # [{n:, depth:}, …] — the current textpart path
          @drop_depth = nil # depth of the open dropped subtree, nil when keeping
          @supplied_depths = []
          @unclear_depths = []
          @current = nil # the open line's accumulation state
          @lb_ordinal = 0
          @lines = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no div[@type=\"edition\"] found" unless @edition_seen

          @lines
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        def start_element(node)
          return if dropping?
          return edition_element(node) if in_edition?

          case local_name(node)
          when "idno"
            @capture_idno = node.attribute("type") == "ddb-hybrid" && !node.empty_element?
          when "div"
            enter_edition(node) if node.attribute("type") == "edition"
          end
        end

        # Element starts inside the edition div, keep-state only (drops are
        # filtered by the caller). Everything not handled here (app, lem,
        # choice, reg, subst, add, expan, ex, num, hi, …) keeps its text: the
        # text nodes stream past and accumulate via #text_node.
        def edition_element(node)
          name = local_name(node)
          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          record_language(node)
          case name
          when "lb" then start_line(node)
          when "gap" then add_gap(node)
          when "handShift" then add_hand(node)
          when "div" then push_textpart(node)
          when "supplied" then @supplied_depths << node.depth unless node.empty_element?
          when "unclear" then @unclear_depths << node.depth unless node.empty_element?
          end
        end

        def end_element(node)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end

          case local_name(node)
          when "idno" then @capture_idno = false
          when "ab" then finish_line
          when "div" then end_div(node)
          when "supplied" then @supplied_depths.pop if @supplied_depths.last == node.depth
          when "unclear" then @unclear_depths.pop if @unclear_depths.last == node.depth
          end
        end

        def text_node(node)
          if @capture_idno
            @hybrid = node.value.to_s.strip
            @capture_idno = false
            return
          end
          return unless in_edition? && @current && !dropping?

          value = node.value.to_s
          @current[:buffer] << value
          count_certainty(value)
        end

        def count_certainty(value)
          return if @supplied_depths.empty? && @unclear_depths.empty?

          graphemes = value.gsub(/[[:space:]]/, "").grapheme_clusters.size
          @current[:supplied] += graphemes unless @supplied_depths.empty?
          @current[:unclear] += graphemes unless @unclear_depths.empty?
        end

        def dropping?
          !@drop_depth.nil?
        end

        def in_edition?
          !@edition_depth.nil?
        end

        # -- identity + edition entry ----------------------------------------

        def enter_edition(node)
          validate_identity!
          check_language!(node.attribute("xml:lang"))
          @edition_seen = true
          @edition_depth = node.depth unless node.empty_element?
        end

        def validate_identity!
          if @hybrid.nil? || @hybrid.empty?
            raise ParseError, "#{@path}: no <idno type=\"ddb-hybrid\"> found in teiHeader"
          end

          minted = "urn:nabu:ddbdp:#{@hybrid.tr(';', ':')}"
          return if minted == @urn

          raise ParseError, "#{@path}: urn mismatch: caller says #{@urn.inspect}, " \
                            "<idno type=\"ddb-hybrid\"> #{@hybrid.inspect} mints #{minted.inspect}"
        end

        def check_language!(xml_lang)
          mapped = DdbdpParser.normalize_language(xml_lang)
          return if mapped.nil? || mapped == @language

          raise ParseError, "#{@path}: language mismatch: caller says #{@language.inspect}, " \
                            "div[@type=\"edition\"]/@xml:lang is #{xml_lang.inspect} (→ #{mapped.inspect})"
        end

        # -- lines --------------------------------------------------------------

        def start_line(node)
          @lb_ordinal += 1
          n = node.attribute("n")
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.nil? || n.empty?

          finish_line
          @current = {
            n: n, textpath: @textparts.map { |part| part[:n] },
            buffer: +"", gaps: [], supplied: 0, unclear: 0, hands: [], languages: []
          }
        end

        def finish_line
          current = @current
          @current = nil
          return unless current

          text = Normalize.nfc(current[:buffer].gsub(/[[:space:]]+/, " ").strip)
          return if text.empty? # everything dropped/lost: not a citable line

          @lines << Line.new(
            urn_suffix: (current[:textpath] + [current[:n]]).join(":"),
            text: text, leiden: leiden(current), languages: current[:languages]
          )
        end

        def leiden(current)
          result = {}
          result["gaps"] = current[:gaps] unless current[:gaps].empty?
          result["supplied_chars"] = current[:supplied] if current[:supplied].positive?
          result["unclear_chars"] = current[:unclear] if current[:unclear].positive?
          result["hands"] = current[:hands] unless current[:hands].empty?
          result
        end

        # -- leiden milestones ---------------------------------------------------

        def add_gap(node)
          # Marker + annotation only when a line is open; then drop any
          # children (<desc>, <certainty> — metadata, not text).
          if @current
            @current[:buffer] << GAP_MARKER
            @current[:gaps] << gap_annotation(node)
          end
          @drop_depth = node.depth unless node.empty_element?
        end

        def gap_annotation(node)
          gap = {}
          %w[reason quantity unit].each do |attribute|
            value = node.attribute(attribute)
            next if value.nil?

            gap[attribute] = value.match?(/\A\d+\z/) ? Integer(value, 10) : value
          end
          gap
        end

        def add_hand(node)
          return unless @current

          hand = node.attribute("new")
          @current[:hands] << hand if hand && !@current[:hands].include?(hand)
        end

        def record_language(node)
          return unless @current

          mapped = DdbdpParser.normalize_language(node.lang)
          return if mapped.nil? || mapped == @language

          @current[:languages] << mapped unless @current[:languages].include?(mapped)
        end

        # -- divs (edition exit, textparts) ---------------------------------------

        def push_textpart(node)
          return unless node.attribute("type") == "textpart"

          n = node.attribute("n")
          raise ParseError, "#{@path}: div[@type=\"textpart\"] is missing its @n" if n.nil? || n.empty?
          return if node.empty_element?

          @textparts << { n: n, depth: node.depth }
        end

        def end_div(node)
          if node.depth == @edition_depth
            finish_line # defensive; </ab> normally closed the last line
            @edition_depth = nil
          elsif @textparts.last && @textparts.last[:depth] == node.depth
            finish_line # lines never span textparts
            @textparts.pop
          end
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
