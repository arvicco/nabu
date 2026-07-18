# frozen_string_literal: true

require "json"

require_relative "../../date_axis"
require_relative "../../wiki_fetch"
require_relative "../../adapters/wiki_template_parser"
require_relative "../../adapters/vienna_wiki"

module Nabu
  module Store
    module AxisBuilder
      # Vienna wiki dating + findspot → the date/place axis (P29-3) — one
      # module serving BOTH wiki slugs (lexlep, tir; same template
      # vocabulary): reads canonical/<slug>/pages/Inscription/*.json, joins
      # filename → urn → document_id, follows the |object= param to the
      # cached Object page and inserts one row per dated OR placed
      # document.
      #
      # - The object's +sortdate+ is a signed historical point year the
      #   wiki maintains for SORTING ("-100" beside date "late 2nd–early
      #   1st c. BC") → not_before = not_after = sortdate with precision
      #   "circa" — a sort key is an approximation, never "exact"; date_raw
      #   keeps the object's own display text. sortdate=0 is the wiki's
      #   "unknown" filler (censused: it pairs with date=unknown — AK-1
      #   rock, BG·1 Bergamo), not a phantom year 0: read as undated,
      #   counted, never DateAxis-invalid.
      # - place_name = the object's |site= (the wiki's own Site page title,
      #   "Pfatten / Vadena"); place_ref stays nil (no external gazetteer
      #   id on the wiki side — the §1.4 no-resolution stance). WGS84
      #   coordinates stay canonical + document metadata (the EDH
      #   coordinates decision — the axis has no coordinate columns).
      module ViennaWikiDates
        # slug → urn prefix; one walk each, shared extraction.
        SLUGS = { "lexlep" => "urn:nabu:lexlep:", "tir" => "urn:nabu:tir:" }.freeze

        module_function

        # Walk both wikis' canonical pages, insert axis rows. Returns
        # { lexlep: { documents:, undated:, invalid: }, tir: { … } } —
        # +undated+ counts joined inscriptions with a place-only row or no
        # row, +invalid+ the DateAxis year tripwire (unreachable for the
        # 0-filler, kept for honesty against upstream drift).
        def build(catalog:, canonical_dir:)
          SLUGS.to_h do |slug, urn_prefix|
            [slug.to_sym, build_slug(catalog, canonical_dir, slug, urn_prefix)]
          end
        end

        def build_slug(catalog, canonical_dir, slug, urn_prefix)
          counts = { documents: 0, undated: 0, invalid: 0 }
          root = File.join(canonical_dir, slug)
          paths = Dir.glob(File.join(root, WikiFetch::PAGES_DIRNAME,
                                     Adapters::ViennaWiki::INSCRIPTION_CATEGORY, "*.json"))
          return counts if paths.empty?

          urn_ids = catalog[:documents].where(Sequel.like(:urn, "#{urn_prefix}%")).select_hash(:urn, :id)
          paths.each do |path|
            document_id = urn_ids[urn_for(path, urn_prefix)] or next

            insert_row(catalog, document_id, root, path, slug, counts)
          end
          counts
        end

        def urn_for(path, urn_prefix)
          title = WikiFetch.decode_title(File.basename(path, ".json"))
          "#{urn_prefix}#{Adapters::ViennaWiki.title_segment(title)}"
        end

        def insert_row(catalog, document_id, root, path, slug, counts)
          axis = extract(root, path)
          if axis == :invalid
            counts[:invalid] += 1
            return
          end
          counts[:undated] += 1 if axis.nil? || axis[:not_before].nil?
          return if axis.nil?

          AxisBuilder.insert_axis(catalog, document_id, axis, slug)
          counts[:documents] += 1
        end

        # One inscription's axis fields via its cached Object page; nil
        # when it carries neither date nor place (or the object page is
        # not cached — an honest absence), :invalid on a DateAxis-rejected
        # year.
        def extract(root, path)
          object = object_params(root, path)
          return nil if object.nil?

          begin
            year = sort_year(object["sortdate"])
          rescue DateAxis::InvalidYear
            return :invalid
          end
          place = AxisBuilder.normalize(object["site"])
          return nil if year.nil? && place.nil?

          date_raw = AxisBuilder.normalize(object["date"])
          date_raw = nil if date_raw == "unknown"
          {
            not_before: year, not_after: year,
            precision: year ? "circa" : nil,
            date_raw: date_raw,
            place_name: place, place_ref: nil
          }
        end

        # The wiki's 0 filler reads as no date (class note); everything
        # else goes through the strict DateAxis parse.
        def sort_year(raw)
          value = raw.to_s.strip
          return nil if value.empty? || value.match?(/\A-?0+\z/)

          DateAxis.parse_year(value)
        end

        def object_params(root, inscription_path)
          wikitext = read_wikitext(inscription_path) or return nil
          params = parser.template_params(wikitext, "inscription") or return nil
          object_title = params["object"].to_s.strip
          return nil if object_title.empty?

          object_path = File.join(root, WikiFetch::PAGES_DIRNAME,
                                  Adapters::ViennaWiki::OBJECT_CATEGORY,
                                  "#{WikiFetch.encode_title(object_title)}.json")
          object_wikitext = read_wikitext(object_path) or return nil
          parser.template_params(object_wikitext, "object")
        end

        def read_wikitext(path)
          return nil unless File.file?(path)

          wikitext = JSON.parse(File.read(path))["wikitext"]
          wikitext.is_a?(String) ? wikitext : nil
        rescue JSON::ParserError
          nil # a broken page costs its axis row, never the build
        end

        def parser
          @parser ||= Adapters::WikiTemplateParser.new
        end
      end
    end
  end
end
