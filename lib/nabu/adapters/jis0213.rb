# frozen_string_literal: true

module Nabu
  module Adapters
    # JIS X 0213:2004 men-ku-ten → Unicode resolution (P38-3), backing the
    # Aozora gaiji class-(a) notation `第N水準X-Y-Z` (plane-row-cell). The
    # table is Project X0213's reference mapping, shipped verbatim at
    # config/jis0213/jisx0213-2004-std.txt (see that directory's README for
    # retrieval + license: "You can use, modify, distribute this table
    # freely.").
    #
    # Table key format: plane 1 rows are `3-XXXX`, plane 2 rows `4-XXXX`,
    # XXXX being the GL encoding of row/cell — byte1 = 0x20 + row, byte2 =
    # 0x20 + cell (第3水準1-93-12 → `3-7D2C`). Values are `U+xxxx`, or the
    # two-codepoint `U+xxxx+xxxx` sequences (base + combining, e.g. the
    # kana-with-semivoicing rows) — both shapes resolve, per the table's own
    # header note. Rows without a Unicode column (a handful of reserved
    # cells) simply do not enter the map, so lookups on them return nil and
    # the caller stays on its loud unresolved path — never a guess.
    module Jis0213
      # Anchored on __dir__ (not Nabu::Config, which loads later in
      # lib/nabu.rb's require order): lib/nabu/adapters → the repo root.
      TABLE_PATH = File.expand_path("../../../config/jis0213/jisx0213-2004-std.txt", __dir__)

      # `U+xxxx` or `U+xxxx+xxxx` (the two-codepoint combining shape).
      UNICODE_VALUE = /\AU\+(\h{4,6})(?:\+(\h{4,6}))?\z/

      module_function

      # The character (1- or 2-codepoint String) for +plane+ (men, 1 or 2),
      # +row+ (ku, 1–94) and +cell+ (ten, 1–94) — or nil when the table has
      # no mapping (out-of-range coordinates included).
      def resolve(plane:, row:, cell:)
        return nil unless [1, 2].include?(plane) && (1..94).cover?(row) && (1..94).cover?(cell)

        table[format("%<plane>d-%<byte1>02X%<byte2>02X",
                     plane: plane == 1 ? 3 : 4, byte1: 0x20 + row, byte2: 0x20 + cell)]
      end

      def table
        @table ||= load_table
      end

      def load_table
        map = {}
        File.foreach(TABLE_PATH, encoding: Encoding::UTF_8) do |line|
          next if line.start_with?("#")

          key, value = line.chomp.split("\t", 3)
          next unless key && (match = UNICODE_VALUE.match(value.to_s))

          map[key] = [match[1], match[2]].compact.map { |hex| hex.to_i(16) }.pack("U*").freeze
        end
        map.freeze
      end
    end
  end
end
