# frozen_string_literal: true

require "nokogiri"

require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # The ITKC 서지 (bibliographic) catalog read seam: the 한국고전종합DB
      # OpenAPI's per-work records as the itkc-catalog module holds them —
      # one XML response page per file under canonical/itkc-catalog/<section>/
      # (Adapters::ItkcCatalog#fetch) — read into one Record per work, and the
      # author-era Band the timeline's ItkcAuthorDates lane mints from it.
      #
      # == The record (a 서지 doc, fields by name)
      #
      # 서지ID (the work id: ITKC_MO_0004A — the prefix every okhc klc record
      # id and every held itkc fascicle file carries), 서명 (title), 저자
      # ("한글|漢字"; "미상|" when unknown), 저자생년 / 저자몰년 (the author's
      # birth / death year), 간행년 (the original print year — the itkc 서지
      # sidecar's 원문간행년 for the same work, checked on ITKC_MO_1250A — or
      # the prose "미상"). Census of the MO_SJ section, 2026-10-19 (1,259
      # records): every birth is a year, "0" on 8 (the unknown filler — there
      # is no year 0); every death a year, "9999" on 18 (the unknown filler);
      # 간행년 a year on 1,046, "미상" on 213. No era-name or dynasty-only
      # entries exist, so nothing needs the era tables.
      #
      # == The band (composition class, the kanripo :DATES: precedent)
      #
      # An author's attested life brackets when the works of their 문집 were
      # written — an attribution about the WORK, never a typed date of any one
      # text in it (a preface by a later hand rides the same band, which is why
      # the class is labeled). The rule, per record:
      #
      # - lower bound: the birth year, else open;
      # - upper bound: the death year, else the original print year when it
      #   does not precede the birth (the munjip existed in print by then — a
      #   terminus ante quem, posthumous prints included), else nothing;
      # - no upper bound → no band: a birth-only claim leaves the work
      #   unbounded toward the present, which says almost nothing and would
      #   satisfy every later date filter. Counted undated, never guessed.
      #
      # Placed with the corpus builders, not beside the adapter: its parse
      # and band rules shape document_axes rows only, so the builders digest
      # covers it — a rule change re-runs the timeline without dirtying any
      # per-source stamp (the date_shelf.rb reader precedent).
      module ItkcCatalogRecords
        SLUG = "itkc-catalog"
        SECTIONS = %w[MO_SJ GO_SJ KP_SJ].freeze
        UNKNOWN_BIRTH = 0
        UNKNOWN_DEATH = 9999
        YEAR = /\A-?\d{1,4}\z/
        ATTIC_DIRNAME = ".attic"

        Record = Data.define(:id, :section, :title, :author_hangul, :author_hanja, :birth, :death, :print_year)
        Page = Data.define(:section, :start, :total, :records)
        Band = Data.define(:not_before, :not_after, :raw)

        module_function

        # {서지ID => Record} over every page under +dir+ (the module workdir);
        # attic pages never read, an absent dir reads empty.
        def records(dir)
          page_paths(dir).each_with_object({}) do |path, index|
            parse_page(File.read(path, encoding: "UTF-8")).records.each { |record| index[record.id] = record }
          end
        end

        def page_paths(dir)
          SECTIONS.flat_map { |section| Dir.glob(File.join(dir, section, "*.xml")).sort }
        end

        # One response page: its header census and its records. Raises
        # Nabu::ParseError when the body is no API response.
        def parse_page(xml)
          doc = Nokogiri::XML(xml) { |config| config.strict.nonet }
          header = doc.xpath("/response/header/field").to_h { |field| [field["name"], field.text.strip] }
          raise Nabu::ParseError, "itkc-catalog: not an OpenAPI response (no header)" if header.empty?

          section = header["secId"].to_s
          Page.new(section: section, start: Integer(header.fetch("start", "0"), 10),
                   total: Integer(header.fetch("totalCount", "0"), 10),
                   records: doc.xpath("/response/result/doc").filter_map { |node| record(node, section) })
        rescue Nokogiri::XML::SyntaxError, ArgumentError => e
          raise Nabu::ParseError, "itkc-catalog: unreadable response page (#{e.message})"
        end

        def record(node, section)
          fields = node.xpath("field").to_h { |field| [field["name"], Normalize.nfc(field.text.strip)] }
          id = fields["서지ID"].to_s
          return nil if id.empty?

          hangul, hanja = fields["저자"].to_s.split("|", 2).map { |form| form.strip.empty? ? nil : form.strip }
          Record.new(id: id, section: section, title: fields["서명"],
                     author_hangul: hangul, author_hanja: hanja,
                     birth: year(fields["저자생년"], unknown: UNKNOWN_BIRTH),
                     death: year(fields["저자몰년"], unknown: UNKNOWN_DEATH),
                     print_year: year(fields["간행년"], unknown: nil))
        end

        def year(value, unknown:)
          text = value.to_s.strip
          return nil unless text.match?(YEAR)

          parsed = Integer(text, 10)
          parsed.zero? || parsed == unknown ? nil : parsed
        end

        # The record's author-era Band, or nil when nothing bounds the work
        # above (module note).
        def band(record)
          upper = record.death
          print_bound = record.death.nil? && record.print_year &&
                        (record.birth.nil? || record.print_year >= record.birth)
          upper ||= record.print_year if print_bound
          return nil if upper.nil?

          Band.new(not_before: record.birth, not_after: upper, raw: raw(record, print_bound))
        end

        def raw(record, print_bound)
          author = [record.author_hangul, record.author_hanja].compact.join(" ")
          life = "#{record.birth || '?'}–#{record.death || '?'}"
          print = print_bound ? " · 원문간행년 #{record.print_year}" : ""
          "저자 #{author} #{life}#{print} (#{record.id} 서지)"
        end
      end
    end
  end
end
