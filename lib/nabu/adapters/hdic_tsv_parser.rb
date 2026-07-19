# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "hdic-tsv" (P32-4): the HDIC project's per-database TSV
    # shape — `#` comment header (provenance, credits, the per-file CC BY-SA
    # grant), then one column-name row, then one tab-separated row per
    # dictionary entry. Column NAMES differ per database (YYID/SYID/TBID/
    # TSJ2ID/KRID_n…), so the adapter passes the id/headword/definition
    # column names and the parser stays one generic reader.
    #
    # The body carries EVERY populated column as "name: value" lines
    # (definition first) — the TBID/SYID/YYID columns are the project's own
    # cross-dictionary links and ride verbatim, so the crosswalk is never
    # lost to a narrower projection. A row with an EMPTY headword cell is
    # skipped by rule (censused upstream 2026-07-19: exactly one such row,
    # TSJ2ID s0811a303a in TSJ_definitions.tsv — an entry-less definition
    # fragment); an empty id cell is damage and raises.
    class HdicTsvParser
      # The wakun-database columns that ride into an entry's rider lines.
      WAKUN_COLUMNS = %w[reading_kana_kanji def_manyogana reading_historical_kana pos].freeze

      # +wakun+: optional path to TSJ_wakun.tsv — the Shinsen Jikyō Japanese
      # readings database (3,828 rows, v1.1.8 2026-07-15), joined onto the
      # definitions rows by its `tsj_id` column and appended as body lines.
      def entries(path, id_column:, entry_column:, def_column:, language:, wakun: nil)
        wakun_lines = wakun && File.file?(wakun) ? wakun_by_id(wakun) : {}
        rows(path).filter_map do |row|
          entry(row, path: path, id_column: id_column, entry_column: entry_column,
                     def_column: def_column, language: language, wakun_lines: wakun_lines)
        end
      end

      private

      # Header-keyed rows; the first non-comment line names the columns.
      def rows(path)
        header = nil
        collected = []
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          next if line.start_with?("#")

          cells = line.chomp.chomp("\r").split("\t", -1)
          if header.nil?
            header = cells
          else
            collected << header.zip(cells).to_h
          end
        end
        raise Nabu::ParseError, "hdic-tsv: #{path} has no column-header row" if header.nil?

        collected
      end

      def entry(row, path:, id_column:, entry_column:, def_column:, language:, wakun_lines:)
        id = row[id_column].to_s.strip
        raise Nabu::ParseError, "hdic-tsv: row without #{id_column} in #{path}" if id.empty?

        headword = Normalize.nfc(row[entry_column].to_s.strip)
        return nil if headword.empty? # skip-by-rule: entry-less row (class note)

        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: id, language: language,
          headword: headword,
          headword_folded: Normalize.search_form(headword, language: language),
          gloss: gloss(row[def_column]),
          body: Normalize.nfc(body_lines(row, id_column, entry_column, def_column, wakun_lines[id]).join("\n"))
        )
      end

      # Definition first, then every other populated column in file order,
      # then the wakun rider lines.
      def body_lines(row, id_column, entry_column, def_column, wakun)
        definition = row[def_column].to_s.strip
        lines = definition.empty? ? [] : ["#{def_column}: #{definition}"]
        row.each do |column, value|
          next if [entry_column, def_column].include?(column)

          text = value.to_s.strip
          lines << "#{column}: #{text}" unless text.empty?
        end
        lines.concat(wakun) if wakun
        lines << "#{id_column}: #{row[id_column]}" if lines.empty?
        lines
      end

      # Short first gloss, best-effort: the definition's first 。-sentence.
      def gloss(definition)
        first = definition.to_s.strip.split("。").first.to_s.strip
        first.empty? ? nil : Normalize.nfc(first)
      end

      def wakun_by_id(path)
        rows(path).each_with_object({}) do |row, index|
          id = row["tsj_id"].to_s.strip
          next if id.empty?

          facts = WAKUN_COLUMNS.filter_map { |column| row[column].to_s.strip }.reject(&:empty?)
          next if facts.empty?

          (index[id] ||= []) << "wakun: #{facts.join(' · ')} [#{row['sj_w_id']}]"
        end
      end
    end
  end
end
