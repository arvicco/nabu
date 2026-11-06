# frozen_string_literal: true

require "nokogiri"

require_relative "statutes_realm_dating"

module Nabu
  module Adapters
    # One British History Online volume TOC page of the Statutes of the
    # Realm (/statutes-realm/vol<N>?page=<p>, 100 rows a page) → its rows,
    # each classed by grain, and the pager's next page. Shared by the fetch
    # (which crawls only the accepted rows) and discover (which mints them
    # and censuses the rest) — one classification, two consumers.
    #
    # Grains (census 2026-11-05 over all 723 rows of vols 5–7):
    #   :act           "<Reign>, <session>: <title>"            656 — ACCEPTED
    #   :private_acts  "<Reign>, <session>: The Private Acts"     5 — ACCEPTED
    #                  (vol. 7's schedules of private-act titles, the roll's
    #                  own Latin formula + the titles — roll text, not apparatus)
    #   :index         "Index: A" …                              53 — rejected
    #   :front_matter  "Preface", "Chronological table …"         5 — rejected
    #                  (Raithby's 1819 editorial prose; the chronological
    #                  table restates the act titles the TOC already carries)
    #   :engraving     "Engraving: …"                             4 — rejected
    #                  (plate pages: one image and its caption)
    #   :unknown       anything else — none today; censused unrecognized
    module StatutesRealmToc
      Row = Data.define(:volume, :slug, :title, :pages, :grain) do
        def accepted? = ACCEPTED.include?(grain)
      end

      ACCEPTED = %i[act private_acts].freeze

      def self.grain(title)
        title = title.to_s.strip
        return :index if title.start_with?("Index:")
        return :engraving if title.start_with?("Engraving:")
        return :front_matter if title == "Preface" || title.start_with?("Chronological table")

        heading = StatutesRealmDating.heading(title)
        return :unknown if heading.nil?

        heading.rest.start_with?("The Private Acts") ? :private_acts : :act
      end

      # The table rows linking into this volume, in page order.
      def self.rows(html, volume:)
        page = Nokogiri::HTML(html)
        page.css("td.views-field-title a[href]").filter_map do |link|
          slug = link["href"][%r{\A/statutes-realm/vol#{volume}/([^/?#]+)\z}, 1] or next
          title = squish(link.text)
          pages = squish(link.ancestors("tr").first&.at_css("td.views-field-field-biblio-pg-range")&.text.to_s)
          Row.new(volume: volume, slug: slug, title: title, pages: pages, grain: grain(title))
        end
      end

      # The pager's rel=next target page number, or nil on the last page.
      def self.next_page(html)
        href = Nokogiri::HTML(html).at_css("nav.pager a[rel=next]")&.[]("href") or return nil
        number = href[/[?&]page=(\d+)/, 1]
        number && Integer(number, 10)
      end

      def self.squish(text)
        Nabu::Normalize.nfc(text.tr(" ", " ").gsub(/[[:space:]]+/, " ").strip)
      end
    end
  end
end
