# frozen_string_literal: true

require "json"

require_relative "../../timeline"

module Nabu
  module Store
    module TimelineBuilder
      # The Ipatiev chronicle's annal years (litopys) → passage-grain
      # timeline rows, the ChronicleAnnals mold read FROM THE CATALOG (the
      # NikhEntryDates stance — the adapter carries the site's annal-year
      # keys "[6360 (852)]" per column as the annal_years annotation, a
      # load-verified f(canonical); no re-parse, no revision bump).
      #
      # == Census (2026-10-20, live catalog)
      #
      # 41 chronicle pages, 964 columns; 226 columns carry 437 keys (AM +
      # the site's AD). Every page holds at least one key; ipat01's
      # opening 11 columns (the Повѣсть's undated introduction, before
      # 6360) precede any annal.
      #
      # == Rows (axis_source "litopys-annals", date_class NULL — the annal
      # dates its entry, as the torot annals do)
      #
      # One row per key: AM → CE through Timeline.am_to_ce (precision
      # "am", the documented September-style envelope), date_raw the
      # site's own key ("AM 6360 (852)"). An annal spans from its key's
      # column to the column holding the NEXT key (inclusive — the annal's
      # text runs into that column up to the key; a key's in-column
      # position is not carried, so the shared column is claimed by both,
      # never dropped); the page's last annal runs to the page's end.
      #
      # A page opening mid-annal (8 pages) CONTINUES its predecessor's
      # last annal: one carried row over the leading columns, but only
      # across CONTIGUOUS pages (ipatNN after ipatNN−1) — the chronicle is
      # one text cut into site pages. Leading columns with no predecessor
      # page held stay undated and are counted (+unkeyed+), never guessed.
      #
      # No document-grain envelope: the document grain is the MetadataDates
      # era band (the svod's attributed composition era), and an annal
      # envelope beside it would claim a second, different document date.
      module LitopysAnnalDates
        SLUG = "litopys"
        AXIS_SOURCE = "litopys-annals"
        PAGE = /:ipat(\d\d)\z/
        KEY = "annal_years"

        # The ChronicleAnnals plausibility gate (AM 5500–7300).
        AM_PLAUSIBLE = ChronicleAnnals::AM_PLAUSIBLE

        module_function

        # Returns { annals:, carried:, unkeyed:, invalid: } — annal rows,
        # carried continuation rows, leading columns left undated, and keys
        # outside the plausibility gate (skipped, counted).
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          counts = { annals: 0, carried: 0, unkeyed: 0, invalid: 0 }
          source_id = catalog[:sources].where(slug: SLUG).get(:id)
          return counts if source_id.nil?

          TimelineBuilder.writing_axes(catalog) do |axes|
            previous = nil # [page number, last annal] of the page before
            chronicle_pages(catalog, source_id).each do |document_id, page|
              carry = previous && previous[0] == page - 1 ? previous[1] : nil
              last = page_rows(catalog, axes, document_id, carry, counts)
              previous = [page, last || carry]
            end
          end
          counts
        end

        # The per-source seam (the MetadataDates contract): drop this
        # lane's rows, re-project. Returns rows inserted; 0 for any other
        # slug.
        def refresh_source!(catalog:, slug:)
          return 0 unless slug == SLUG

          catalog[:document_axes].where(axis_source: AXIS_SOURCE).delete
          outcome = build(catalog: catalog)
          outcome[:annals] + outcome[:carried]
        end

        # [[document_id, page number]] in page order (the glossaries and
        # any non-chronicle document fall out on the urn shape).
        def chronicle_pages(catalog, source_id)
          catalog[:documents].where(source_id: source_id, withdrawn: false).select_map(%i[id urn])
                             .filter_map { |id, urn| (m = PAGE.match(urn)) && [id, Integer(m[1], 10)] }
                             .sort_by(&:last)
        end

        # One page's rows. Returns the page's last annal (nil when it has
        # no key).
        def page_rows(catalog, axes, document_id, carry, counts)
          sequences, keys = scan(catalog, document_id, counts)
          return nil if sequences.empty?

          # The leading columns before the first key (the whole page when
          # it holds none); the carried annal reaches into the first key's
          # column, like any annal reaches its successor's.
          lead_end = keys.empty? ? sequences.last : keys.first[:seq]
          lead = keys.empty? ? sequences.size : sequences.count { |seq| seq < lead_end }
          if carry && lead.positive?
            axes.insert(row(document_id, carry, sequences.first, lead_end))
            counts[:carried] += 1
          else
            counts[:unkeyed] += lead
          end
          keys.each_with_index do |key, index|
            to = keys[index + 1] ? keys[index + 1][:seq] : sequences.last
            axes.insert(row(document_id, key, key[:seq], to))
            counts[:annals] += 1
          end
          keys.last
        end

        # The page's live passage sequences and its keys in reading order.
        def scan(catalog, document_id, counts)
          sequences = []
          keys = []
          catalog[:passages].where(document_id: document_id, withdrawn: false)
                            .order(:sequence).select_map(%i[sequence annotations_json])
                            .each do |sequence, json|
                              sequences << sequence
                              annal_years(json).each do |year|
                                am = year["am"]
                                unless am.is_a?(Integer) && AM_PLAUSIBLE.cover?(am)
                                  counts[:invalid] += 1
                                  next
                                end
                                keys << { seq: sequence, am: am, ad: year["ad"] }
                              end
                            end
          [sequences, keys]
        end

        def annal_years(json)
          years = JSON.parse(json.to_s)[KEY]
          years.is_a?(Array) ? years.grep(Hash) : []
        rescue JSON::ParserError
          []
        end

        # NB: every row carries the SAME column set (multi_insert).
        def row(document_id, key, from, to)
          not_before, not_after = Timeline.am_to_ce(key[:am])
          raw = key[:ad] ? "AM #{key[:am]} (#{key[:ad]})" : "AM #{key[:am]}"
          { document_id: document_id, not_before: not_before, not_after: not_after,
            precision: "am", date_raw: raw, passage_seq_from: from, passage_seq_to: to,
            axis_source: AXIS_SOURCE }
        end
      end
    end
  end
end
