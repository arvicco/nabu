# frozen_string_literal: true

require_relative "../../date_axis"
require_relative "../../adapters/coptic_tt_parser"

module Nabu
  module Store
    module AxisBuilder
      # Coptic Scriptorium manuscript dates and places (P17-1, survey §5):
      # 234 documents carry `origDate` + `origDate_notBefore`/`notAfter`
      # (4-digit CE strings, "between 500 and 799 C.E.") with an upstream
      # `origDate_precision` vocabulary (high/medium/low — "high" IS
      # colophon dating, e.g. theodosius 983/987); many more carry an
      # `origPlace`/`placeName` (White Monastery 227, Hagr Edfu, Hamuli…).
      # These are MANUSCRIPT (copying) dates — the right axis for a corpus
      # of codex fragments. The HGV shape: a straight field read from each
      # TT header's one meta line, joined to the catalog by urn.
      #
      # Honest absences: the bible corpora are undated digital editions
      # (no origDate anywhere in their headers — verified on the fixture
      # zip members), so their in-repo zips are never opened here; a
      # document with neither date nor place gets no row; "unknown"-class
      # place values are skipped (never stored as a place). A year-0 header
      # (DateAxis rejects year 0) is skipped and counted invalid, never
      # stored — the robust-bulk-build-over-strict-model stance.
      #
      # The urn mint mirrors Adapters::CopticScriptorium#document_urn
      # (FROZEN): cts tail minus the chapter suffix for chapter files; the
      # adapter test pins the two against each other via the shared fixture
      # set, so they cannot drift silently.
      module CopticScriptoriumDates
        SLUG = "coptic-scriptorium"
        URN_PREFIX = "urn:nabu:coptic-scriptorium:"
        CTS_NAMESPACE = /\Aurn:cts:coptic(?:Lit|Doc):/
        CHAPTER_SUFFIX = /:\d+\z/
        EXCLUDED_DIRS = %w[coptic-treebank bohairic-treebank].freeze
        NO_PLACE = %w[unknown unclear uncertain none].freeze

        module_function

        # Walk canonical/coptic-scriptorium's loose TT headers and insert one
        # row per dated-or-placed document we hold. Returns
        # { documents:, invalid: } — +invalid+ counts year-0/unparseable
        # headers, skipped and never guessed.
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, SLUG)
          return { documents: 0, invalid: 0 } unless Dir.exist?(dir)

          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          rows = 0
          invalid = 0
          seen = Set.new
          tt_headers(dir) do |meta|
            urn = document_urn(meta)
            next unless seen.add?(urn)

            begin
              axis = extract(meta)
            rescue DateAxis::InvalidYear
              invalid += 1
              next
            end
            next if axis.nil?

            document_id = ids[urn] or next
            insert(catalog, document_id, axis)
            rows += 1
          end
          { documents: rows, invalid: invalid }
        end

        def tt_headers(dir)
          Dir.glob(File.join(dir, "**", "*_TT", "*.tt")).each do |path|
            next if path.split(File::SEPARATOR).any? { |segment| EXCLUDED_DIRS.include?(segment) }

            meta = Adapters::CopticTtParser.header(path)
            next if meta.nil? || meta["document_cts_urn"].nil?

            yield meta
          end
        end

        def document_urn(meta)
          tail = meta["document_cts_urn"].sub(CTS_NAMESPACE, "")
          tail = tail.sub(CHAPTER_SUFFIX, "") if meta["chapter"]
          "#{URN_PREFIX}#{tail}"
        end

        # The axis fields, or nil when the header carries neither a date nor
        # a usable place. Precision is upstream's own vocabulary when given,
        # else "range" (the bounds are honest envelopes, never midpoints).
        def extract(meta)
          not_before = DateAxis.parse_year(meta["origDate_notBefore"])
          not_after = DateAxis.parse_year(meta["origDate_notAfter"])
          place = place_of(meta)
          return nil if not_before.nil? && not_after.nil? && place.nil?

          {
            not_before: not_before, not_after: not_after,
            precision: meta["origDate_precision"] || (not_before || not_after ? "range" : nil),
            date_raw: meta["origDate"], place_name: place
          }
        end

        def place_of(meta)
          [meta["origPlace"], meta["placeName"]].each do |value|
            value = value.to_s.strip
            next if value.empty? || NO_PLACE.include?(value.downcase)

            return value
          end
          nil
        end

        def insert(catalog, document_id, axis)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: axis[:not_before], not_after: axis[:not_after],
            precision: axis[:precision], date_raw: axis[:date_raw],
            place_name: axis[:place_name], axis_source: SLUG
          )
        end
      end
    end
  end
end
