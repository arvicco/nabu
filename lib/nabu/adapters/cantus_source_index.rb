# frozen_string_literal: true

require "nokogiri"
require_relative "source_read"

module Nabu
  module Adapters
    # The Cantus Database's "Browse Sources" listing read as per-source
    # metadata — the half of the cantus-csv family that knows the
    # MANUSCRIPT (the per-source CSV export carries only the chant rows).
    #
    #   GET /sources/?segment=4063&page=<n>   (segment 4063 = "Cantus DB:
    #   Sources with Inventories", the exact set /json-sources/ lists)
    #
    # One table row per source: Country | City + Holding Institution |
    # Cantus Siglum (link /source/<id>/, a "Fragment" badge beside it) |
    # Summary (the full text in the cell's title attribute) | Date/Origin
    # (curated /century/<id> links + /provenance/<id> links) | Image Link |
    # Chants / Melodies ("4305 / 6" — upstream's own advertised count,
    # which equals the CSV export's row count on every source probed,
    # 15/15 at the 2026-11-04 census).
    #
    # The century labels are upstream's controlled vocabulary ("10th
    # century", "10th century (975-1000)", "13th century (2nd half)",
    # "09th century" — 40 distinct labels across the 305 sources, census
    # 2026-11-04): a century N bands to (N-1)×100+1 … N×100 (the scat
    # century envelope), a stated year span wins, halves split at 50. The
    # provenance vocabulary (214 values, the page's own filter list) is
    # places save three non-place values — DECLARED in NON_PLACES.
    class CantusSourceIndex
      # One listed source. +centuries+/+provenance+ are arrays (a source
      # may carry two of each — 23 sources name two centuries).
      Source = Data.define(:id, :siglum, :country, :institution, :summary, :centuries,
                           :provenance, :chants, :melodies)

      PAGE_GLOB = "sources-page-*.html"

      # The column headers the reading depends on (a renamed column must
      # fail loudly, never yield blank metadata).
      REQUIRED_COLUMNS = ["Country", "City + Holding Institution", "Cantus Siglum", "Summary",
                          "Date/Origin", "Chants / Melodies"].freeze

      # Provenance values that name no place: two religious orders and a
      # nationality adjective (the full 214-value vocabulary read
      # 2026-11-04). They ride metadata "provenance"; they never mint a
      # place claim. Everything else in the vocabulary names a place
      # (town, abbey, region or country — coarse values ride as named).
      NON_PLACES = %w[Dominican Franciscan English].freeze

      CENTURY = /\A0?(\d{1,2})(?:st|nd|rd|th)\s+century(?:\s*\((.+)\))?\z/i
      SPAN = /\A(\d{3,4})\s*-\s*(\d{3,4})\z/
      DISPLAYING = /Displaying\s+\d+\s*-\s*\d+\s+of\s+(\d+)\s+sources/

      # {source id => Source} over every listing page in +workdir+ (an
      # attic directory reads the live pages beside it).
      def self.load(workdir)
        dir = File.basename(workdir) == Nabu::Adapter::ATTIC_DIRNAME ? File.dirname(workdir) : workdir
        Dir.glob(File.join(dir, PAGE_GLOB)).each_with_object({}) do |path, index|
          parse_page(SourceRead.utf8_file(path, label: "cantus listing")).each { |source| index[source.id] = source }
        end
      end

      def self.parse_page(html)
        doc = Nokogiri::HTML(html)
        table = doc.css("table").find { |candidate| candidate.at_css("a[href^='/source/']") } ||
                doc.at_css("table")
        columns = column_indexes(table)
        table.css("tbody tr").filter_map { |row| source_of(row.css("td"), columns) }
      end

      # Upstream's own advertised total ("Displaying 1-100 of 305 sources.").
      def self.page_total(html)
        match = Nokogiri::HTML(html).text.gsub(/\s+/, " ").match(DISPLAYING)
        match && Integer(match[1], 10)
      end

      # The highest page number the pagination block names (the page itself
      # when it is the last).
      def self.last_page(html)
        doc = Nokogiri::HTML(html)
        pagination = doc.at_css("div.pagination")
        return 1 if pagination.nil?

        numbers = pagination.css("a[href]").filter_map { |link| link["href"][/[?&]page=(\d+)/, 1] }
        numbers += pagination.css("b").map(&:text)
        numbers.map { |n| Integer(n.strip, 10, exception: false) }.compact.max || 1
      end

      def self.century_years(label)
        match = CENTURY.match(label.to_s.strip) or return nil
        n = Integer(match[1], 10)
        return nil if n.zero?

        low = ((n - 1) * 100) + 1
        high = n * 100
        qualifier = match[2].to_s.strip
        if (span = SPAN.match(qualifier))
          [Integer(span[1], 10), Integer(span[2], 10)]
        elsif qualifier.match?(/\A1st half\z/i)
          [low, low + 49]
        elsif qualifier.match?(/\A2nd half\z/i)
          [low + 50, high]
        else
          [low, high]
        end
      end

      # The source's date claim: the envelope over every century label
      # that parses, nil when none does.
      def self.date_of(centuries)
        bands = Array(centuries).filter_map { |label| century_years(label) }
        return nil if bands.empty?

        { "not_before" => bands.map(&:first).min, "not_after" => bands.map(&:last).max,
          "raw" => Array(centuries).join("; ") }
      end

      # The first provenance value that names a place, or nil.
      def self.place_of(provenance)
        Array(provenance).find { |value| !value.to_s.strip.empty? && !NON_PLACES.include?(value.to_s.strip) }
      end

      def self.column_indexes(table)
        headers = table ? table.css("thead th").map { |th| th.text.gsub(/\s+/, " ").strip } : []
        missing = REQUIRED_COLUMNS - headers
        unless missing.empty?
          raise Nabu::ParseError, "cantus sources listing lacks column(s) #{missing.join(', ')} " \
                                  "(upstream reshaped the Browse Sources table?)"
        end
        REQUIRED_COLUMNS.to_h { |name| [name, headers.index(name)] }
      end
      private_class_method :column_indexes

      def self.source_of(cells, columns)
        siglum_cell = cells[columns.fetch("Cantus Siglum")]
        link = siglum_cell&.at_css("a[href^='/source/']") or return nil
        id = link["href"][%r{/source/(\d+)}, 1] or return nil
        date_cell = cells[columns.fetch("Date/Origin")]
        summary_cell = cells[columns.fetch("Summary")]
        counts = squish(cells[columns.fetch("Chants / Melodies")]&.text).scan(/\d+/)
        chants, melodies = counts.map { |n| Integer(n, 10) }
        Source.new(
          id: Integer(id, 10), siglum: squish(link.text), country: squish(cells[columns.fetch("Country")]&.text),
          institution: squish(cells[columns.fetch("City + Holding Institution")]&.text),
          summary: squish(summary_cell&.[]("title")).then { |title| title.empty? ? squish(summary_cell&.text) : title },
          centuries: date_cell ? date_cell.css("a[href^='/century/']").map { |a| squish(a.text) } : [],
          provenance: date_cell ? date_cell.css("a[href^='/provenance/']").map { |a| squish(a.text) } : [],
          chants: chants, melodies: melodies
        )
      end
      private_class_method :source_of

      def self.squish(text) = text.to_s.gsub(/\s+/, " ").strip
      private_class_method :squish
    end
  end
end
