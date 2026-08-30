# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # Streaming parser for DACON's own POS format (the `dacon-pos` family,
    # P88-A4) — censused from all 4 real files of Zenodo deposit 12887386
    # (2026-08-29):
    #
    #   one line   = one `form<sep>TAG` token — but the deposit is
    #                internally INCONSISTENT: cnew12/cnew13_14 separate with
    #                runs of spaces, cnew17/cnew19 with a TAB; cnew13_14
    #                opens with a UTF-8 BOM; three of four carry a
    #                `form<sep>POS` header line; line ends are CRLF except
    #                cnew12's LF. All four shapes parse here.
    #   `<utt>`    = the sentence boundary (sometimes with a trailing tab,
    #                censused in cnew17) — the corpus's only segmentation.
    #   `fol` tag  = a foliation marker (`[1]`, `*fn30a`), not a word.
    #
    # == Passage minting
    #
    # - One passage per <utt>-delimited block, urn "<document-urn>:utt-<n>"
    #   (1-based block index); the trailing block after the last <utt> mints
    #   too, and a file with no <utt> at all (cnew12, the 233-token
    #   Ukubāhāḥ inscription) honestly yields one passage.
    # - text = the forms joined with " " (IAST romanization — words, unlike
    #   the Tibetan tsheg case), NFC at the boundary (upstream verified
    #   NFC-stable).
    # - annotations = { "tokens" => [{"form","pos"}, …], "folios" => […] }.
    #   fol-tagged tokens enter NEITHER the text NOR the token list — they
    #   ride "folios" in order (absent when the block has none). There is no
    #   lemma anywhere in the deposit: no "lemma" key is ever minted (the
    #   soas-pos honest-absence stance).
    #
    # == The 26 dirty lines (censused 2026-08-29, cnew13_14 ×21 + cnew17 ×5)
    #
    # The deposit carries a small tail of irregular token lines: TAG-LESS
    # forms ("..", "*saṃvat", "thva\t"), forms GLUED to their tag with no
    # separator ("śuklaadj" — zero-width chars included), separator-only
    # lines ("\t"), and exactly ONE three-field line ("nan    na
    # case.abl"). Quarantining two of four documents over 26 lines in a
    # 29k-token gold corpus would be dishonest, so: a whitespace-only line
    # skips like a blank; one field mints a form-only token (no "pos" key —
    # honest absence, never an invented tag; a glued line IS one field);
    # two or more fields anchor on the LAST separator (the soas-pos rsplit
    # logic — the tag charset is the narrow side), extra fields riding the
    # form verbatim. Upstream shape drift is caught at FETCH (every file
    # sits under a hard sha256 pin), not here.
    class DaconPosParser
      BOM = "\u{FEFF}"
      HEADER = /\Aform(?:\t+|\s{2,})POS\z/
      SEPARATOR = /\t+|\s{2,}/

      # Same signature family as SoasPosParser#parse; +source+ is a path
      # (String) or an IO-like (StringIO in tests).
      def parse(source, urn:, language:, title: nil, canonical_path: nil, metadata: {})
        document = Nabu::Document.new(
          urn: urn, language: language, title: title, metadata: metadata,
          canonical_path: canonical_path || source.to_s
        )

        blocks(source).each_with_index do |block, index|
          document << build_passage(block, document_urn: urn, language: language,
                                           block_no: index + 1, sequence: index)
        end

        raise Nabu::ParseError, "#{source}: no form/POS token lines found" if document.empty?

        document
      end

      private

      # The <utt>-delimited token blocks, empties dropped (a leading <utt>
      # or double boundary mints nothing).
      def blocks(source)
        blocks = [[]]
        each_line(source) do |line, line_no|
          next if line.empty?
          next if line_no == 1 && line.match?(HEADER)

          if line.start_with?("<utt>")
            blocks << []
          elsif (token = split_token(line))
            blocks.last << token
          end
        end
        blocks.reject { |block| block.all? { |token| token["pos"] == "fol" } }
      end

      def each_line(source)
        line_no = 0
        read_lines(source) do |raw|
          line_no += 1
          line = raw.sub(/\r?\n?\z/, "")
          line = line.delete_prefix(BOM) if line_no == 1
          yield line, line_no
        end
      end

      # A String is always a path (the ConlluParser rule).
      def read_lines(source, &block)
        if source.is_a?(String)
          File.open(source, "r:UTF-8") { |io| io.each_line(&block) }
        else
          source.each_line(&block)
        end
      end

      def split_token(line)
        fields = line.split(SEPARATOR).reject(&:empty?)
        case fields.size
        when 0 then nil
        when 1 then { "form" => fields[0] }
        else { "form" => fields[0..-2].join(" "), "pos" => fields[-1] }
        end
      end

      def build_passage(block, document_urn:, language:, block_no:, sequence:)
        folios, tokens = block.partition { |token| token["pos"] == "fol" }
        text = Nabu::Normalize.nfc(tokens.map { |token| token["form"] }.join(" "))
        annotations = { "tokens" => tokens }
        annotations["folios"] = folios.map { |token| token["form"] } if folios.any?
        Nabu::Passage.new(
          urn: "#{document_urn}:utt-#{block_no}",
          language: language,
          text: text,
          annotations: annotations,
          sequence: sequence
        )
      end
    end
  end
end
