# frozen_string_literal: true

require "strscan"

module Nabu
  module Adapters
    # Parser family for Penn Treebank labeled bracketing (.psd) — the
    # historical-corpus lingua franca of the Penn parsed-corpora school
    # (HeliPaD now; YCOE and native IcePaHC are the planned siblings). A
    # standalone, individually tested component adapters compose, with the
    # house parser call shape: #parse(source, urn:, language:, title:,
    # canonical_path:) plus the one family knob, +id_prefix:+ (below).
    #
    # == The format (censused against test/fixtures/helipad/)
    #
    # A .psd file is a stream of balanced-parenthesis tree blocks separated
    # by blank lines, one block per sentence/token-unit:
    #
    #   ( (IP-MAT (CODE <P_7>)
    #             (NP-SBJ *exp*)
    #             (NP-PRD (Q^N^PL Manega-manag) …)
    #             (BEDI^3^PL uuaron-wesan) …
    #             (. .-.))
    #     (ID OSHeliandC.1.1-5))
    #
    # - The top-level block is UNLABELED: its children are the content tree
    #   (IP-MAT/IP-SUB/…) and exactly one (ID <token>) leaf — the stable
    #   upstream citation id, minted verbatim into the passage urn.
    # - Preterminal leaves are (TAG text). Three leaf kinds:
    #   - (CODE <…>)   editorial/metrical markers (see below), not text;
    #   - empty categories — text starting with "*" (*exp*, *ICH*-1, *T*-1,
    #     *con*, …) or exactly "0" (zero complementizer/relativizer) — the
    #     standard Penn null elements: no surface text, kept in the tokens
    #     lane (the tree is incomplete without them);
    #   - real tokens. HeliPaD fuses surface form and lemma into one atom,
    #     "form-lemma" (Manega-manag, uuaron-wesan, ",-,"), split on the
    #     LAST hyphen (fixture README; a form containing hyphens keeps
    #     them). An unhyphenated leaf is a form-only token with NO lemma
    #     key — never an invented lemma (YCOE ships exactly that shape).
    # - Tags carry morphology inline, "^"-separated after the POS head
    #   (Q^N^PL, BEDI^3^PL, GE+VBDI^3^SG, PRO$^N^3^SG): split on the FIRST
    #   caret into "pos" + "morph" (morph absent when the tag has none —
    #   VB, P, CONJ). Nonterminal labels (NP-SBJ, CP-REL-1, IPX-SUB=0) are
    #   never interpreted; they survive verbatim in the "tree" annotation
    #   and as the "tag" of empty categories.
    # - Parens can NEVER appear inside leaf text (the format's own escape
    #   for that is -LRB-/-RRB-; none censused in HeliPaD), so the reader
    #   tokenizes on parens/whitespace — a real lexer over balanced trees,
    #   not a regex hack. Unbalanced input, stray top-level atoms, a block
    #   without its (ID …), or a preterminal with several atoms are all
    #   Nabu::ParseError (quarantine), never papered over.
    #
    # == Metrical / editorial markers: the (CODE …) lane
    #
    # HeliPaD's metre and codicology ride (CODE <…>) leaves interleaved
    # with the tokens: <R_n> verse-line n begins, <C> caesura (the
    # half-line boundary of Germanic alliterative verse), <F_n> fitt n
    # begins, <MS_5a> folio, <P_7> edition page, <COM:HELIAND_C> comment.
    # The parser does NOT interpret them — it strips the angle brackets and
    # keeps each marker AT ITS POSITION in the tokens lane ({"code" => "C"}
    # between the two half-lines' tokens), so lineation, caesurae and fitt
    # boundaries stay reconstructible downstream without baking HeliPaD
    # semantics into the family.
    #
    # == Passage minting (tree block = passage)
    #
    # - urn = "<document-urn>:<id tail>", where the tail is the block's ID
    #   with "<id_prefix>." stripped when the caller passes +id_prefix:+ and
    #   the ID starts with it ("OSHeliandC.1.1-5" → "1.1-5"); otherwise the
    #   full ID verbatim. The verbatim ID always rides annotations["id"].
    # - sequence = block ordinal from 0 (a block whose tree carries no
    #   surface text mints no passage but keeps its ordinal — the PROIEL
    #   convention).
    # - text = token forms in tree order, single-spaced, with closing
    #   punctuation forms (only [,.;:!?] censused) attached to the
    #   preceding token; NFC at this boundary (whole file, once).
    #
    # == Annotations
    #
    #   "tokens" => the in-order lane: {"form","lemma","pos","morph"} for
    #               real tokens (absent fields mint no key — the lean-hash
    #               convention the lemma indexer reads), {"tag","empty"}
    #               for null elements, {"code"} for CODE markers.
    #   "id"     => the (ID …) token verbatim.
    #   "tree"   => the whole block re-serialized as a single-line
    #               S-expression (atoms verbatim, one space between
    #               elements) — the retained syntax lane, round-trippable
    #               to the constituency structure.
    #
    # == The family seam (what varies across Penn corpora)
    #
    # - ID conventions: HeliPaD "OSHeliandC.<tree-ordinal>.<line-range>";
    #   YCOE "cocathom1,ÆCHom_I,_1:10.1" (file,text:citation); IcePaHC
    #   "2008.OFSI.NAR-SAG,.3". The parser treats the ID as an OPAQUE
    #   required token; +id_prefix:+ is the one minting convenience, and an
    #   adapter with a different grain does its own tail derivation from
    #   annotations["id"].
    # - Lemmatization: fused form-lemma leaves (HeliPaD, IcePaHC ≥0.9) vs
    #   none in the .psd (YCOE — its lemmas live in sibling .pos files an
    #   adapter would join OUTSIDE this parser). Both shapes parse here.
    # - Tag vocabularies differ per corpus (Old Saxon vs OE vs Icelandic
    #   tag sets); the parser never interprets tags beyond the "^" morph
    #   separator (absent in YCOE: "pos" is then the whole tag).
    # - Document grain: adapters decide file-vs-corpus grain; the parser
    #   parses ONE file into ONE document.
    class PennPsdParser
      # Penn null elements: *…* (optionally trace-indexed), bare *, or 0.
      EMPTY_CATEGORY = /\A(?:\*[^\s()]*|0)\z/
      # Closing punctuation that attaches to the preceding token (the only
      # punctuation forms censused in HeliPaD; opening quotes would need a
      # family extension, noted rather than guessed).
      NO_SPACE_BEFORE = /\A[,.;:!?]+\z/
      private_constant :EMPTY_CATEGORY, :NO_SPACE_BEFORE

      # Same signature family as EpidocParser/ConlluParser/ProielParser#parse.
      def parse(source, urn:, language:, title: nil, canonical_path: nil, id_prefix: nil)
        path = resolve_canonical_path(source, canonical_path)
        blocks = read_blocks(source, path)
        raise ParseError, "#{path}: no tree blocks found" if blocks.empty?

        build_document(blocks, urn: urn, language: language, title: title,
                               path: path, id_prefix: id_prefix)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      # Whole-file read: .psd is line-oriented plain text, and the largest
      # real member of the family (heliand.psd) is 3.4 MB — far under the
      # only-stream-above-~5MB line, and the balanced reader needs no DOM.
      # NFC once, here, at the adapter boundary.
      def read_blocks(source, path)
        content = source.is_a?(String) ? File.read(source, encoding: Encoding::UTF_8) : source.read
        PsdReader.new(Normalize.nfc(content), path).blocks
      end

      def build_document(blocks, urn:, language:, title:, path:, id_prefix:)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        blocks.each_with_index do |block, sequence|
          sentence = PsdExtraction.new(block, path: path, ordinal: sequence + 1).call
          next if sentence.text.empty? # a tree of only CODE markers/empties has no surface

          document << passage(sentence, urn: urn, language: language,
                                        sequence: sequence, id_prefix: id_prefix, block: block)
        end
        raise ParseError, "#{path}: every tree block was surface-empty" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      def passage(sentence, urn:, language:, sequence:, id_prefix:, block:)
        Passage.new(
          urn: "#{urn}:#{urn_tail(sentence.id, id_prefix)}",
          language: language,
          text: sentence.text,
          annotations: { "tokens" => sentence.tokens, "id" => sentence.id,
                         "tree" => serialize(block) },
          sequence: sequence
        )
      end

      # The HeliPaD-shaped convenience: "OSHeliandC.1.1-5" minus its text
      # prefix is the citation tail scholars use. Anything else stays the
      # verbatim ID (uniqueness is the conformance suite's check).
      def urn_tail(id, id_prefix)
        prefix = id_prefix && "#{id_prefix}."
        prefix && id.start_with?(prefix) ? id.delete_prefix(prefix) : id
      end

      # One-line canonical S-expression of a parsed node — atoms verbatim,
      # single spaces — the round-trippable "tree" annotation.
      def serialize(node)
        return node if node.is_a?(String)

        "(#{node.map { |child| serialize(child) }.join(' ')})"
      end

      # The balanced-parenthesis lexer/reader. Tokens: "(", ")", atoms
      # ([^\s()]+ — leaf text can never contain parens, see class notes).
      # Yields the top-level blocks as nested arrays (atom = String,
      # subtree = Array); any imbalance or stray top-level atom raises.
      class PsdReader
        def initialize(content, path)
          @scanner = StringScanner.new(content)
          @path = path
        end

        def blocks
          result = []
          loop do
            skip_whitespace
            break if @scanner.eos?

            raise ParseError, "#{@path}: stray atom #{@scanner.peek(20).inspect} outside any tree block" \
              unless @scanner.skip("(")

            result << subtree
          end
          result
        end

        private

        def subtree
          children = []
          loop do
            skip_whitespace
            raise ParseError, "#{@path}: unbalanced parentheses (unexpected end of file)" if @scanner.eos?

            if @scanner.skip("(") then children << subtree
            elsif @scanner.skip(")") then return children
            else children << @scanner.scan(/[^\s()]+/)
            end
          end
        end

        def skip_whitespace
          @scanner.skip(/\s+/)
        end
      end
      private_constant :PsdReader

      # A finished sentence: the upstream ID, the reconstructed surface
      # text, and the ordered tokens lane.
      PsdSentence = Data.define(:id, :text, :tokens)
      private_constant :PsdSentence

      # Walks one top-level block: peels the (ID …) leaf off the top level,
      # then a depth-first walk of the content collecting the tokens lane
      # and surface text.
      class PsdExtraction
        def initialize(block, path:, ordinal:)
          @block = block
          @path = path
          @ordinal = ordinal
          @tokens = []
          @text = +""
        end

        def call
          id = extract_id!
          content_nodes.each { |node| walk(node) }
          PsdSentence.new(id: id, text: @text.freeze, tokens: @tokens)
        end

        private

        def extract_id!
          ids = @block.filter_map { |node| leaf_text(node) if leaf?(node) && node.first == "ID" }
          return ids.first if ids.size == 1

          raise ParseError, "#{@path}: tree block ##{@ordinal} (document order) has #{ids.size} " \
                            "(ID …) nodes; exactly one is required"
        end

        def content_nodes
          @block.reject { |node| leaf?(node) && node.first == "ID" }
        end

        # A preterminal: [label, atom]. Anything with subtree children
        # recurses; a node mixing several atoms is malformed.
        def leaf?(node)
          node.is_a?(Array) && node.size == 2 && node.all?(String)
        end

        def leaf_text(node)
          node.fetch(1)
        end

        def walk(node)
          raise ParseError, "#{@path}: tree block ##{@ordinal}: malformed node #{node.inspect}" \
            unless node.is_a?(Array) && node.first.is_a?(String)

          return add_leaf(node.first, leaf_text(node)) if leaf?(node)

          children = node.drop(1)
          if children.any?(String)
            raise ParseError, "#{@path}: tree block ##{@ordinal}: node #{node.first.inspect} mixes " \
                              "atoms and subtrees"
          end

          children.each { |child| walk(child) }
        end

        def add_leaf(label, atom)
          if label == "CODE"
            @tokens << { "code" => atom[/\A<(.*)>\z/, 1] || atom }
          elsif atom.match?(EMPTY_CATEGORY)
            @tokens << { "tag" => label, "empty" => atom }
          else
            token = token_hash(label, atom)
            append_surface(token.fetch("form"))
            @tokens << token
          end
        end

        # form-lemma on the LAST hyphen; tag = pos^morph on the FIRST caret
        # (class notes). Absent fields mint no key.
        def token_hash(label, atom)
          split = atom.rindex("-")
          split = nil if split&.zero? || split == atom.length - 1
          form = split ? atom[0...split] : atom
          caret = label.index("^")
          token = { "form" => form }
          token["lemma"] = atom[(split + 1)..] if split
          token["pos"] = caret ? label[0...caret] : label
          token["morph"] = label[(caret + 1)..] if caret
          token
        end

        def append_surface(form)
          @text << " " unless @text.empty? || form.match?(NO_SPACE_BEFORE)
          @text << form
        end
      end
      private_constant :PsdExtraction
    end
  end
end
