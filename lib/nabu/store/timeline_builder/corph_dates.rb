# frozen_string_literal: true

require_relative "../../adapters/corph_sql_parser"
require_relative "../../adapters/corph"

module Nabu
  module Store
    module TimelineBuilder
      # CorPH text dates (P25-0): TEXT.Date — dating prose curated by the
      # ChronHib project — into document-grain timeline rows. Censused on
      # the full dump (2026-07-17): 73/78 texts parse honestly, 5 are honest
      # residues (the Annals of Ulster's 431–1131 annalistic spread, and
      # MS-only prose like "MS: 826-848, also the date range used") — counted
      # undated, never guessed. These are TEXT dates (the language dating —
      # what a chronologicon is for); the MS dates riding in the same prose
      # stay in document metadata verbatim.
      #
      # The parse ladder (see extract_range):
      #   1. the ChronHib phrase — "Date range 690-720 is used in ChronHib",
      #      "Date ranges 785-825 (for text), 800-825 (for MS) are used …":
      #      prefer the "(for text)"-tagged range, else the ENVELOPE of every
      #      range inside the phrase (the fable-reviewed multi-date policy);
      #      the capture starts AFTER "date range(s)", so MS ranges named
      #      earlier in the prose never leak in;
      #   2. the text-date fallback — "Text: 688 X 692", "Text 689-719"
      #      (8 texts whose ChronHib phrase is absent).
      #
      # All years are CE (7th–10th-c. corpus; no BCE arithmetic to trip).
      # date_raw keeps the whole upstream Date prose verbatim.
      module CorphDates
        SLUG = "corph"
        URN_PREFIX = "urn:nabu:corph:"

        # "690-720" / "690 – 720" / "688 X 692" (the Vita Columbae style).
        RANGE = /(\d{3,4})\s*(?:[-–]|X)\s*(\d{3,4})/

        # The ChronHib phrase: everything between "date range(s)" and its
        # "is/are used" verb.
        PHRASE = /[Dd]ate ranges?\s+(.*?)\s+(?:is|are)\s+used/m

        FOR_TEXT = /(\d{3,4})\s*[-–]\s*(\d{3,4})\s*\(for text\)/

        module_function

        # Walk the canonical dump's TEXT rows and insert one timeline row per
        # dated document we hold. Returns { documents:, undated: } — undated
        # counts HELD documents whose Date resisted the ladder (the honest
        # residue), never unheld ones.
        def build(catalog:, canonical_dir:)
          dump = File.join(canonical_dir, SLUG, Adapters::Corph::DUMP_FILENAME)
          return { documents: 0, undated: 0 } unless File.file?(dump)

          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          rows = 0
          undated = 0
          Adapters::CorphSqlParser.new(dump).each_row("TEXT") do |row|
            document_id = ids[document_urn(row)] or next
            range = extract_range(row["Date"].to_s)
            next undated += 1 if range.nil?

            insert(catalog, document_id, range, row["Date"].to_s)
            rows += 1
          end
          { documents: rows, undated: undated }
        end

        # FROZEN alongside Adapters::Corph#discover (the drift-pin test holds
        # the two together).
        def document_urn(row)
          "#{URN_PREFIX}#{row.fetch('Text_ID')}"
        end

        # [not_before, not_after] CE, or nil when the prose resists the
        # ladder (class note).
        def extract_range(date)
          if (capture = date[PHRASE, 1])
            if (tagged = capture.match(FOR_TEXT))
              return [tagged[1].to_i, tagged[2].to_i]
            end

            ranges = capture.scan(RANGE).map { |lo, hi| [lo.to_i, hi.to_i] }
            return [ranges.map(&:first).min, ranges.map(&:last).max] unless ranges.empty?
          end
          text_date(date)
        end

        def text_date(date)
          m = date.match(/Text\b:?\s*(?:c\.\s*)?#{RANGE}/)
          m && [m[1].to_i, m[2].to_i]
        end

        def insert(catalog, document_id, range, raw)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: range[0], not_after: range[1],
            precision: range[0] == range[1] ? "year" : "range",
            date_raw: Nabu::Normalize.nfc(raw.strip.gsub(/\s+/, " ")),
            axis_source: SLUG
          )
        end
      end
    end
  end
end
