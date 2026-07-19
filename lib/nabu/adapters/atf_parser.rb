# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "atf" (P31-2): one C-ATF document block — the plain-text
    # transliteration format of the CDLI bulk dump (oracc.museum.upenn.edu/
    # doc/help/editinginatf/cdliatf/). The family core owns the LINE GRAMMAR
    # only; corpus policy (language maps, catalog joins, urn prefixes) stays
    # in each adapter, so the eBL-ATF dialect (P31-3) can register against
    # the same core without inheriting CDLI decisions. The dialect seams are
    # the constructor policy (language_map / related_target) plus the
    # #directive, #classify_at, #unrecognized and #document_language methods
    # a dialect subclass overrides — override points, not configuration soup
    # (EblAtfParser is the first registrant beside the C-ATF core).
    #
    # == The line grammar (censused over the full 86.9 MB dump, 2026-07-19)
    #
    #   &P000001 = designation       document header (one per block; the
    #                                caller splits the file into blocks —
    #                                "& P519727" with a stray space is a
    #                                real upstream typo and accepted)
    #   #atf: lang sux               language protocol. The dump carries 12
    #                                spelling variants ("#atf lang", "#atf.
    #                                lang", "#atflang", "#atf: lang = peo",
    #                                "#atf: lang sux, akk") — matched
    #                                tolerantly, value mapped through the
    #                                adapter-supplied language_map, first
    #                                code of a multi-language value wins and
    #                                the verbatim value is kept in metadata.
    #   #atf: use lexical            protocol flags → metadata "atf_use".
    #   #tr.en: …  /  #tr-en: …      per-LINE translations (en 94,968 · ts
    #                                9,386 · de/it/fr/fa/dk/es/ca; "#tr:"
    #                                74) → the line's "tr" annotation,
    #                                keyed by the upstream code verbatim.
    #                                CDLI translations are line-grained
    #                                inline riders, not documents — the
    #                                -en-sibling decision is per-dialect.
    #   #link: def A = Q000365 = …   composite link definitions; the dump's
    #   #atf def linktext A = Q…     older spelling (3 blocks) too.
    #   #link: Q000398 …             a bare document-level composite link.
    #   # anything else              editorial comments ("# seal
    #                                impression", "# = P000456 obv. ii 1")
    #                                → "comments" on the open line, else
    #                                document metadata.
    #   @tablet / @envelope / @seal 1  object declarations
    #   @obverse / @surface a / @column 1  surfaces and columns
    #   @m=division / @law 15 / @colophon  logical divisions (open
    #                                vocabulary incl. upstream typos
    #                                "@sobverse", "@coumn" — anything not an
    #                                object/surface/column is a division,
    #                                kept verbatim as the open line's
    #                                "division"; never invented-corrected,
    #                                never a quarantine)
    #   $ beginning broken           state lines → "states" on the NEXT
    #                                minted line; trailing states land on
    #                                the last line as "states_after" (a
    #                                lineless document keeps them in
    #                                metadata "states").
    #   >>Q000002 014                composite alignment of the previous
    #                                text line; letter targets (">>A 21")
    #                                resolve through the link definitions →
    #                                "links" annotation + document
    #                                "related" (urn targets minted by the
    #                                adapter-supplied related_target hook).
    #   =: …  /  || A 791            variant / parallel riders on the
    #                                previous text line ("variants" /
    #                                "parallels" annotations, verbatim).
    #   1. text / 1'. / a001. / A1=1.  numbered text lines: label = every-
    #                                thing before the first ". " —
    #                                VERBATIM, the corpus's own citation
    #                                (primes, letter prefixes, "0", ranges
    #                                "4-6", bilingual "A1=1"). A label with
    #                                EMPTY text (359 corpus-wide) mints
    #                                nothing.
    #   anything else                ParseError → honest quarantine (188
    #                                junk lines / 156 documents corpus-wide:
    #                                missing-dot labels, a stray BOM, "&
    #                                blank space" mid-document).
    #
    # == Passage identity (the corpus's own grain: line within face/column)
    #
    #   urn = <doc-urn>[:<object>][:<face>][:<column>]:<label>
    #
    # Face/column/object segments are the @-line bodies verbatim, spaces →
    # "." ("surface.a", "seal.1", "composite.text"). The object segment
    # joins ONLY when the block declares more than one object (2,718 docs —
    # tablet-and-envelope pairs restart their line numbers per object;
    # censused: keying without the object leaves 22,849 collisions, with it
    # 3,916). Remaining duplicate suffixes take the house positional
    # disambiguator (:b2, :b3 — the DdbdpParser/Oracc precedent): never
    # quarantine, never merge, clean documents keep byte-identical urns.
    #
    # == Zero-line blocks
    #
    # A block whose lines never mint (uninscribed sealings, catalog stubs;
    # 2,063 corpus-wide) parses to a zero-passage document marked
    # "text_layer" => "none" (the ogham/isicily metadata-only precedent) —
    # catalogued, never quarantined.
    #
    # Text is NFC at this boundary (Normalize.nfc); the akk/sux search fold
    # (conventions §9) applies downstream via each passage's language. NO
    # #lem lines exist in C-ATF — the family emits no lemma annotations, so
    # nothing from this family can ever enter the lemma index as gold.
    class AtfParser
      # One parsed line-in-waiting.
      Line = Struct.new(:label, :object, :face, :column, :division, :text, :annotations,
                        keyword_init: true)
      private_constant :Line

      HEADER = /\A&\s*([A-Z]\d+)\s*(?:=\s*(.*))?\z/
      ATF_LANG = /\A#atf[\s:.=]*lang[\s:=]+(\S+)/
      ATF_USE = /\A#atf:?\s+use\s+(\S+)/
      LINK_DEF = /\A#(?:link:?\s*def|atf\s+def\s+linktext)\s+(\S+)\s*=\s*([A-Z]\d+)/
      LINK_BARE = /\A#link:?\s+([A-Z]\d+)/
      TRANSLATION = /\A#tr(?:[.-]([a-z]+))?\s*:\s*(.*)\z/
      STRUCTURE = /\A@\s*(.*)\z/
      STATE = /\A\$\s*(.*)\z/
      LINK_LINE = /\A>>\s*(\S+)?\s*(.*)\z/
      VARIANT = /\A=:\s*(.*)\z/
      PARALLEL = /\A\|\|\s*(.*)\z/
      TEXT_LINE = /\A(\S+)\.(?:\s+(.*))?\z/

      # Structure vocabulary (censused). Everything else after "@" is a
      # division — open vocabulary, verbatim, never guessed.
      SURFACES = %w[obverse reverse left right top bottom edge surface face seal].freeze
      OBJECTS = %w[tablet object envelope bulla prism fragment tag cone brick sealing
                   barrel cylinder block macehead].freeze

      # +language_map+: upstream #atf lang code → stored code (adapter
      # policy; unmapped codes fall to +default_language+ honestly).
      # +related_target+: a callable minting a journal-addressable target
      # from a composite id ("Q000002" → "urn:nabu:cdli:q000002"); nil
      # keeps ids out of document "related" (links annotations still carry
      # them verbatim).
      def initialize(language_map: {}, default_language: "und", related_target: nil)
        @language_map = language_map
        @default_language = default_language
        @related_target = related_target
      end

      # Parse one document block (the text from its "&" header up to the
      # next). +language_fallback+ (the adapter's catalog-derived code) is
      # used when the block carries no #atf lang line; +title_fallback+
      # when the header carries no designation; +metadata+ is the
      # adapter's base metadata (catalog fields, facets, related) — parser
      # keys merge into it, "related" unions. +line+ is the block's first
      # line number in +path+, for honest error messages.
      def parse(block, urn:, path:, line: 1, language_fallback: nil, title_fallback: nil,
                metadata: {})
        state = parse_lines(block, urn: urn, path: path, first_line: line)
        state[:language_fallback] = language_fallback
        trailing_states(state)
        language = document_language(state)
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path,
          title: state[:title] || title_fallback,
          metadata: document_metadata(state, metadata)
        )
        mint_passages(state, document, language)
        document
      end

      private

      # -- the line loop --------------------------------------------------------

      def parse_lines(block, urn:, path:, first_line:)
        state = blank_state(urn, path)
        block.each_line.with_index(first_line) do |raw, number|
          state[:line_number] = number
          text = raw.chomp.rstrip
          next if text.strip.empty?

          consume(text.strip, state)
        end
        state
      end

      def blank_state(urn, path)
        {
          urn: urn, path: path, line_number: nil,
          title: nil, language_raw: nil, atf_use: [],
          link_defs: {}, related: [], doc_comments: [], doc_states: [],
          lines: [], states: [], objects: [],
          object: nil, face: nil, column: nil, division: nil,
          empty_lines: 0
        }
      end

      def consume(text, state)
        case text
        when HEADER then header(Regexp.last_match, state)
        when /\A#/ then directive(text, state)
        when STRUCTURE then structure(Regexp.last_match(1), state)
        when STATE then state[:states] << Regexp.last_match(1).rstrip
        when VARIANT then rider(state, "variants", Regexp.last_match(1))
        when PARALLEL then rider(state, "parallels", parallel_entry(Regexp.last_match(1), state))
        when /\A>>/ then composite_link(text, state)
        when TEXT_LINE then text_line(Regexp.last_match, state)
        else
          unrecognized(text, state)
        end
      end

      # The fall-through seam: what the grammar cannot classify. The core
      # quarantines honestly; a dialect with additional line types the loop
      # has no case for (eBL-ATF "// …" parallels, P31-3) overrides this and
      # falls back to super for genuine junk.
      def unrecognized(text, state)
        fail_line(state, "unrecognized line #{text.inspect}")
      end

      def header(match, state)
        fail_line(state, "second document header #{match[0].inspect} inside one block") if state.dig(:header, :seen)
        state[:header] = { seen: true }
        title = match[2].to_s.strip
        state[:title] = Normalize.nfc(title) unless title.empty?
      end

      # Every "#" line: protocol, translation, link definition, or comment.
      # A dialect adapter overrides this seam for its own directives
      # (eBL-ATF #note:/#tr.en with extents) without touching the loop.
      def directive(text, state)
        if (match = ATF_LANG.match(text))
          state[:language_raw] ||= match[1]
        elsif (match = ATF_USE.match(text))
          state[:atf_use] << match[1]
        elsif (match = LINK_DEF.match(text))
          state[:link_defs][match[1]] = match[2]
          add_related(state, match[2])
        elsif (match = LINK_BARE.match(text))
          add_related(state, match[1])
        elsif (match = TRANSLATION.match(text))
          translation(match, state)
        else
          comment(text.delete_prefix("#").strip, state)
        end
      end

      # Translation lines ride the open text line, keyed by the upstream
      # code verbatim ("en", "ts", "de"…; a bare "#tr:" keys "tr").
      def translation(match, state)
        code = match[1] || "tr"
        value = Normalize.nfc(match[2].rstrip)
        line = state[:lines].last
        return comment("tr.#{code}: #{value}", state) if line.nil?

        translations = (line.annotations["tr"] ||= {})
        translations[code] = [translations[code], value].compact.reject(&:empty?).join("\n")
      end

      def comment(text, state)
        return if text.empty?

        target = state[:lines].last
        if target
          (target.annotations["comments"] ||= []) << Normalize.nfc(text)
        else
          state[:doc_comments] << Normalize.nfc(text)
        end
      end

      # -- structure ------------------------------------------------------------

      def structure(body, state)
        body = body.rstrip
        return if body.empty?

        token = body.split(/\s+/).first.downcase.delete_suffix("?").delete_suffix(":")
        rest = body.split(/\s+/, 2)[1]
        case classify_at(token)
        when :column then state[:column] = rest || body
        when :surface
          # "@surface a"/"@face a" name their face in the argument (the
          # keyword is scaffolding); "@obverse", "@seal 1" ARE the face.
          state[:face] = slugify(%w[surface face].include?(token) && rest ? rest : body)
          state[:column] = nil
        when :object
          state[:object] = slugify(token == "object" && rest ? rest : body)
          state[:objects] << state[:object] unless state[:objects].include?(state[:object])
          state[:face] = nil
          state[:column] = nil
        else
          state[:division] = Normalize.nfc(body)
        end
      end

      # The @-token classifier — a dialect seam (eBL-ATF adds its own
      # structure vocabulary here).
      def classify_at(token)
        return :column if token == "column"
        return :surface if SURFACES.include?(token)
        return :object if OBJECTS.include?(token)

        :division
      end

      # -- riders on the previous text line -------------------------------------

      def rider(state, key, entry)
        line = state[:lines].last
        fail_line(state, "#{key} rider with no preceding text line") if line.nil?
        (line.annotations[key] ||= []) << entry
      end

      def parallel_entry(body, state)
        target, ref = body.rstrip.split(/\s+/, 2)
        resolved = resolve_link(target, state)
        entry = { "target" => resolved }
        entry["line"] = ref if ref && !ref.empty?
        entry
      end

      def composite_link(text, state)
        match = LINK_LINE.match(text)
        target = match && match[1]
        fail_line(state, "composite link with no target: #{text.inspect}") if target.nil?

        resolved = resolve_link(target, state)
        add_related(state, resolved)
        entry = { "target" => resolved }
        ref = match[2].to_s.rstrip
        entry["line"] = ref unless ref.empty?
        rider(state, "links", entry)
      end

      # ">>A 21" resolves through the block's link definitions; an id
      # ("Q000002", "P000456") passes through; an unresolvable letter stays
      # verbatim — recorded, never guessed.
      def resolve_link(target, state)
        state[:link_defs][target] || target
      end

      def add_related(state, target)
        return unless @related_target && target.match?(/\A[A-Z]\d+\z/)

        minted = @related_target.call(target)
        state[:related] << minted if minted && !state[:related].include?(minted)
      end

      # -- text lines -----------------------------------------------------------

      def text_line(match, state)
        text = match[2].to_s.rstrip
        if text.empty?
          state[:empty_lines] += 1
          return
        end

        annotations = {}
        annotations["states"] = state[:states] unless state[:states].empty?
        annotations["division"] = state[:division] if state[:division]
        state[:states] = []
        state[:lines] << Line.new(
          label: match[1], object: state[:object], face: state[:face],
          column: state[:column], division: state[:division],
          text: Normalize.nfc(text), annotations: annotations
        )
      end

      # -- assembly -------------------------------------------------------------

      # #atf lang mapped through the adapter's table; the first code of a
      # multi-language value wins; no lang line → the adapter's catalog
      # fallback; unmapped → default. Whenever the verbatim value differs
      # from the final code it is kept ("language_raw") — mapping is never
      # silent.
      def document_language(state)
        raw = state[:language_raw]
        return state[:language_fallback] || @default_language if raw.nil?

        code = raw.split(/[,&_\s]+/).first.to_s
        mapped = @language_map.fetch(code, @default_language)
        state[:unmapped_language] = raw if raw != mapped
        mapped
      end

      def document_metadata(state, base)
        result = base.dup
        result["designation"] = state[:title] if state[:title]
        result["atf_use"] = state[:atf_use] unless state[:atf_use].empty?
        result["language_raw"] = state[:unmapped_language] if state[:unmapped_language]
        result["comments"] = state[:doc_comments] unless state[:doc_comments].empty?
        related = (Array(base["related"]) + state[:related]).uniq
        result["related"] = related unless related.empty?
        result["states"] = state[:doc_states] unless state[:doc_states].empty?
        result["text_layer"] = "none" if state[:lines].empty?
        result
      end

      def mint_passages(state, document, language)
        multi_object = state[:objects].size > 1
        seen = Hash.new(0)
        state[:lines].each_with_index do |line, sequence|
          suffix = suffix_for(line, multi_object)
          seen[suffix] += 1
          suffix = "#{suffix}:b#{seen[suffix]}" if seen[suffix] > 1
          document << Nabu::Passage.new(
            urn: "#{state[:urn]}:#{suffix}", language: language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
      end

      # Leftover $ states after the last text line: the last line keeps
      # them as "states_after"; a lineless document keeps them in metadata
      # (documents are already built by then — via state[:doc_states]).
      def trailing_states(state)
        return if state[:states].empty?

        if (line = state[:lines].last)
          line.annotations["states_after"] = state[:states]
        else
          state[:doc_states].concat(state[:states])
        end
        state[:states] = []
      end

      def suffix_for(line, multi_object)
        segments = []
        segments << line.object if multi_object && line.object
        segments << line.face if line.face
        segments << slugify(line.column) if line.column
        segments << slugify(line.label)
        segments.join(":")
      end

      # An @-body or label as a urn segment: NFC, whitespace runs → ".".
      def slugify(text)
        Normalize.nfc(text.strip.gsub(/\s+/, "."))
      end

      def fail_line(state, message)
        raise ParseError,
              "#{state[:path]}:#{state[:line_number]}: #{state[:urn]}: #{message}"
      end
    end
  end
end
