# frozen_string_literal: true

module Nabu
  module Store
    # The AED hieroglyph postings walk (P103-2): canonical/aed carries
    # 13,949 per-text stand-off files (`files/<TLA-text-id>_hiero.xml`)
    # whose bodies encode each token's hieroglyph run as plain
    # U+13000-block codepoints (`<w corresp="src:tla…">𓂋𓊪𓂝</w>`;
    # damaged readings ride inside `<unclear>` and still COUNT — an
    # attested-but-damaged sign is an attestation). This builder tallies
    # them into the precompiled hiero_postings table (migration 033):
    # one row per glyph with its distinct-text and total-occurrence
    # counts, so the HieroCard corpus panel reads ONE row instead of
    # walking 14k files (the desk-commands law).
    #
    # Derivable by construction: f(canonical/aed) — drop-and-reproject;
    # wired into both rebuild flavors and the aed post-sync refresh. A
    # tree without the hiero cone (the pre-P103 sparse clone, a public
    # checkout) yields the honest empty table, never an error.
    module HieroPostingsBuilder
      TABLE = :hiero_postings
      SOURCE_SLUG = "aed"
      GLOB = File.join("files", "*_hiero.xml").freeze
      # The Unicode Egyptian Hieroglyphs block + the Format-Controls
      # extension (U+13000–1345F, the Unikemet space the sign cards key).
      GLYPH = /[\u{13000}-\u{1345F}]/
      BODY = %r{<body>(.*)</body>}m

      Summary = Data.define(:texts, :glyphs, :rows)

      module_function

      def rebuild!(catalog:, canonical_dir:, progress: nil)
        catalog[TABLE].delete if catalog.table_exists?(TABLE)
        files = hiero_files(canonical_dir)
        return Summary.new(texts: 0, glyphs: 0, rows: 0) if files.empty?

        texts_by_glyph = Hash.new(0)
        signs_by_glyph = Hash.new(0)
        scanned = 0
        files.each do |path|
          runs = File.read(path, encoding: Encoding::UTF_8)[BODY, 1].to_s.scan(GLYPH)
          scanned += 1
          progress&.load_tick(scanned, 0) if (scanned % 1000).zero?
          next if runs.empty?

          runs.tally.each do |glyph, count|
            texts_by_glyph[glyph] += 1
            signs_by_glyph[glyph] += count
          end
        end
        rows = texts_by_glyph.keys.sort.map do |glyph|
          { glyph: glyph, texts: texts_by_glyph[glyph], signs: signs_by_glyph[glyph] }
        end
        rows.each_slice(2_000) { |slice| catalog[TABLE].multi_insert(slice) }
        Summary.new(texts: scanned, glyphs: rows.size,
                    rows: rows.sum { |row| row[:signs] })
      end

      def hiero_files(canonical_dir)
        return [] if canonical_dir.nil?

        Dir.glob(File.join(canonical_dir, SOURCE_SLUG, GLOB))
      end
    end
  end
end
