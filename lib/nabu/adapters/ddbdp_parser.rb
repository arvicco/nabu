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
    #               final intent (the paired <del> renders in ⟦…⟧ beside it);
    #               standalone (place="above" insertions) it is equally part
    #               of the text
    #   <supplied>  editorial restorations ARE the readable text — print
    #               editions read straight through their square brackets
    #   <unclear>   dotted-but-read letters
    #   <expan>     full content INCLUDING the <ex> expansions — abbreviations
    #               read expanded ("plur(imam)" reads "plurimam")
    #   <num>       the numeral's text content (@value is metadata)
    #
    # KEEP, RENDERED IN LEIDEN DOUBLE BRACKETS ⟦…⟧ (owner-ruled 2026-08-10; see below):
    #   <del>       text deleted in antiquity but legible — reading text in
    #               Leiden, printed inside ⟦…⟧; nesting nests the brackets
    #
    # DROP (apparatus/metadata, never reading text):
    #   <rdg>       rejected variant readings (dropped from the text, captured
    #               into the "apparatus" annotation — see "The apparatus
    #               layer" below)
    #   <orig>      pre-regularization spellings
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
    # dropped <orig> counts nothing, a <del> inside a dropped <rdg> renders
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
    #   urn = <document-urn>[:<textpart-path>][:b<k>]:<lb n>
    #
    # The textpart path (ancestor div[@type="textpart"]/@n values, in order)
    # appears only when textpart divs exist — :r:3 for recto line 3, plain :3
    # for an unpartitioned papyrus.
    #
    # The :b<k> segment (k ≥ 2) is the IMPLICIT RESTART BLOCK (P5-1). Some
    # DDbDP files restart their line numbering mid-document — multiple
    # <lb n="1"/> inside one <ab>, with no textpart divs to disambiguate
    # (aegyptus.89.240 is the exemplar; 12,288 documents quarantined on
    # duplicate urns in the 2026-07-04 first sync). Papyrologically such a
    # restart usually IS a new text block — a column, fragment, or recto/
    # verso the encoder left unpartitioned — so the urn treats it as one: an
    # implicit block segment, shaped like a synthetic textpart, sits between
    # the textpart path and the line number. Blocks are detected by URN
    # COLLISION, not by numeric comparison: when a line's default suffix
    # equals one already minted in this document (within the same textpart
    # context — the counter resets at every textpart boundary), the next
    # block opens (b2, then b3, …) and the line is re-minted inside it,
    # looping until unique. The first block never carries a label.
    #
    # Collision-triggered (rather than "n is not monotonically increasing")
    # is a FROZEN-URN safety decision: these urns are frozen forever once
    # loaded, and any document that parsed cleanly before P5-1 had, by
    # definition, zero suffix collisions — so the mechanism provably never
    # engages for it and its urns stay byte-identical (the 49,060 documents
    # loaded before the fix re-parse as "skipped"). A monotonicity heuristic
    # could fire on already-loaded documents with odd-but-unique numbering
    # (non-numeric @n like "12/13", out-of-order editorial numbering) and
    # silently re-mint frozen urns. Restart documents themselves never
    # entered the catalog (they quarantined), so their urns were free to
    # define here. Trade-off accepted: when a restarted block begins at a
    # number the previous block never reached (block one is lines 5-7,
    # block two restarts at 1), its first lines land in the previous
    # block's namespace and the block opens only at the first collision —
    # urns stay unique and stable, merely blind to the block boundary; and
    # a real textpart literally named "b2" cannot collide with a synthetic
    # block because every minted suffix passes the same uniqueness check.
    #
    # <lb break="no"/> means the word continues
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
    # whitespace treatment: runs collapse to one space, ends strip, NFC
    # (text_normalized is minted by Passage.new — the P6-4 per-language
    # search form). The tension is deliberate: inside
    # extraction the preserved spacing decides word boundaries; after
    # extraction the passage is normal prose and follows house rules.
    #
    # Lines that end empty after extraction (all content dropped/lost) are
    # skipped; a document with zero citable lines is a ParseError. Content
    # inside <ab> before the first <lb> is not citable (upstream puts only
    # whitespace there) and is discarded.
    #
    # == <del> renders ALWAYS in ⟦…⟧ (P6-2 → owner ruling 2026-08-10; conventions.md §5)
    #
    # In Leiden double brackets ⟦…⟧ mean *deleted in antiquity but legible*:
    # the scribe crossed the text out (cross-strokes, slashes, wash-out), yet
    # the editor reads every letter — so print editions print the text,
    # inside the brackets. Cancelled is not deleted: reading text, not
    # apparatus. History: the original policy dropped <del> wholesale, which
    # erased the ~40 documents that are cancellations end to end
    # (o.claud.3.457, cpr.6.3, bgu.1.179, apf.59.139 — zero citable lines,
    # quarantined); P6-2 recovered exactly that class via a document-scoped
    # fallback pass; an owner-delegated ruling (2026-08-10) adopted the
    # faithful general rule — <del> ALWAYS renders in ⟦…⟧, partial
    # cancellations included — retiring both the blanket drop and the
    # fallback machinery (single standard pass again). The corpus-wide
    # consequence (9,696 affected documents measured at ruling time) is a
    # deliberate, journaled re-parse: packet 79-3b, not this parser patch.
    #
    # The rendering: "⟦" where the del opens, "⟧" where it closes, exactly
    # the gap-marker philosophy (a multi-line cancellation prints one
    # opening and one closing bracket, as in print practice; nested dels
    # nest their brackets). Everything else about the policy is unchanged
    # inside the kept del: rdg/orig/note/figure still drop, gaps still mark,
    # supplied/unclear still count, lbs still delimit (restart blocks
    # included). Every line any part of whose content lies in a cancellation
    # carries {"leiden" => {"cancelled" => true}}. A <del> inside a DROPPED
    # branch (rdg/orig) still drops with that branch — the branch as a whole
    # is not reading text. Lines whose entire content is a del are now
    # citable ("⟦…⟧" is non-empty text): the resurrection class.
    #
    # One structural exception guards the frozen-urn law: inside a <subst>,
    # upstream duplicates a line-spanning <lb> into BOTH branches (add and
    # del each carry their own copy, so either branch reads alone —
    # bgu.1.100's revision history). With both branches now kept, only the
    # <add> branch's copy fires as a line boundary; the del branch's copy is
    # the SAME physical line break and is suppressed (firing it would mint a
    # colliding suffix and re-mint frozen urns via the implicit-block
    # machinery). Scope-tested nearest-first, so a subst nested inside a
    # cancellation del keeps its add-branch <lb> live.
    #
    # == Annotations (lean; only non-empty keys)
    #
    #   {"leiden" => {"gaps" => [{"reason","quantity","unit"}…],   # kept gaps
    #                 "supplied_chars" => <grapheme count>,        # restored
    #                 "unclear_chars"  => <grapheme count>,        # dotted
    #                 "hands" => ["m2", …],                        # handShift
    #                 "cancelled" => true},                        # any <del> touched the line
    #    "languages" => ["lat", …],   # inline xml:lang scopes differing from
    #                                 # the document language, mapped (la→lat)
    #    "apparatus" => [{"type","lemma","resp","readings"}…]}  # see below
    #
    # supplied_chars/unclear_chars count non-whitespace grapheme clusters —
    # "letters restored", the number a print edition's brackets would enclose.
    #
    # == The apparatus layer (<app>/<lem>/<rdg>)
    #
    # The editorial apparatus is kept as STRUCTURE beside the text, never in
    # it: the passage text is exactly the lemma reading it always was (the
    # layer only adds the "apparatus" key), and every <app> in kept content
    # becomes one entry on the line where the <app> opens:
    #
    #   {"type"     => "editorial" | "alternative" | …,   # @type, verbatim
    #    "lemma"    => "<the lem rendered as the passage text renders it>",
    #    "resp"     => "BL 7.99",                         # lem/@resp, verbatim
    #    "readings" => [{"text" => "<rdg rendered>",
    #                    "resp" => "Original Edition",     # rdg/@resp
    #                    "apparatus" => [<entry>…]}…]}     # apps nested in the rdg
    #
    # Absent attributes leave their key out; "lemma" and each reading's
    # "text" are always present (an empty <rdg/> reads "" — the reading
    # omits the lemma). DDbDP attributes variants by @resp — the editor,
    # Berichtigungsliste entry or edition that proposed the reading — never
    # by manuscript @wit sigla, so "resp" is the witness field here.
    #
    # Readings render under the SAME Leiden policy as the text (gap → "[…]",
    # reg over orig, del in ⟦…⟧, supplied/unclear/expan read through,
    # note/figure drop). An <app> nested inside a reading contributes its
    # lemma to the reading's text and is itself recorded on the reading's
    # "apparatus"; an <app> nested inside a lemma is kept content and gets
    # its own entry, after its enclosing one (document order). An <app>
    # inside a dropped branch (<orig>) drops with that branch. A line break
    # inside a lemma or reading renders as " | " — "|" glued to both sides
    # for <lb break="no"/> — and the entry is recorded once, on the line
    # where its <app> opened; a line that extracts empty (and is therefore
    # not a passage) takes its entries with it. The rdg subtree never
    # touches the line machinery: its <lb>s are not boundaries, its gaps,
    # hands and certainty counts never reach the "leiden" annotation.
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
    class DdbdpParser < StreamingTeiParser
      # DDbDP tags languages with ISO 639-1 "la"; Nabu uses ISO 639-3 "lat"
      # (conventions.md §4). Script subtags survive the mapping (la-Grek →
      # lat-Grek). "grc" is already 639-3 and passes through.
      LANGUAGE_MAP = { "la" => "lat" }.freeze

      # The single lacuna marker every <gap> contributes (see file header).
      GAP_MARKER = "[…]"

      # Leiden double brackets — ancient cancellation, legible text. Emitted
      # around every <del>'s kept content (owner-ruled 2026-08-10; see file header).
      CANCELLATION_OPEN = "⟦"
      CANCELLATION_CLOSE = "⟧"

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
      Line = Data.define(:urn_suffix, :text, :leiden, :languages, :apparatus)
      private_constant :Line

      # In-buffer line-break sentinels for lemma/reading rendering (control
      # characters XML 1.0 cannot carry, so they never collide with text).
      BREAK = "\u0002"
      NO_BREAK = "\u0001"
      private_constant :BREAK, :NO_BREAK

      # Final form of a lemma or reading buffer: the house whitespace
      # treatment, edge breaks trimmed, breaks rendered " | " (plain) or
      # "|" (break="no"), NFC.
      def self.render_apparatus_text(buffer)
        text = buffer.gsub(/[[:space:]]+/, " ")
                     .gsub(/\A[ #{BREAK}#{NO_BREAK}]+|[ #{BREAK}#{NO_BREAK}]+\z/o, "")
                     .gsub(/ ?#{NO_BREAK} ?/o, "|")
                     .gsub(/ ?#{BREAK} ?/o, " | ")
        Normalize.nfc(text)
      end

      def self.break_sentinel(node)
        node.attribute("break") == "no" ? NO_BREAK : BREAK
      end

      # One <app> under construction. Mutable while the stream runs (a lemma
      # may span lines, so the Line holding it is minted before it closes);
      # #to_h is taken only after extraction completes.
      class AppEntry
        attr_reader :depth, :readings
        attr_accessor :lem_depth

        def initialize(node)
          @depth = node.depth
          @type = node.attribute("type")
          @resp = nil
          @lemma = +""
          @lem_depth = nil
          @readings = []
        end

        def open_lem(node)
          @resp = node.attribute("resp")
          @lem_depth = node.depth unless node.empty_element?
        end

        def lem_open?
          !@lem_depth.nil?
        end

        def <<(value)
          @lemma << value
        end

        def to_h
          entry = {}
          entry["type"] = @type if @type
          entry["lemma"] = DdbdpParser.render_apparatus_text(@lemma)
          entry["resp"] = @resp if @resp
          entry["readings"] = @readings unless @readings.empty?
          entry
        end
      end
      private_constant :AppEntry

      # The open <app> elements of one reading scope (the edition's kept
      # content, or one <rdg>'s content): routes lemma text to every open
      # lemma (an app nested in a lemma feeds both lemmas) and answers
      # whether a <lem>/<rdg> is a direct child of the innermost app.
      class AppStack
        def initialize
          @entries = []
        end

        # Returns the new entry (nil for an empty <app/>).
        def open_app(node)
          return nil if node.empty_element?

          entry = AppEntry.new(node)
          @entries << entry
          entry
        end

        def open_lem(node)
          entry = child_of_top(node)
          entry&.open_lem(node)
        end

        # The innermost app when +node+ is its direct child, else nil.
        def child_of_top(node)
          entry = @entries.last
          entry if entry && node.depth == entry.depth + 1
        end

        def emit(value)
          @entries.each { |entry| entry << value if entry.lem_open? }
        end

        def close(name, node)
          entry = @entries.last
          return unless entry

          if name == "lem" && entry.lem_depth == node.depth
            entry.lem_depth = nil
          elsif name == "app" && entry.depth == node.depth
            @entries.pop
          end
        end
      end
      private_constant :AppStack

      # One <rdg> subtree, rendered under the Leiden policy into a reading
      # hash. Consumes every Reader event from the rdg's start to its end
      # tag — the line machinery never sees them, exactly as when the whole
      # subtree was dropped. Nested apps keep their lemma in the text and
      # are recorded on the reading; their own readings capture recursively.
      class ReadingCapture
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        DROPPED_ELEMENTS = %w[orig note figure].freeze

        def self.empty_reading(node)
          { "text" => "", "resp" => node.attribute("resp") }.compact
        end

        def initialize(node)
          @depth = node.depth
          @resp = node.attribute("resp")
          @buffer = +""
          @apps = AppStack.new
          @entries = [] # apps nested in this reading, document order
          @drop_depth = nil
          @del_depths = []
          @subst_depths = []
          @child = nil # the open nested <rdg> capture
          @child_entry = nil
          @done = false
        end

        def done?
          @done
        end

        def reading
          result = { "text" => DdbdpParser.render_apparatus_text(@buffer) }
          result["resp"] = @resp if @resp
          result["apparatus"] = @entries.map(&:to_h) unless @entries.empty?
          result
        end

        def process(node)
          return delegate(node) if @child

          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then emit(node.value.to_s) unless @drop_depth
          end
        end

        private

        def delegate(node)
          @child.process(node)
          return unless @child.done?

          @child_entry.readings << @child.reading
          @child = nil
          @child_entry = nil
        end

        def start_element(node)
          return if @drop_depth

          name = node.name.split(":").last
          case name
          when "rdg" then open_rdg(node)
          when *DROPPED_ELEMENTS then drop(node)
          when "app" then open_app(node)
          when "lem" then @apps.open_lem(node)
          when "gap"
            emit(GAP_MARKER)
            drop(node)
          when "del" then open_del(node)
          when "subst" then @subst_depths << node.depth unless node.empty_element?
          when "lb" then emit(DdbdpParser.break_sentinel(node)) unless duplicate_subst_del_lb?
          end
        end

        def end_element(node)
          if @drop_depth
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          return @done = true if node.depth == @depth

          name = node.name.split(":").last
          case name
          when "del" then close_del(node)
          when "subst" then @subst_depths.pop if @subst_depths.last == node.depth
          when "app", "lem" then @apps.close(name, node)
          end
        end

        def open_app(node)
          entry = @apps.open_app(node)
          @entries << entry if entry
        end

        def open_rdg(node)
          entry = @apps.child_of_top(node)
          return drop(node) unless entry
          return entry.readings << ReadingCapture.empty_reading(node) if node.empty_element?

          @child = ReadingCapture.new(node)
          @child_entry = entry
        end

        def open_del(node)
          return if node.empty_element?

          @del_depths << node.depth
          emit(CANCELLATION_OPEN)
        end

        def close_del(node)
          return unless @del_depths.last == node.depth

          @del_depths.pop
          emit(CANCELLATION_CLOSE)
        end

        # The main extraction's nearest-scope rule: an <lb> inside a subst's
        # <del> branch duplicates the <add> branch's copy.
        def duplicate_subst_del_lb?
          return false if @del_depths.empty? || @subst_depths.empty?

          @del_depths.last > @subst_depths.last
        end

        def drop(node)
          @drop_depth = node.depth unless node.empty_element?
        end

        def emit(value)
          @buffer << value
          @apps.emit(value)
        end
      end
      private_constant :ReadingCapture

      # The identity family this instance parses (P104-3): DDbDP by
      # default (idno "ddb-hybrid" minting urn:nabu:ddbdp:…, frozen), or
      # the DCLP literary tree of the same idp.data repo (idno "dclp" —
      # the numeric papyri.info/dclp/<n> key; the dclp-hybrid is
      # non-unique upstream — minting urn:nabu:dclp:<n>, the Papyri
      # adapter's DCLP lane). Everything else — Leiden policy, line
      # minting, restart blocks — is identical between the two corpora;
      # only the identity idno and the urn namespace differ.
      def initialize(idno_type: "ddb-hybrid", urn_namespace: "ddbdp")
        super()
        @idno_type = idno_type
        @urn_namespace = urn_namespace
      end

      # Same signature family as the sibling parsers. +metadata+ (P104-1)
      # rides the caller's document-grain claims (the papyri adapter's
      # HGV/TM idnos) onto the Document verbatim.
      def parse(source, urn:, language:, title: nil, canonical_path: nil, metadata: {})
        path = resolve_canonical_path(source, canonical_path)
        lines = extract_lines(source, path: path, urn: urn, language: language)
        build_document(lines, urn: urn, language: language, title: title, path: path,
                              metadata: metadata)
      end

      private

      def extract_lines(source, path:, urn:, language:)
        extract(source, path: path, urn: urn, language: language,
                        idno_type: @idno_type, urn_namespace: @urn_namespace)
      end

      def extraction_class = Extraction

      def build_document(lines, urn:, language:, title:, path:, metadata: {})
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path,
                                metadata: metadata)
        lines.each_with_index do |line, sequence|
          document << Passage.new(
            urn: "#{urn}:#{line.urn_suffix}",
            language: language,
            text: line.text,
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
        result["apparatus"] = line.apparatus.map(&:to_h) unless line.apparatus.empty?
        result
      end

      # The single-pass Reader state machine. Header phase captures the
      # ddb-hybrid idno; body phase reacts only inside div[@type="edition"],
      # where it maintains the textpart path, the keep/drop state and the
      # current line buffer (see the policy in the file header).
      class Extraction < StreamingTeiParser::Walker
        # Subtrees that are never reading text (see file header). <gap> is
        # handled separately: marker first, then its children drop too;
        # <del> is handled separately too — kept, rendered in ⟦…⟧ (owner ruling 2026-08-10).
        DROPPED_ELEMENTS = %w[rdg orig note figure].freeze
        private_constant :DROPPED_ELEMENTS

        def initialize(reader:, path:, urn:, language:, idno_type: "ddb-hybrid",
                       urn_namespace: "ddbdp")
          super(reader: reader, path: path)
          @urn = urn
          @language = language
          @idno_type = idno_type
          @urn_namespace = urn_namespace
          @del_depths = [] # open <del> depths (rendered in ⟦…⟧, ruled 2026-08-10)
          @subst_depths = [] # open <subst> depths (duplicate-lb suppression)
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
          @block = 1 # implicit restart-block ordinal (see file header)
          @seen_suffixes = {} # suffix => true, for collision-triggered blocks
          @apps = AppStack.new # open <app>s in kept content (the apparatus layer)
          @reading = nil # the open <rdg> capture, which consumes its whole subtree
          @reading_entry = nil
          @pending_apparatus = [] # entries opened before any line (attach to the next)
        end

        def call
          @reader.each { |node| @reading ? capture_reading(node) : process(node) }
          raise ParseError, "#{@path}: no div[@type=\"edition\"] found" unless @edition_seen

          @lines
        end

        private

        def start_element(node)
          return if dropping?
          return edition_element(node) if in_edition?

          case local_name(node)
          when "idno"
            @capture_idno = node.attribute("type") == @idno_type && !node.empty_element?
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
          return open_cancellation(node) if name == "del"
          return open_reading(node) if name == "rdg"

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
          when "subst" then @subst_depths << node.depth unless node.empty_element?
          when "app" then open_app(node)
          when "lem" then @apps.open_lem(node)
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
          when "del" then close_cancellation(node)
          when "supplied" then @supplied_depths.pop if @supplied_depths.last == node.depth
          when "unclear" then @unclear_depths.pop if @unclear_depths.last == node.depth
          when "subst" then @subst_depths.pop if @subst_depths.last == node.depth
          when "app", "lem" then @apps.close(local_name(node), node)
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
          @apps.emit(value)
          count_certainty(value)
        end

        # -- the apparatus layer (see file header) --------------------------------

        def open_app(node)
          entry = @apps.open_app(node) or return

          (@current ? @current[:apparatus] : @pending_apparatus) << entry
        end

        # A <rdg> that is a direct child of an open kept <app> is captured
        # into a reading; any other <rdg> drops wholesale as it always did.
        def open_reading(node)
          entry = @apps.child_of_top(node)
          if entry.nil?
            @drop_depth = node.depth unless node.empty_element?
          elsif node.empty_element?
            entry.readings << ReadingCapture.empty_reading(node)
          else
            @reading = ReadingCapture.new(node)
            @reading_entry = entry
          end
        end

        def capture_reading(node)
          @reading.process(node)
          return unless @reading.done?

          @reading_entry.readings << @reading.reading
          @reading = nil
          @reading_entry = nil
        end

        def count_certainty(value)
          return if @supplied_depths.empty? && @unclear_depths.empty?

          graphemes = value.gsub(/[[:space:]]/, "").grapheme_clusters.size
          @current[:supplied] += graphemes unless @supplied_depths.empty?
          @current[:unclear] += graphemes unless @unclear_depths.empty?
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
            raise ParseError, "#{@path}: no <idno type=\"#{@idno_type}\"> found in teiHeader"
          end

          minted = "urn:nabu:#{@urn_namespace}:#{@hybrid.tr(';', ':')}"
          return if minted == @urn

          raise ParseError, "#{@path}: urn mismatch: caller says #{@urn.inspect}, " \
                            "<idno type=\"#{@idno_type}\"> #{@hybrid.inspect} mints #{minted.inspect}"
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
          return if duplicate_subst_del_lb?

          n = node.attribute("n")
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.nil? || n.empty?

          finish_line
          @apps.emit(DdbdpParser.break_sentinel(node)) # a lemma spanning the break
          @current = {
            n: n, textpath: @textparts.map { |part| part[:n] },
            buffer: +"", gaps: [], supplied: 0, unclear: 0, hands: [], languages: [],
            cancelled: !@del_depths.empty?, # line opened inside a kept cancellation
            apparatus: @pending_apparatus
          }
          @pending_apparatus = []
        end

        def finish_line
          current = @current
          @current = nil
          return unless current

          text = Normalize.nfc(current[:buffer].gsub(/[[:space:]]+/, " ").strip)
          return if text.empty? # everything dropped/lost: not a citable line

          @lines << Line.new(
            urn_suffix: mint_suffix(current),
            text: text, leiden: leiden(current), languages: current[:languages],
            apparatus: current[:apparatus]
          )
        end

        # Restart-aware suffix minting (see "Passage = the LINE" in the file
        # header). The default shape <textpart-path?>:<lb n> is tried first;
        # a collision with an already-minted suffix means the line numbering
        # restarted, so the next implicit block opens (b2, b3, …) and the
        # line is re-minted inside it, looping until unique. Documents whose
        # suffixes never collide — everything that parsed cleanly before
        # P5-1 — never enter the loop body and mint byte-identically.
        def mint_suffix(current)
          loop do
            block = @block > 1 ? ["b#{@block}"] : []
            suffix = (current[:textpath] + block + [current[:n]]).join(":")
            if @seen_suffixes.key?(suffix)
              @block += 1
            else
              @seen_suffixes[suffix] = true
              return suffix
            end
          end
        end

        def leiden(current)
          result = {}
          result["gaps"] = current[:gaps] unless current[:gaps].empty?
          result["supplied_chars"] = current[:supplied] if current[:supplied].positive?
          result["unclear_chars"] = current[:unclear] if current[:unclear].positive?
          result["hands"] = current[:hands] unless current[:hands].empty?
          result["cancelled"] = true if current[:cancelled]
          result
        end

        # -- <del> rendering (P6-2 → the 2026-08-10 ruling; see file header) ---------

        # An <lb> inside a subst's <del> branch is upstream's DUPLICATE copy
        # of the line break (when a correction spans a line break, both
        # branches carry their own <lb> so either reads alone — bgu.1.100's
        # revision history). The kept <add> branch's copy is the boundary
        # that fires; firing the del branch's copy too would mint the same
        # suffix twice and re-mint frozen urns via the implicit-block
        # collision machinery. Nearest-scope test — the innermost open del
        # must sit INSIDE the innermost open subst: a subst nested inside a
        # cancellation <del> keeps its own add-branch <lb> live.
        def duplicate_subst_del_lb?
          return false if @del_depths.empty? || @subst_depths.empty?

          @del_depths.last > @subst_depths.last
        end

        # <del> start: keep the content, open the Leiden double bracket in
        # place (the marker sits exactly where the cancellation begins,
        # gap-marker style; nested dels nest their brackets).
        def open_cancellation(node)
          return if node.empty_element?

          @del_depths << node.depth
          mark_cancelled(CANCELLATION_OPEN)
        end

        def close_cancellation(node)
          return unless @del_depths.last == node.depth

          @del_depths.pop
          mark_cancelled(CANCELLATION_CLOSE)
        end

        def mark_cancelled(marker)
          return unless @current

          @current[:buffer] << marker
          @apps.emit(marker)
          @current[:cancelled] = true
        end

        # -- leiden milestones ---------------------------------------------------

        def add_gap(node)
          # Marker + annotation only when a line is open; then drop any
          # children (<desc>, <certainty> — metadata, not text).
          if @current
            @current[:buffer] << GAP_MARKER
            @apps.emit(GAP_MARKER)
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
          @block = 1 # a textpart is its own line-numbering universe
        end

        def end_div(node)
          if node.depth == @edition_depth
            finish_line # defensive; </ab> normally closed the last line
            @edition_depth = nil
          elsif @textparts.last && @textparts.last[:depth] == node.depth
            finish_line # lines never span textparts
            @textparts.pop
            @block = 1 # a textpart is its own line-numbering universe
          end
        end
      end
      private_constant :Extraction
    end
  end
end
