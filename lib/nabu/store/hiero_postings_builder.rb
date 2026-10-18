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
    # walking 14k files (the desk-commands law). Signs written only as a
    # Gardiner-coded "Keine Entsprechung in Unicode" note post as
    # code-keyed rows beside the glyph rows (migration 043); the
    # untalliable remainder rides the Summary.
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
      # The finer grain (migration 042): word tokens and damaged runs.
      WORD = %r{<w\b[^>]*>(.*?)</w>}m
      UNCLEAR = %r{<unclear>(.*?)</unclear>}m
      # Signs without a codepoint (migration 043): a <note> inside the
      # <w>, optionally wrapped in <unclear> (damaged). The payload is a
      # hyphen-joined Gardiner spelling ("D31A-A1", "[[-I9-]]" damage
      # brackets) or the untalliable "diese Graphien".
      NO_UNICODE = %r{(<unclear>\s*)?<note>Keine Entsprechung in Unicode für ([^<]*)</note>}
      UNTALLIABLE = /\Adiese Graphien/
      DAMAGE_BRACKETS = /\[\[|\]\]/
      # Mirrors Query::HieroCard::CODE, the Gardiner grammar authority
      # (the store loads before the query layer; a test pins equality).
      CODE = /\A[A-Z][A-Za-z]?\d{1,3}[A-Za-z]{0,2}\z/

      # +glyphs+/+rows+ = the codepoint-keyed rows and their occurrences;
      # +codes+/+code_signs+ = the code-keyed rows and theirs; +remainder+
      # censuses what the notes carry but no row can hold.
      Summary = Data.define(:texts, :glyphs, :rows, :codes, :code_signs, :remainder)
      # +notes+: every Keine-Entsprechung note inside a <w>; +graphien+:
      # the "diese Graphien" ones; +screened+: token => count of spelling
      # members failing the Gardiner grammar (bare numerals like "2").
      Remainder = Data.define(:notes, :graphien, :screened)

      module_function

      def rebuild!(catalog:, canonical_dir:, progress: nil)
        catalog[TABLE].delete if catalog.table_exists?(TABLE)
        files = hiero_files(canonical_dir)
        remainder = { notes: 0, graphien: 0, screened: Hash.new(0) }
        return summary(0, [], [], remainder) if files.empty?

        tallies = new_tallies
        code_tallies = new_tallies
        scanned = 0
        files.each do |path|
          body = File.read(path, encoding: Encoding::UTF_8)[BODY, 1].to_s
          scanned += 1
          progress&.load_tick(scanned, 0) if (scanned % 1000).zero?
          tally_text(body, tallies)
          tally_codes(body, code_tallies, remainder)
        end
        rows = tallies.keys.sort.map { |glyph| { glyph: glyph, code: nil, **tallies[glyph] } }
        code_rows = code_tallies.keys.sort.map { |code| { glyph: nil, code: code, **code_tallies[code] } }
        (rows + code_rows).each_slice(2_000) { |slice| catalog[TABLE].multi_insert(slice) }
        summary(scanned, rows, code_rows, remainder)
      end

      def new_tallies
        Hash.new { |hash, key| hash[key] = { texts: 0, signs: 0, words: 0, unclear: 0 } }
      end

      def summary(scanned, rows, code_rows, remainder)
        Summary.new(texts: scanned, glyphs: rows.size, rows: rows.sum { |row| row[:signs] },
                    codes: code_rows.size, code_signs: code_rows.sum { |row| row[:signs] },
                    remainder: Remainder.new(notes: remainder[:notes], graphien: remainder[:graphien],
                                             screened: remainder[:screened].sort.to_h))
      end

      # One text's contribution: per glyph, the text itself (+texts+),
      # every occurrence (+signs+), each word token carrying it at least
      # once (+words+ — the census found every glyph inside a <w>), and
      # the occurrences read inside <unclear> (+unclear+, damaged).
      def tally_text(body, tallies)
        runs = body.scan(GLYPH)
        return if runs.empty?

        runs.tally.each do |glyph, count|
          tallies[glyph][:texts] += 1
          tallies[glyph][:signs] += count
        end
        body.scan(WORD) { |(word)| word.scan(GLYPH).uniq.each { |glyph| tallies[glyph][:words] += 1 } }
        body.scan(UNCLEAR) { |(run)| run.scan(GLYPH).each { |glyph| tallies[glyph][:unclear] += 1 } }
      end

      # One text's Gardiner-coded contribution, at the glyph grain: each
      # grammar-conforming spelling member is one sign occurrence, each
      # note-bearing <w> one word, members of an <unclear>-wrapped note
      # damaged occurrences.
      def tally_codes(body, tallies, remainder)
        in_text = Set.new
        body.scan(WORD) do |(word)|
          in_word = Set.new
          word.scan(NO_UNICODE) do |damaged, payload|
            remainder[:notes] += 1
            payload = payload.strip
            if payload.match?(UNTALLIABLE)
              remainder[:graphien] += 1
              next
            end

            spelling_codes(payload, remainder[:screened]).each do |code|
              tallies[code][:signs] += 1
              tallies[code][:unclear] += 1 if damaged
              in_word << code
            end
          end
          in_word.each { |code| tallies[code][:words] += 1 }
          in_text.merge(in_word)
        end
        in_text.each { |code| tallies[code][:texts] += 1 }
      end

      # Split the spelling on "-", strip damage brackets and trailing
      # periods; non-conforming members land in +screened+, never a row.
      def spelling_codes(payload, screened)
        tokens = payload.gsub(DAMAGE_BRACKETS, "").split("-")
                        .map { |token| token.strip.delete_suffix(".") }.reject(&:empty?)
        codes, rejects = tokens.partition { |token| token.match?(CODE) }
        rejects.each { |token| screened[token] += 1 }
        codes
      end

      def hiero_files(canonical_dir)
        return [] if canonical_dir.nil?

        Dir.glob(File.join(canonical_dir, SOURCE_SLUG, GLOB))
      end
    end
  end
end
