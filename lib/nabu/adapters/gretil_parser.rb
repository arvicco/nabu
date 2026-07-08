# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one GRETIL (Göttingen Register of Electronic Texts in
    # Indian Languages) mass-converted TEI P5 file — the fifth bespoke parser
    # family (architecture §3), sibling to EpidocParser, ConlluParser,
    # ProielParser and DdbdpParser, and the project's first Indic-language
    # source. A standalone, individually tested component the Gretil adapter
    # composes. Same call shape as the other parsers:
    # #parse(source, urn:, language:, title:, canonical_path:).
    #
    # GRETIL's TEI is NOT EpiDoc/CapiTainS: no refsDecl-driven cRefPattern, no
    # CTS urns, no __cts__.xml — hence a new family, not EpidocParser reuse.
    # Text lives in <text xml:lang="…"><body> as one of FOUR addressability
    # shapes (the scout's P9-4a census + the P9-4c quarantine recovery), and
    # this parser mines a citation from whichever shape a text carries:
    #
    # == The three addressability rungs (citation minting)
    #
    # (a) ATTRIBUTE-CITED (hand-crafted minority — sa_Rgveda-edAufrecht).
    #     Nested <div type="maṇḍala|sūkta" n="…"> wrapping
    #     <lg xml:id="RV_1.001.01"> wrapping <l n="1.001.01a">. The <l>/@n is a
    #     FULL self-contained dotted address (maṇḍala.sūkta.verse.pada), so the
    #     citable unit is the <l> (the pada) and the citation is its @n VERBATIM
    #     — no div-path prefixing (that would duplicate what @n already encodes),
    #     no lg-id prefix-stripping. The enclosing <lg>/@xml:id and the div
    #     @type/@n path ride along in the passage annotations as context
    #     ("lg", "div"), so the verse grouping is preserved without being the
    #     citation. → urn …:sa_Rgveda-edAufrecht-…:1.001.01a
    #
    # (b) IN-TEXT VERSE MARKER (mass-converted verse — sa_brahmabindUpaniSad).
    #     Flat <lg> of <l> with NO @n/@xml:id; the verse number is embedded in
    #     the running text as a marker "// BrbUp_1 //" — abbreviation +
    #     underscore + dotted number, delimited by DOUBLE slashes. Inspected in
    #     the real bytes (never guessed): the marker sits at the END of the last
    #     <l> of the verse it names, i.e. it CLOSES the verse it FOLLOWS. So the
    #     text is accumulated across the verse's <l> lines (space-joined) until a
    #     marker completes; the accumulated text (with the marker STRIPPED)
    #     becomes the passage and the marker's number becomes the citation. The
    #     single daṇḍa "/" (half-verse / pada boundary) and double daṇḍa are
    #     ordinary reading text and are KEPT — only the "// Abbr_N //" verse
    #     marker is the citation and is removed. → urn …:sa_brahmabindUpaniSad:1
    #
    # (c) UNADDRESSED PROSE (prose — sa_prajJApAramitAhRdayasUtra). Flat <p>
    #     with no numbering of any kind. Each <p> is a passage cited by a
    #     synthetic 1-based paragraph ordinal "p1", "p2", …, FLAGGED in the
    #     annotation ("addressing" => "prose-ordinal") as non-canonical
    #     addressing so a future re-chunk against a real reference system is
    #     honest. → urn …:sa_prajJApAramitAhRdayasUtra:p1
    #
    # (d) XML:ID-CITED (mass-converted, the P9-4c pure-lg-xml:id recovery —
    #     sa_RgvidhAna). The citation rides only in an @xml:id on the verse
    #     group <lg xml:id="RgV_1.1.1"> (its <l> children are pada rows, NOT
    #     separate passages — same grain as the marker rung); no @n, no in-text
    #     marker, no prose. The citation is the id with its leading "<Abbr>_"
    #     prefix stripped, dotted path kept (RgV_1.1.1 → 1.1.1).
    #     → urn …:sa_RgvidhAna-a1:1.1.1
    #
    #     Rung (d) is a SECOND-PASS FALLBACK (XmlIdExtraction), run only when
    #     rungs (a)/(b)/(c) leave the document empty. This is a frozen-urn
    #     necessity, not an optimization: many already-loaded docs carry
    #     <lg xml:id>/<p xml:id> AND prose, and were loaded via the prose rung
    #     (their group text mashed into ordinals). Emitting xml:id passages
    #     in-line would rewrite those clean urns. Confining rung (d) to
    #     otherwise-empty docs makes it purely additive to the quarantined
    #     "no citable passages" class. (Consequence: a <p xml:id> doc that
    #     carries text is clean-as-prose and stays that way — p-level xml:id is
    #     not recovered; recovering it is a future, frozen-urn-breaking packet.)
    #
    # The rung is recorded in every passage's "addressing" annotation
    # ("attribute" | "verse-marker" | "prose-ordinal" | "xml-id").
    #
    # == Two post-extraction disambiguations (P9-4c fix 3)
    #
    # After extraction, before minting passages, the verse list is repaired so
    # a document is NEVER quarantined for a duplicate citation:
    #   * multi-prefix join — when marker verses carry ≥2 distinct prefixes AND
    #     their bare numbers actually collide (DhvK_1.1 vs DhvA_1.1), the prefix
    #     joins the citation (DhvK.1.1 vs DhvA.1.1). Gated on a real collision
    #     so already-clean multi-prefix files keep their bare urns (frozen-urn).
    #   * collision suffix — any remaining duplicate citation gets a positional
    #     ":b<k>" suffix in document order (second → :b2, third → :b3), the
    #     ddbdp precedent. Documents with no duplicates are untouched.
    #
    # == The accent policy (orig KEPT — the inverse of DdbdpParser)
    #
    # GRETIL's normalization decl (documented in every teiHeader) preserves
    # Vedic accents and other "additional information … accents, capitalization,
    # whitespace" as <orig> elements — optionally paired with a <reg> holding
    # the IAST-conformant plain-text equivalent inside a <choice>. In
    # sa_Rgveda-edAufrecht the accents ride in BARE <orig> (no <choice>/<reg>):
    # "a<orig>̱</orig>gnim" — the combining anudātta U+0331 (macron below) and
    # udātta/svarita U+030D (vertical line above) sit in the <orig>.
    #
    # Because the accented reading is the SCHOLARLY value of a Vedic edition,
    # the policy is the deliberate INVERSE of DdbdpParser's Leiden rule (which
    # keeps <reg>, drops <orig> as pre-regularization spelling): here <orig> is
    # KEPT (its accents are the pristine text we want to preserve) and its
    # paired <reg> — the de-accented search-convenience form — is DROPPED. Our
    # own diacritic-insensitive search form (Passage#text_normalized, generic
    # fold for `san`) is minted downstream regardless, so nothing is lost by
    # dropping the upstream <reg>. <note> (editorial remarks, analytic-only)
    # is likewise dropped. Everything else keeps its text.
    #
    # == Streaming
    #
    # The only Nokogiri entry point is Nokogiri::XML::Reader — a whole-document
    # DOM is never built (sa_Rgveda-edAufrecht is ~5 MB whole; the family rule
    # is the family rule). Text is captured ONLY inside <l> and <p> (and only
    # within <text><body> — the teiHeader is full of <p>/<note> that must never
    # leak). Dropped subtrees (<reg>, <note>) are skipped via a depth stack.
    # Final passage text gets the house whitespace treatment (runs collapse to
    # one space, ends strip) and NFC at this boundary (text_normalized is minted
    # by Passage.new, the P6-4 per-language search form).
    #
    # == Language
    #
    # Read from <text>/@xml:lang (e.g. "sa-Latn"), mapped ISO 639-1 → 639-3
    # (sa → san), script subtag preserved (sa-Latn → san-Latn). Cross-checked
    # against the caller's language (discover peeks the same attribute); a
    # divergence is a cataloguing error, surfaced as ParseError, not smoothed.
    class GretilParser
      # GRETIL tags Indic languages with ISO 639-1; Nabu uses ISO 639-3
      # (conventions.md §4). Script subtags survive the mapping (sa-Latn →
      # san-Latn). Codes already in 639-3 pass through unchanged.
      LANGUAGE_MAP = { "sa" => "san" }.freeze

      # In-text verse marker, PRIMARY pass: "// Abbr_1 //" or "// Abbr_1.2 //"
      # — abbreviation prefix (letters, incl. precomposed non-ASCII — KūrmP_,
      # Nā_), underscore, dotted/comma'd number, DOUBLE-slash delimited. The
      # number is the citation; the whole marker is stripped; the prefix is
      # captured for the multi-prefix disambiguation (fix 3). Byte-identical to
      # the P9-4b regex apart from named captures — so clean docs re-parse
      # unchanged. (Single "/" and "||" daṇḍas are ordinary reading text.)
      MARKER = %r{//\s*(?<prefix>\p{L}[\p{L}\d]*)_(?<num>\d[\d.,]*)\s*//}

      # In-text verse marker, FALLBACK pass (P9-4c fix 2): also accepts the
      # single-pipe form "| Abbr_1,1.1 |" (comma level separators —
      # sa_bAdarAyaNa-brahmasUtra). The opening and closing delimiters must
      # MATCH (\k<delim>), so a lone daṇḍa "|" never trips it. Used ONLY when
      # the primary "//"-marker pass leaves the document empty — so the many
      # already-loaded docs that contain "| Abbr_N |" spans as ordinary reading
      # text (recognized as prose in the primary pass) keep their urns
      # byte-identical (frozen-urn); only the pure pipe-marked docs that the
      # primary pass cannot address are recovered here.
      MARKER_FALLBACK = %r{(?<delim>//|\|)\s*(?<prefix>\p{L}[\p{L}\d]*)_(?<num>\d[\d.,]*)\s*\k<delim>}

      # Leading "<Abbr>_" prefix of a citation xml:id (RgV_1.1.1 → 1.1.1). A
      # bare id with no such prefix (or one that would strip to empty) is kept
      # verbatim.
      ID_PREFIX = /\A\p{L}[\p{L}\d]*_/

      # Strip the "<Abbr>_" prefix from an xml:id, keeping the dotted path.
      def self.strip_id_prefix(id)
        stripped = id.sub(ID_PREFIX, "")
        stripped.empty? ? id : stripped
      end

      # Map an upstream xml:lang tag to Nabu's ISO 639-3 form. nil-safe.
      def self.normalize_language(tag)
        return nil if tag.nil? || tag.empty?

        primary, rest = tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary, primary)
        rest ? "#{mapped}-#{rest}" : mapped
      end

      # One emitted passage: citation suffix, final (collapsed, NFC) text, the
      # addressing rung, lean context annotations, and — for verse-marker
      # rungs — the marker's abbreviation prefix (nil otherwise), used by the
      # multi-prefix disambiguation.
      Verse = Data.define(:citation, :text, :addressing, :context, :prefix)
      private_constant :Verse

      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        verses = extract(source, path: path, language: language)
        verses = apply_multi_prefix(verses)
        verses = disambiguate_collisions(verses)
        build_document(verses, urn: urn, language: language, title: title, path: path)
      end

      private

      # P9-4c fix 3 (multi-prefix). When the marker verses carry ≥2 distinct
      # abbreviation prefixes AND their bare-number citations actually collide
      # (kārikā DhvK_1.1 vs commentary DhvA_1.1), join the prefix into the
      # citation (DhvK.1.1 vs DhvA.1.1) so the two layers do not share a urn.
      #
      # FROZEN-URN SAFETY — the deliberate refinement of the packet's literal
      # rule: the census found 26 files with ≥2 marker prefixes but only a
      # handful collide; the rest were already loaded cleanly with bare-number
      # citations. Firing the join unconditionally on every ≥2-prefix file
      # would rewrite those clean urns. So the join is gated on an ACTUAL
      # collision among the marker verses — which is exactly the currently-
      # quarantined subset. Single-prefix files never reach the join (the
      # ≥2-prefix guard), so a single-prefix collision (Valc 1.70×2) is left
      # for the positional :b<k> suffix below, never prefixed.
      def apply_multi_prefix(verses)
        marker_verses = verses.select { |v| v.addressing == "verse-marker" }
        return verses if marker_verses.filter_map(&:prefix).uniq.size < 2

        bare = marker_verses.map(&:citation)
        return verses if bare.uniq.size == bare.size # no collision → leave bare

        verses.map do |verse|
          next verse unless verse.addressing == "verse-marker" && verse.prefix

          verse.with(citation: "#{verse.prefix}.#{verse.citation}")
        end
      end

      # P9-4c fix 3 (collision tolerance). Deterministically disambiguate any
      # duplicate citation in document order instead of quarantining the whole
      # document (ddbdp precedent): the second occurrence gets a ":b2" suffix,
      # the third ":b3", and so on. A document with no duplicate citations is
      # returned untouched (frozen-urn: clean docs keep byte-identical urns).
      def disambiguate_collisions(verses)
        seen = Hash.new(0)
        verses.map do |verse|
          seen[verse.citation] += 1
          count = seen[verse.citation]
          count == 1 ? verse : verse.with(citation: "#{verse.citation}:b#{count}")
        end
      end

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      # Primary pass, then two frozen-urn-safe fallbacks that fire ONLY when the
      # primary rungs leave the document empty (so they cannot touch any
      # already-loaded doc): the pure lg-xml:id shape (P9-4c fix 1,
      # sa_RgvidhAna), THEN the single-pipe marker variant (fix 2). p-level
      # xml:id is deliberately NOT recovered — a <p xml:id> carrying text
      # already emits as a prose ordinal in the primary pass (that doc is
      # clean-as-prose and frozen), so re-citing it would break the guard (see
      # the file header).
      #
      # ORDER MATTERS (performance): xml:id before pipe. A markerless xml:id
      # doc accumulates its whole body into one buffer (nothing flushes it);
      # running the pipe recognizer over that megabyte buffer re-scans it at
      # every daṇḍa for a "| Abbr_N |" that will never come — quadratic. The
      # xml:id pass (no marker scanning) drains such docs first; the pipe pass
      # then only meets genuine pipe-marked docs, which flush their buffer at
      # every marker and stay linear.
      def extract(source, path:, language:)
        verses = with_io(source) do |io|
          run_extraction(io, path: path, language: language, marker: MARKER)
        end
        return verses unless verses.empty?

        verses = File.open(path, "r") do |io|
          XmlIdExtraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, language: language).call
        end
        return verses unless verses.empty?

        File.open(path, "r") do |io|
          run_extraction(io, path: path, language: language, marker: MARKER_FALLBACK)
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def run_extraction(io, path:, language:, marker:)
        Extraction.new(
          reader: Nokogiri::XML::Reader(io, path), path: path, language: language, marker: marker
        ).call
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(verses, urn:, language:, title:, path:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        verses.each_with_index do |verse, sequence|
          document << Passage.new(
            urn: "#{urn}:#{verse.citation}",
            language: language,
            text: verse.text,
            annotations: annotations(verse),
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable passages found in <text><body>" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def annotations(verse)
        result = { "addressing" => verse.addressing }
        result.merge!(verse.context) unless verse.context.empty?
        result
      end

      # The single-pass Reader state machine. Ignores everything until
      # <text><body>; inside the body it captures text within <l>/<p>, tracks
      # div/lg addressing context, filters the dropped subtrees, and emits a
      # passage at each of the three rung triggers (see the file header).
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[reg note].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        def initialize(reader:, path:, language:, marker: MARKER)
          @reader = reader
          @path = path
          @language = language
          @marker = marker
          @in_body = false
          @text_lang = nil
          @capturing = false     # inside an <l> or <p>
          @buffer = +""
          @drop_depth = nil
          @divs = []             # [{type:, n:, depth:}, …] — addressing context
          @lg_id = nil           # current <lg>/@xml:id (or @n)
          @l_n = nil             # current <l>/@n (rung a), nil otherwise
          @prose_ordinal = 0
          @verses = []
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no <text><body> found" unless @seen_body

          @verses
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
          name = local_name(node)
          return capture_text_lang(node) if name == "text"
          return enter_body(node) if name == "body"
          return unless @in_body
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "div" then push_div(node)
          when "lg" then @lg_id = node.attribute("xml:id") || node.attribute("n")
          when "l" then open_line(node)
          when "p" then open_paragraph(node)
          end
        end

        def end_element(node)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          return unless @in_body

          case local_name(node)
          when "body" then @in_body = false
          when "div" then @divs.pop if @divs.last && @divs.last[:depth] == node.depth
          when "lg" then @lg_id = nil
          when "l" then close_line
          when "p" then close_paragraph
          end
        end

        def text_node(node)
          return unless @in_body && @capturing && !dropping?

          @buffer << node.value.to_s
          scan_markers if @l_n.nil? # markers only segment unaddressed text (rung b)
        end

        # -- header / body gating -----------------------------------------------

        def capture_text_lang(node)
          # The FIRST <text> (the edition) carries the language; nested <text>
          # in the header (rare) is ignored once we have it.
          @text_lang = node.attribute("xml:lang") if @text_lang.nil?
        end

        def enter_body(node)
          check_language!
          @in_body = true
          @seen_body = true
          @in_body = false if node.empty_element?
        end

        def check_language!
          mapped = GretilParser.normalize_language(@text_lang)
          return if mapped.nil? || mapped == @language

          raise ParseError, "#{@path}: language mismatch: caller says #{@language.inspect}, " \
                            "<text>/@xml:lang is #{@text_lang.inspect} (→ #{mapped.inspect})"
        end

        # -- rung (a): attribute-cited <l>/@n -----------------------------------

        def open_line(node)
          separate
          @capturing = true
          @l_n = node.attribute("n")
          @capturing = false if node.empty_element?
        end

        def close_line
          emit(@l_n, addressing: "attribute", context: line_context) if @l_n && !@l_n.empty?
          # No @n: buffer persists (rung b accumulates the verse across lines).
          @l_n = nil
          @capturing = false
        end

        def line_context
          context = {}
          context["lg"] = @lg_id if @lg_id && !@lg_id.empty?
          div_path = @divs.filter_map { |d| [d[:type], d[:n]] if d[:type] && d[:n] }.to_h
          context["div"] = div_path unless div_path.empty?
          context
        end

        # -- rung (b): in-text verse markers ------------------------------------

        # Emit every completed "// Abbr_N //" marker in the buffer, closing the
        # verse it follows (text before the marker) and stripping the marker.
        def scan_markers
          while (match = @marker.match(@buffer))
            before = @buffer[0...match.begin(0)]
            emit_text(before, match[:num], addressing: "verse-marker", context: {}, prefix: match[:prefix])
            @buffer = +@buffer[match.end(0)..]
          end
        end

        # -- rung (c): unaddressed prose ----------------------------------------

        def open_paragraph(node)
          @capturing = true
          @capturing = false if node.empty_element?
        end

        def close_paragraph
          @capturing = false
          # A marker inside the <p> already emitted (rung b) and cleared the
          # buffer; only markerless prose falls through to an ordinal.
          return if @buffer.strip.empty?

          @prose_ordinal += 1
          emit("p#{@prose_ordinal}", addressing: "prose-ordinal", context: {})
        end

        # -- emission -----------------------------------------------------------

        def emit(citation, addressing:, context:, prefix: nil)
          emit_text(@buffer, citation, addressing: addressing, context: context, prefix: prefix)
          @buffer = +""
        end

        def emit_text(raw, citation, addressing:, context:, prefix: nil)
          text = Normalize.nfc(raw.gsub(/[[:space:]]+/, " ").strip)
          return if text.empty?

          @verses << Verse.new(
            citation: citation, text: text, addressing: addressing, context: context, prefix: prefix
          )
        end

        # A single space between consecutive captured chunks (multi-<l> verses),
        # so pada boundaries do not fuse words. No-op when the buffer is empty
        # or already ends in whitespace.
        def separate
          @buffer << " " if !@buffer.empty? && !@buffer.end_with?(" ")
        end

        def push_div(node)
          return if node.empty_element?

          @divs << { type: node.attribute("type"), n: node.attribute("n"), depth: node.depth }
        end

        def dropping?
          !@drop_depth.nil?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction

      # P9-4c rung (d): the xml:id fallback pass. Emits one passage per verse
      # group (<lg> or self-contained <p>) that carries an @xml:id, citation =
      # the id with its "<Abbr>_" prefix stripped (RgV_1.1.1 → 1.1.1); the
      # group's <l>/<p> text is the passage. Same streaming discipline as
      # Extraction (Reader only, <reg>/<note> dropped, text confined to
      # <text><body>). Run ONLY when the primary pass found nothing, so it is
      # invisible to every already-loaded document (frozen-urn).
      class XmlIdExtraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[reg note].freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS

        def initialize(reader:, path:, language:)
          @reader = reader
          @path = path
          @language = language
          @in_body = false
          @capturing = false
          @drop_depth = nil
          @group_id = nil # xml:id of the open <lg>/<p>, or nil
          @group_buffer = +""
          @verses = []
        end

        def call
          @reader.each { |node| process(node) }
          @verses
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
          name = local_name(node)
          return enter_body(node) if name == "body"
          return unless @in_body
          return if dropping?

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "lg", "p" then open_group(node)
          when "l" then open_line(node)
          end
        end

        def end_element(node)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          return unless @in_body

          case local_name(node)
          when "body" then @in_body = false
          when "lg", "p" then close_group
          when "l" then @capturing = false
          end
        end

        def text_node(node)
          return unless @in_body && @capturing && !dropping?

          @group_buffer << node.value.to_s
        end

        def enter_body(node)
          @in_body = !node.empty_element?
        end

        # A <p> holds its citable text directly; an <lg> holds it in <l>
        # children (captured on open_line). Either way the group buffer starts
        # fresh so the passage is exactly this group's text.
        def open_group(node)
          @group_id = node.attribute("xml:id")
          @group_buffer = +""
          @capturing = local_name(node) == "p" && !node.empty_element?
        end

        def open_line(node)
          @group_buffer << " " if !@group_buffer.empty? && !@group_buffer.end_with?(" ")
          @capturing = !node.empty_element?
        end

        def close_group
          emit_group if @group_id && !@group_id.empty?
          @group_id = nil
          @group_buffer = +""
          @capturing = false
        end

        def emit_group
          text = Normalize.nfc(@group_buffer.gsub(/[[:space:]]+/, " ").strip)
          return if text.empty?

          @verses << Verse.new(
            citation: GretilParser.strip_id_prefix(@group_id),
            text: text, addressing: "xml-id", context: {}, prefix: nil
          )
        end

        def dropping?
          !@drop_depth.nil?
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :XmlIdExtraction
    end
  end
end
