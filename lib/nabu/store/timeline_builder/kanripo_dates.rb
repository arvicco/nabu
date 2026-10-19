# frozen_string_literal: true

require_relative "../../period_bands"

module Nabu
  module Store
    module TimelineBuilder
      # Kanripo KR-Catalog dates (P104-1, under the aggressive-mining law): the catalog's
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
      #      (the mining law's distinct honestly-labeled grade-2 class);
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
        # Any org heading: its stars (the outline depth) and its title.
        OUTLINE_HEADING = /\A(\*+)\s+(\S.*?)\s*\z/
        PERSONS_HEADING = "人物"
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
          TimelineBuilder.writing_axes(catalog) do |axes|
            Dir.glob(File.join(dir, "KR?[a-z].txt")).each do |path|
              each_entry(path) do |kr_id, claim|
                document_id = ids["#{URN_PREFIX}#{kr_id}"] or next

                if claim.nil?
                  counts[:undated] += 1
                  next
                end
                insert(axes, document_id, claim)
                counts[:documents] += 1
              end
            end
          end
          counts
        end

        # Yields [kr_id, claim-or-nil] per catalog entry of one subclass
        # file — the dating view over #each_record.
        def each_entry(path)
          each_record(path) { |entry| yield entry[:id], best_claim(entry) }
        end

        # {kr_id => [person, …]} over every subclass file under
        # +catalog_dir+ (KR-Catalog/KR) — the adapter's person-metadata
        # view over the same reader. Absent dir → {}.
        def persons_by_text(catalog_dir)
          return {} unless Dir.exist?(catalog_dir)

          Dir.glob(File.join(catalog_dir, "KR?[a-z].txt")).each_with_object({}) do |path, index|
            each_record(path) { |entry| index[entry[:id]] = entry[:persons] unless entry[:persons].empty? }
          end
        end

        # Yields one record per catalog entry of one subclass file:
        #   { id:, own: (the entry's :KR_ID: drawer), first_person: (the
        #     dating ladder's first DATES/DYNASTY-bearing drawer),
        #     persons: [{ name:, part:, props:, functions: }, …] }
        # Streaming line scan: text headings open entries, deeper headings
        # build the org outline, :PROPERTIES: drawers collect into the open
        # scope (the entry's own drawer carries :KR_ID:). A person is a
        # heading directly under a 人物 heading — recorded at the heading
        # (a drawer-less block still names its person), its drawer, if
        # any, filling props. +part+ is nil for the text's own byline
        # (人物 directly under the text heading), else the heading above
        # 人物 (an appendix or an edition: "(附)考證", "WYG 道德眞經注").
        # :FUNCTION: may repeat inside one drawer — +functions+ keeps every
        # value in order (props keeps the last, the dating ladder's view).
        def each_record(path)
          scan = { entry: nil, outline: [], heading: nil, person: nil, drawer: nil }
          File.foreach(path) do |line|
            if (match = TEXT_HEADING.match(line))
              yield scan[:entry] if scan[:entry]
              scan.merge!(entry: { id: match[1], own: {}, first_person: nil, persons: [] },
                          outline: [], heading: nil, person: nil)
              next
            end
            scan_line(scan, line) if scan[:entry]
          end
          yield scan[:entry] if scan[:entry]
        end

        def scan_line(scan, line)
          if (match = OUTLINE_HEADING.match(line))
            depth = match[1].size
            scan[:outline] = scan[:outline].first(depth)
            scan[:outline][depth] = match[2]
            scan[:heading] = match[2] if depth >= 4
            scan[:person] = person_at(scan[:entry], scan[:outline], depth)
          elsif line.include?(":PROPERTIES:")
            scan[:drawer] = {}
          elsif scan[:drawer] && line.include?(":END:")
            file_drawer(scan[:entry], scan[:heading], scan[:drawer])
            scan[:person][:props] = scan[:drawer] if scan[:person]
            scan[:person] = nil
            scan[:drawer] = nil
          elsif scan[:drawer] && (match = PROPERTY.match(line))
            scan[:drawer][match[1]] = match[2]
            scan[:person][:functions] << match[2] if scan[:person] && match[1] == "FUNCTION" && !match[2].empty?
          end
        end

        # A heading directly under a 人物 heading opens a person record
        # (appended to the entry); any other heading closes person scope.
        def person_at(entry, outline, depth)
          return nil unless depth >= 5 && outline[depth - 1] == PERSONS_HEADING

          record = { name: outline[depth], part: depth == 5 ? nil : outline[depth - 2],
                     props: {}, functions: [] }
          entry[:persons] << record
          record
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

        def insert(axes, document_id, claim)
          axes.insert(
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
