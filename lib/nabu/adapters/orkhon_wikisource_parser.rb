# frozen_string_literal: true

module Nabu
  module Adapters
    # The orkhon-wikisource parser family: MediaWiki wikitext as Turkish
    # Wikisource (tr.wikisource.org) writes the Orkhon inscriptions —
    # censused 2026-11-27 over the three pages of Kategori:Orhun Abideleri
    # (Kül Tigin, Bilge Kağan, Tonyukuk). This class knows the SHAPES; the
    # adapter decides what they mean. Censused shapes:
    #
    # - the {{eser başlığı}} work header (başlık/önceki/sonraki/bölüm/eser
    #   sahibi/notlar/vikipedi) — captured, never text;
    # - == headings == naming the stone face ("Güney Yüzü"), or, on the
    #   two-stone Tonyukuk page, == the stone == ("Birinci Taş") over
    #   === the face ===;
    # - one {| class="wikitable" |} per face, captioned
    #   "|+ '''Kül Tigin taşı, 1. yüz (güney) 13 dizi'''" (dizi = lines),
    #   headed by six "!" columns (# twice, Göktürk Türkçesi (aslı), Harf
    #   çevirisi, Çeviri yazı, Türkiye Türkçesi çevirisi) and carrying one
    #   ROW PER INSCRIBED LINE: six one-per-line "| " cells — the citation
    #   ("G1", Tonyukuk "1-B1"), upstream's own row id
    #   ("kt-1-g-13-01"), the runiform original (behind a
    #   style="text-align:right;" cell attribute), the letter-by-letter
    #   transliteration, the transcription and the modern Turkish
    #   translation;
    # - "|-" row separators (a doubled one on two Bilge Kağan rows — an
    #   empty row, dropped);
    # - the == Dış bağlantılar == apparatus: {{Kaynak}} citation templates
    #   and bare external links — captured as bibliography, never text.
    #
    # Every censused row has exactly six cells and no inline markup; a row
    # of any other width raises (a reshaped page must be re-censused, never
    # half-read). Text is NOT normalized here — NFC happens at the adapter
    # boundary (house rule).
    class OrkhonWikisourceParser
      Row = Data.define(:cite, :row_id, :runiform, :transliteration, :transcription, :translation,
                        :stone, :face)
      Face = Data.define(:stone, :face, :caption, :declared_lines, :lines)
      Result = Data.define(:header, :rows, :faces, :bibliography)

      # const: the six columns every censused row carries (2026-11-27, 214/214 rows) — a
      # row of any other width is a reshaped page, never half-read.
      CELLS = 6
      HEADING = /\A(=+)\s*(.*?)\s*\1\s*\z/
      APPARATUS = /\Adış bağlantılar\z/i
      HEADER_OPEN = /\{\{\s*eser başlığı\s*\n(.*?)\n\s*\}\}/m
      KAYNAK = /\{\{\s*Kaynak\s*\n(.*?)\n\s*\}\}/m
      PARAM = /\A\s*\|?\s*([^=|]+?)\s*=\s*(.*?)\s*\z/
      CAPTION = /\A\|\+\s*(?:'''(.*?)'''|(.*?))\s*\z/
      DIZI = /(\d+)\s+dizi\b/
      # A cell line "| content", or "| attr="…" | content" (the runiform
      # column's alignment attribute).
      ATTRIBUTED_CELL = /\A\|\s*(?:[a-z-]+="[^"]*"\s*)+\|(?!\|)\s?(.*)\z/
      CELL = /\A\|\s?(.*)\z/

      def parse(wikitext)
        text = wikitext.to_s
        state = { stone: nil, face: nil, path: [], apparatus: false, table: nil, row: nil }
        rows = []
        faces = []
        text.each_line(chomp: true) { |line| step(line, state, rows, faces) }
        raise ParseError, "unterminated wikitable" if state[:table]

        Result.new(header: header(text), rows: rows, faces: faces, bibliography: bibliography(text))
      end

      private

      def step(line, state, rows, faces)
        if (heading = line.match(HEADING))
          heading!(state, heading[1].size, heading[2])
        elsif state[:apparatus]
          nil
        elsif line.start_with?("{|")
          state[:table] = { caption: nil, rows: [] }
        elsif state[:table]
          table_line(line, state, rows, faces)
        end
      end

      # The heading path: the deepest heading names the face, its parent
      # (Tonyukuk's stone) the stone.
      def heading!(state, level, title)
        path = state[:path]
        path.pop while path.any? && path.last.first >= level
        path << [level, title]
        state[:apparatus] = path.any? { |_, name| name.match?(APPARATUS) }
        state[:face] = title
        state[:stone] = path.size > 1 ? path[-2].last : nil
      end

      def table_line(line, state, rows, faces)
        table = state[:table]
        if line.start_with?("|}")
          close_row!(state, table)
          faces << Face.new(stone: state[:stone], face: state[:face], caption: table[:caption],
                            declared_lines: table[:caption].to_s[DIZI, 1]&.to_i, lines: table[:rows].size)
          rows.concat(table[:rows])
          state[:table] = nil
        elsif line.start_with?("|+")
          table[:caption] = line.match(CAPTION).captures.compact.first
        elsif line.start_with?("|-")
          close_row!(state, table)
          state[:row] = []
        elsif line.start_with?("|")
          (state[:row] ||= []) << cell(line)
        end
      end

      def cell(line)
        (line.match(ATTRIBUTED_CELL) || line.match(CELL))[1].strip
      end

      def close_row!(state, table)
        cells = state[:row]
        state[:row] = nil
        return if cells.nil? || cells.empty?
        unless cells.size == CELLS
          raise ParseError,
                "row #{cells.first.inspect}: #{cells.size} cells, expected #{CELLS}"
        end

        cite, row_id, runiform, transliteration, transcription, translation = cells
        table[:rows] << Row.new(cite: cite, row_id: row_id, runiform: runiform, transliteration: transliteration,
                                transcription: transcription, translation: translation,
                                stone: state[:stone], face: state[:face])
      end

      def header(text)
        body = text[HEADER_OPEN, 1] or return {}
        params(body).reject { |_, value| value.empty? }
      end

      # One line per {{Kaynak}} citation: "Surname, Name (year). Title. Publisher. ISBN/url" —
      # the template's own fields, in the order a reader cites them.
      def bibliography(text)
        apparatus = text.split(/^==\s*Dış bağlantılar\s*==\s*$/i, 2)[1].to_s
        cited = apparatus.scan(KAYNAK).map do |(body)|
          fields = params(body)
          name = [fields["soyadı"], fields["ad"]].compact.reject(&:empty?).join(", ")
          year = fields["yıl"] || fields["yayıntarihi"]
          head = [name, year && "(#{year})"].compact.reject(&:empty?).join(" ")
          [head, fields["başlık"], fields["yayıncı"], fields["isbn"] && "ISBN #{fields['isbn']}",
           fields["url"]].compact.reject(&:empty?).join(". ")
        end
        links = apparatus.gsub(KAYNAK, "").scan(/\[(https?:\S+)\s+([^\]]+)\]/).map { |url, label| "#{label}. #{url}" }
        cited + links
      end

      def params(body)
        body.split("\n").filter_map do |line|
          match = line.match(PARAM) or next
          [match[1].strip, match[2].strip]
        end.to_h
      end
    end
  end
end
