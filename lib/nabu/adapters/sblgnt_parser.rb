# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser for one SBLGNT plain-text book file (P11-5) — Faithlife/SBLGNT's
    # data/sblgnt/text/*.txt, the SBL Greek New Testament. A standalone,
    # individually tested parser family the Sblgnt adapter composes.
    #
    # == The format
    #
    # Verse-per-line TSV after a first line carrying the Greek book title:
    #
    #   ΚΑΤΑ ΜΑΡΚΟΝ
    #   Mark 1:1<TAB>Ἀρχὴ τοῦ εὐαγγελίου Ἰησοῦ ⸀χριστοῦ.
    #   Mark 1:2<TAB>⸀Καθὼς γέγραπται …
    #
    # The ref column is "Book C:V" (book token = the upstream file stem:
    # Matt, Mark, 1Cor, 3John, Phlm…). The ⸀⸂⸃ sigla embedded in the verse
    # text are the upstream edition's apparatus cross-references (the
    # sblgntapp variant files are not ingested) — kept verbatim, canonical
    # means canonical. One verse = one passage, urn <doc-urn>:<C>.<V>.
    class SblgntParser
      # "Mark 1:1<TAB>text" — the book token is [\w]+ (digits lead 1Cor/3John).
      LINE = /\A(?<book>\S+)\s(?<chapter>\d+):(?<verse>\d+)\t(?<text>.+?)\s*\z/

      def parse(path, urn:, language:, title:)
        document = Nabu::Document.new(urn: urn, language: language, title: title,
                                      canonical_path: File.expand_path(path))
        verse_lines(path).each { |match| append_verse(document, urn, language, match) }
        raise ParseError, "#{path}: no verse lines found" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The Greek title on the first line — what the adapter's discover peeks
      # for document titles. nil for an empty file.
      def title(path)
        first = File.open(path, "r:UTF-8", &:gets)
        title = first.to_s.strip
        title.empty? ? nil : Normalize.nfc(title)
      end

      private

      # Every line after the first must be a verse line (or blank); anything
      # else is upstream drift the parse must not paper over.
      def verse_lines(path)
        File.readlines(path, encoding: "UTF-8").drop(1).filter_map.with_index(2) do |line, lineno|
          next if line.strip.empty?

          LINE.match(line) ||
            raise(ParseError, "#{path}:#{lineno}: not a 'Book C:V<TAB>text' verse line: #{line.strip[0, 60].inspect}")
        end
      end

      def append_verse(document, urn, language, match)
        document << Nabu::Passage.new(
          urn: "#{urn}:#{match[:chapter]}.#{match[:verse]}",
          language: language,
          text: Normalize.nfc(match[:text]),
          sequence: document.size,
          annotations: { "citation" => "#{match[:book]} #{match[:chapter]}:#{match[:verse]}" }
        )
      end
    end
  end
end
