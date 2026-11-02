# frozen_string_literal: true

require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # Parser for the cgpg-vert family (P153): the Sketch Engine vertical
    # files of the CGPG Patrologia Graeca deposit (Zenodo 19915273) — the
    # OCR of a Migne volume, lemmatized and POS-tagged by machine.
    #
    # == The format (censused over all 33 deposit files, 2026-11-02)
    #
    # CRLF lines (PG 123/124/126 are LF — read either way). One
    # <doc id="PG 101 - AI processed"> wrapper per file, then one block
    # per token:
    #
    #   <w id="PDF Page 14, Line 1 - word id 1">
    #   «Ἐπειδὴ<TAB>επειδη<TAB>ἐπειδή<TAB>επειδη<TAB>I+Conj
    #   </w>
    #
    # The five columns are the OCR surface (punctuation attached), a folded
    # (lowercased, accentless) copy of it, the lemma, a folded lemma, and
    # the POS. The id carries the token's position on the page IMAGE of the
    # scanned volume (PDF page, OCR line, running word id). It is not
    # well-formed XML (the form lines are bare), so this is a line reader,
    # not an XML parser — streaming, one file at a time.
    #
    # == Grain
    #
    # Passage = one PDF page (urn <doc-urn>:p<page>): the page is the only
    # citable unit the deposit has (no work, chapter or column markup —
    # Migne's column numbers are not in the files). Passage text = the
    # page's tokens, space-joined per OCR line, lines joined by "\n";
    # line-end word breaks stay split as OCR'd ("γεν" / "ναίαις").
    # Tokens ride the "tokens" annotation as {form, lemma, pos, line} —
    # the Indexer's lemma lane reads form + lemma. The folded columns are
    # recomputable and are not stored.
    #
    # == Quirks (kept honest, never repaired)
    #
    # - "∅" in an analysis column (unanalysed punctuation, »): the surface
    #   rides, the lemma/pos keys are left out — no "∅" lemma ever reaches
    #   the index.
    # - empty form column (2,229 tokens deposit-wide, "\t∅\t∅\t∅\t∅" or
    #   "\t\t∅\t∅\t∅"): nothing to show; counted as empty_form_tokens.
    # - a lone "#NOM?" line in place of the token row, its </w> missing (66
    #   deposit-wide) — a spreadsheet formula error upstream that ate the
    #   token: counted as lost_tokens.
    class CgpgVertParser
      DOC_OPEN = /\A<doc id="([^"]*)">\z/
      TOKEN_OPEN = /\A<w id="PDF Page (\d+), Line (\d+) - word id (\d+)">\z/
      NO_ANALYSIS = "∅"

      def parse(path, urn:, language:, title:, metadata: {})
        state = read(path)
        raise ParseError, "#{path}: no tokens" if state[:pages].empty?

        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path, title: title,
          metadata: metadata.merge(
            "doc_id" => state[:doc_id],
            "empty_form_tokens" => state[:empty],
            "lost_tokens" => state[:lost]
          ).compact
        )
        state[:pages].each_with_index do |(page, lines), index|
          document << Nabu::Passage.new(
            urn: "#{urn}:p#{page}", language: language, sequence: index,
            text: lines.values.map { |tokens| tokens.map { |t| t["form"] }.join(" ") }.join("\n"),
            annotations: { "pdf_page" => page, "tokens" => lines.values.flatten }
          )
        end
        document
      end

      private

      def read(path)
        state = { doc_id: nil, pages: {}, empty: 0, lost: 0, position: nil }
        SourceRead.utf8_file(path, label: "cgpg").each_line(chomp: true) { |line| step(state, line, path) }
        state
      end

      def step(state, line, path)
        if (match = line.match(TOKEN_OPEN))
          state[:position] = [Integer(match[1], 10), Integer(match[2], 10)]
        elsif (match = line.match(DOC_OPEN))
          raise ParseError, "#{path}: a second <doc> element (#{match[1]})" if state[:doc_id]

          state[:doc_id] = match[1]
        elsif !line.empty? && !line.start_with?("</")
          token_row(state, line, path)
        end
      end

      def token_row(state, line, path)
        columns = line.split("\t", -1)
        raise ParseError, "#{path}: a token row outside any <w> block" if state[:position].nil?
        return state[:lost] += 1 unless columns.size == 5
        return state[:empty] += 1 if columns[0].empty?

        page, line_no = state[:position]
        lines = state[:pages][page] ||= {}
        (lines[line_no] ||= []) << token(columns, line_no)
      end

      def token(columns, line_no)
        form, _form_folded, lemma, _lemma_folded, pos = columns
        { "form" => Normalize.nfc(form), "lemma" => analysis(lemma) && Normalize.nfc(lemma),
          "pos" => analysis(pos), "line" => line_no }.compact
      end

      def analysis(value)
        value unless value.empty? || value == NO_ANALYSIS
      end
    end
  end
end
