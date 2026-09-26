# frozen_string_literal: true

require_relative "../../period_bands"

module Nabu
  module Store
    module TimelineBuilder
      # Kanripo KR-Catalog dates (P104-1, Q77 under №R-70): the catalog's
      # per-text org entries carry dating claims the shelf never minted —
      # 5,122 held documents sat `undatable` while the KR-Catalog states,
      # per text, an explicit :DATE: (672 entries), the first 人物
      # person's :DATES: life span (2,714 person blocks censused
      # 2026-09-26), or a :DYNASTY: attribution (5,117 blocks). The
      # claim ladder, best first, one row per text:
      #
      #   1. the entry's own :DATE: — a clean 3/4-digit year mints a
      #      typed one-year envelope (precision "year"); the 389
      #      era-name years (乾隆十三年) stay unminted — regnal-year
      #      arithmetic is deliberately out (the ebl P81-1 stance);
      #   2. the FIRST 人物 person block (the byline order: the author
      #      leads, commentators follow — 史記 lists 司馬遷 before its
      #      唐/清 commentators): :DATES: mint the author-life envelope,
      #      else :DYNASTY: bands through the ruled period_bands.yml
      #      sinological rows — both ATTRIBUTIONS, precision "era"
      #      (№R-70's distinct honestly-labeled grade-2 class);
      #   3. the entry's own :DYNASTY: (the Daozang shape — KR5 texts
      #      carry it in the text drawer), banded the same way.
      #
      # A text none of the rungs reach is counted undated, never
      # guessed; "ca." qualifiers stay in date_raw, year 0 (no such
      # year) invalidates the rung. Withdrawn/unheld texts never row.
      module KanripoDates
        SLUG = "kanripo"
        URN_PREFIX = "urn:nabu:kanripo:"
        CATALOG_DIR = File.join("KR-Catalog", "KR").freeze

        TEXT_HEADING = /\A\*{3}\s+(KR\d[a-z]\d{4})\b/
        PERSON_HEADING = /\A\*{4,}\s+(\S.*?)\s*\z/
        PROPERTY = /\A\s*:([A-Za-z_]+):\s*(.*?)\s*\z/
        CLEAN_YEAR = /\A\d{3,4}\z/
        # ":DATES: ca. -145 - ca. -86" | "fl. 874 - 888" | "1249 - 1333" |
        # a single year — ca./fl. qualifiers stay in date_raw, the span is
        # upstream's own (a floruit span is attested activity, an honest
        # attribution envelope).
        LIFE_SPAN = /\A(?:(?:ca|fl)\.\s*)?(-?\d{1,4})(?:\s*-\s*(?:(?:ca|fl)\.\s*)?(-?\d{1,4}))?\z/

        module_function

        # Walk the KR-Catalog subclass files and insert one row per held,
        # claim-bearing text. Returns { documents:, undated: } — +undated+
        # counts HELD texts whose entry offers no rung.
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, SLUG, CATALOG_DIR)
          return { documents: 0, undated: 0 } unless Dir.exist?(dir)

          ids = catalog[:documents]
                .where(Sequel.like(:urn, "#{URN_PREFIX}%"))
                .where(withdrawn: false)
                .select_hash(:urn, :id)
          counts = { documents: 0, undated: 0 }
          Dir.glob(File.join(dir, "KR?[a-z].txt")).each do |path|
            each_entry(path) do |kr_id, claim|
              document_id = ids["#{URN_PREFIX}#{kr_id}"] or next

              if claim.nil?
                counts[:undated] += 1
                next
              end
              insert(catalog, document_id, claim)
              counts[:documents] += 1
            end
          end
          counts
        end

        # Yields [kr_id, claim-or-nil] per catalog entry of one subclass
        # file. Streaming line scan: text headings open entries, deeper
        # headings name persons, :PROPERTIES: drawers collect into the
        # open scope (the entry's own drawer carries :KR_ID:; any other
        # drawer is a person block).
        def each_entry(path)
          entry = nil
          person = nil
          drawer = nil
          File.foreach(path) do |line|
            if (match = TEXT_HEADING.match(line))
              yield entry[:id], best_claim(entry) if entry
              entry = { id: match[1], own: {}, first_person: nil }
              person = nil
              next
            end
            next if entry.nil?

            if (match = PERSON_HEADING.match(line))
              person = match[1]
            elsif line.include?(":PROPERTIES:")
              drawer = {}
            elsif drawer && line.include?(":END:")
              file_drawer(entry, person, drawer)
              drawer = nil
            elsif drawer && (match = PROPERTY.match(line))
              drawer[match[1]] = match[2]
            end
          end
          yield entry[:id], best_claim(entry) if entry
        end

        def file_drawer(entry, person, drawer)
          if drawer.key?("KR_ID")
            entry[:own] = drawer
          elsif entry[:first_person].nil? && (drawer.key?("DATES") || drawer.key?("DYNASTY"))
            entry[:first_person] = drawer.merge("NAME" => person)
          end
        end

        # The ladder (class note): own DATE → first-person DATES →
        # first-person DYNASTY → own DYNASTY; nil when no rung holds.
        def best_claim(entry)
          own_date(entry[:own]) || person_claim(entry[:first_person]) ||
            dynasty_claim(entry[:own]["DYNASTY"], name: nil)
        end

        def own_date(own)
          date = own["DATE"].to_s
          return nil unless date.match?(CLEAN_YEAR)

          year = Integer(date, 10)
          { not_before: year, not_after: year, precision: "year", raw: "DATE #{date}" }
        end

        def person_claim(person)
          return nil if person.nil?

          label = ["人物", person["NAME"], person["DYNASTY"] && "(#{person['DYNASTY']})"].compact.join(" ")
          life_span(person["DATES"], label: label) || dynasty_claim(person["DYNASTY"], name: label)
        end

        def life_span(dates, label:)
          match = LIFE_SPAN.match(dates.to_s) or return nil

          years = [Integer(match[1], 10), match[2] ? Integer(match[2], 10) : Integer(match[1], 10)]
          return nil if years.any?(&:zero?) # there is no year 0

          { not_before: years.min, not_after: years.max, precision: "era",
            raw: "#{label} #{dates}" }
        end

        def dynasty_claim(dynasty, name:)
          band = Nabu::PeriodBands.default&.lookup(dynasty)
          return nil if band.nil?

          { not_before: band[0], not_after: band[1], precision: "era",
            raw: name || "(#{dynasty})" }
        end

        def insert(catalog, document_id, claim)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: claim[:not_before], not_after: claim[:not_after],
            precision: claim[:precision], date_raw: claim[:raw],
            axis_source: SLUG
          )
        end
      end
    end
  end
end
