# frozen_string_literal: true

require_relative "itkc_catalog_records"

module Nabu
  module Store
    module TimelineBuilder
      # The ITKC author-era lane: a JOIN between held documents and the
      # itkc-catalog module's 서지 records (ItkcCatalogRecords), keyed by
      # the ITKC work id both sides carry.
      #
      # - okhc: the klc slice — the 한국문집총간 munjip mass, 652,405
      #   records with no year field (census 2026-10-19) — carries the
      #   work id in every urn ("urn:nabu:okhc:klc:ITKC_MO_0001A_0010_
      #   010_0010"; the record's permanent_url names the same dataId);
      # - itkc: the held fascicles' urns ("urn:nabu:itkc:mo-1247a-0010",
      #   "go-1432a-0140") decode to ITKC_MO_1247A / ITKC_GO_1432A.
      #
      # Each joined document gains the work's author-era band (the
      # ItkcCatalog band rules: birth..death, the original print year as
      # the terminus when the death is unknown) as a derived, labeled row
      # — the kanripo :DATES: precedent: precision "era", date_class
      # "composition" (the attributed-era grade — it dates the munjip's
      # making by its author's life, never a text's own claim), axis_source
      # "<slug>-authors", date_raw naming the author, the years and the 서지
      # record. A document some other upstream lane already dates keeps
      # that claim ALONE (the fill never overrides an explicit date — the
      # itkc fascicles' 원문간행년 print years stay the only rows on 608
      # fascicles); a silver estimate is no upstream claim and blocks
      # nothing.
      #
      # Counted per target, never guessed: +undated+ (the work is in the
      # catalog but nothing bounds it above), +unmatched+ (no catalog
      # record for the work id), +already_dated+ (left to the other lane).
      #
      # Derived by construction: f(canonical/itkc-catalog + loaded rows) —
      # catalog urns and existing axis rows only, no re-parse. It runs
      # inside the timeline rebuild (rebuild, incremental rebuild,
      # builders:refresh) after every dating lane it defers to, and after
      # a sync of okhc, itkc or the catalog module (refresh_source!). An
      # absent catalog tree is a clean no-op.
      module ItkcAuthorDates
        CATALOG_SLUG = ItkcCatalogRecords::SLUG
        AXIS_SUFFIX = "-authors"
        PRECISION = "era"
        DATE_CLASS = "composition"
        SILVER_CLASS = "silver"
        BATCH = 2_000

        OKHC_WORK = /\Aurn:nabu:okhc:klc:(ITKC_[A-Z]{2}_[0-9A-Z]+)(?:_|\z)/
        ITKC_WORK = /\Aurn:nabu:itkc:([a-z]{2})-([0-9a-z]+)-\d{4}/

        # slug => the urn prefix bounding the scan + the urn → work id read.
        TARGETS = {
          "okhc" => { prefix: "urn:nabu:okhc:klc:ITKC_", work: ->(urn) { urn[OKHC_WORK, 1] } },
          "itkc" => {
            prefix: "urn:nabu:itkc:",
            work: lambda do |urn|
              match = ITKC_WORK.match(urn)
              match && "ITKC_#{match[1].upcase}_#{match[2].upcase}"
            end
          }
        }.freeze

        module_function

        # {slug => {documents:, undated:, unmatched:, already_dated:}}.
        def build(catalog:, canonical_dir:)
          bands = catalog_bands(canonical_dir)
          TARGETS.to_h { |slug, _| [slug, build_target(catalog, slug, bands)] }
        end

        # The per-source seam: a sync of a target re-derives its slice; a
        # sync of the catalog module re-derives both; any other slug is a
        # no-op. Returns the rows minted.
        def refresh_source!(catalog:, canonical_dir:, slug:)
          slugs = slug == CATALOG_SLUG ? TARGETS.keys : [slug] & TARGETS.keys
          return 0 if slugs.empty?

          bands = catalog_bands(canonical_dir)
          slugs.sum do |target|
            catalog[:document_axes].where(axis_source: target + AXIS_SUFFIX).delete
            build_target(catalog, target, bands)[:documents]
          end
        end

        # {work id => Band or nil} for every held record ({} when the
        # module tree is absent).
        def catalog_bands(canonical_dir)
          ItkcCatalogRecords.records(File.join(canonical_dir, CATALOG_SLUG))
                            .transform_values { |record| ItkcCatalogRecords.band(record) }
        end

        def build_target(catalog, slug, bands)
          counts = { documents: 0, undated: 0, unmatched: 0, already_dated: 0 }
          return counts if bands.empty?

          target = TARGETS.fetch(slug)
          each_batch(catalog, target[:prefix]) do |batch|
            dated = dated_ids(catalog, batch.map(&:first), slug)
            rows = batch.filter_map do |id, urn|
              row_for(id, target[:work].call(urn), bands, dated, counts, slug)
            end
            catalog[:document_axes].multi_insert(rows) unless rows.empty?
          end
          counts
        end

        def row_for(id, work, bands, dated, counts, slug)
          return nil if work.nil? # not a work-keyed urn (outside the joinable slice)

          unless bands.key?(work)
            counts[:unmatched] += 1
            return nil
          end
          if dated.include?(id)
            counts[:already_dated] += 1
            return nil
          end
          band = bands[work]
          if band.nil?
            counts[:undated] += 1
            return nil
          end
          counts[:documents] += 1
          { document_id: id, not_before: band.not_before, not_after: band.not_after,
            precision: PRECISION, date_class: DATE_CLASS, date_raw: band.raw,
            axis_source: slug + AXIS_SUFFIX }
        end

        # Live documents under +prefix+, BATCH at a time in urn order
        # (keyset on the unique urn index): yields [[id, urn], …].
        def each_batch(catalog, prefix)
          upper = prefix[0..-2] + (prefix[-1].ord + 1).chr
          scope = catalog[:documents].where(withdrawn: false)
                                     .where(Sequel[:urn] >= prefix).where(Sequel[:urn] < upper)
          last = nil
          loop do
            page = scope.order(:urn).limit(BATCH)
            page = page.where(Sequel[:urn] > last) if last
            batch = page.select_map(%i[id urn])
            break if batch.empty?

            yield batch
            last = batch.last[1]
          end
        end

        # The ids among +ids+ another upstream lane already dates (a row
        # with a bound, not this lane's, not a silver estimate).
        def dated_ids(catalog, ids, slug)
          catalog[:document_axes]
            .where(document_id: ids)
            .exclude(axis_source: slug + AXIS_SUFFIX)
            .exclude(Sequel.function(:coalesce, :date_class, "") => SILVER_CLASS)
            .where(Sequel.|(Sequel.~(not_before: nil), Sequel.~(not_after: nil)))
            .distinct.select_map(:document_id).to_set
        end
      end
    end
  end
end
