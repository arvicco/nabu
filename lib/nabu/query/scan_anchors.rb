# frozen_string_literal: true

require "yaml"

module Nabu
  module Query
    # The define → reference-scan bridges: a dictionary entry's PRINT
    # citation ("BDB p. 135", "Wb 1, 2.8") resolved to the held
    # local-library scan of the cited work and the PDF leaf of the printed
    # page. The rule surface is config/scan_anchors.yml — per cited work a
    # siglum pattern (a regex over the citation label with named captures
    # page, optional line, and volume for multi-volume works) and either one
    # shelf item (single volume) or a volumes map (volume as cited → item),
    # each with a leaf_offset calibration: printed page N sits on PDF page
    # N + leaf_offset (the local-library adapter mints PDF pages as
    # `<item>:p<page>`, 1-based, so the leaf IS that passage's page number).
    # A column-numbered work (unit: column — Holder's "AcS II: 1779", two
    # printed columns per page) captures (?<column>…) instead, and printed
    # column C sits on leaf ceil(C/2) + leaf_offset; its breaks key on
    # from_column.
    #
    # Query time, read-only, quasi-instant: one indexed document probe per
    # distinct item per query (memoized), one passage probe per anchored
    # citation. Nothing is stored; an ingest or a re-calibration shows on
    # the next define. Degradation is honest at every step and never an
    # error — each Anchor carries a status the renderers word:
    #
    # - :anchored      held, calibrated, and the leaf's page passage exists
    # - :held          held and calibrated, but no page passage at the leaf
    #                  (a scan without a text layer) — the document + leaf
    # - :uncalibrated  held, leaf_offset still null — the document, the
    #                  printed page named
    # - :out_of_range  the calibrated leaf falls before the scan's first page
    # - :not_held      item configured but absent (or withdrawn) in the catalog
    # - :unconfigured  no item for the work/volume in the config yet
    #
    # A label no pattern matches (the AED's "Wb 635", "Wb, passim", other
    # works' sigla) yields no anchor at all — the citation renders as before.
    class ScanAnchors
      class ConfigError < Nabu::Error; end

      FILENAME = "scan_anchors.yml"

      # The two print-locus units a work cites by. A page-numbered work
      # (BDB, the Wb) puts printed page N on one leaf; a column-numbered work
      # (Holder's Alt-celtischer Sprachschatz — two numbered columns per
      # printed page) puts columns 2k-1 and 2k on the same leaf.
      UNITS = %i[page column].freeze

      # One configured volume (or the single volume of a one-volume work).
      # +breaks+ is a list of [from, leaf_offset] pairs, descending by
      # +from+ (a printed page, or a printed column in column mode) — a
      # bound-in insert, a plate, or a rescanned run shifts the offset
      # mid-volume (the Wb's Lieferung title leaves; the duplicate leaves of
      # Holder's Google scan); the cited locus picks its offset.
      Volume = Data.define(:item, :leaf_offset, :breaks, :unit) do
        def offset_for(locus)
          hit = breaks.find { |from, _| locus >= from }
          hit ? hit[1] : leaf_offset
        end

        # The PDF leaf of +locus+: page N → N + k; column C → ceil(C/2) + k
        # (the printed-page index of a two-column page), k picked by the
        # locus through the breaks.
        def leaf_for(locus)
          index = unit == :column ? (locus + 1) / 2 : locus
          index + offset_for(locus)
        end
      end

      # One configured work: +volumes+ is {volume-as-cited => Volume}, or
      # {nil => Volume} for a single-volume work; +unit+ is :page or :column.
      Work = Data.define(:id, :title, :pattern, :volumes, :unit)

      # A label parsed against a work's pattern. +volume+ is the cited
      # volume string (nil for single-volume works); exactly one of +page+ /
      # +column+ is set (the work's unit); +line+ nil when the citation
      # names no line.
      Match = Data.define(:work, :title, :volume, :page, :column, :line) do
        def locus = page || column
      end

      # One resolved citation. +urn+ is the show-able target (the page
      # passage when :anchored, else the scan document; nil when not held);
      # +leaf+ nil unless calibrated and in range; +page+ / +column+ as on
      # Match.
      Anchor = Data.define(:work, :title, :volume, :page, :column, :line, :item, :leaf, :urn, :status) do
        # The renderers' shared wording (CLI line tail, MCP `pointer`).
        def pointer
          case status
          when :anchored then "#{urn} (scan leaf #{leaf}#{line_note})"
          when :held then "#{urn} (scan leaf #{leaf}#{line_note} — no page text; open the PDF at that page)"
          when :uncalibrated then "#{urn} (scan held; leaf offset not yet calibrated — find #{printed})"
          when :out_of_range then "#{urn} (#{printed} falls before the scan's first leaf — check the offset)"
          when :not_held then "scan not held — #{item} is not in this catalog (ingest it into local-library)"
          else "no scan configured for #{cited_work} (config/#{FILENAME})"
          end
        end

        private

        def printed = column ? "printed col. #{column}" : "printed p. #{page}"

        def line_note = line ? ", line #{line}" : ""

        def cited_work = volume ? "#{title} vol. #{volume}" : title
      end

      def self.load(path)
        new(YAML.safe_load_file(path) || {})
      end

      # The project table, or nil when the file is absent (a stripped
      # clone) — lane off, never an error (the FacetMap stance).
      def self.load_default(config:)
        path = File.join(config.config_dir, FILENAME)
        File.exist?(path) ? load(path) : nil
      end

      def initialize(doc)
        @works = (doc["works"] || {}).map { |id, spec| parse_work(id.to_s, spec || {}) }
      end

      attr_reader :works

      # The first work whose pattern matches +label+, parsed; nil when no
      # work claims it or the locus is malformed (no page/column, or 0).
      def match(label)
        @works.each do |work|
          m = work.pattern.match(label.to_s) or next
          locus = m[work.unit.to_s].to_i
          return nil unless locus.positive?

          volume = m.names.include?("volume") ? m[:volume].sub(/\A0+(?=\d)/, "") : nil
          line = m.names.include?("line") && m[:line] ? m[:line].to_i : nil
          return Match.new(work: work.id, title: work.title, volume: volume, line: line,
                           page: work.unit == :page ? locus : nil,
                           column: work.unit == :column ? locus : nil)
        end
        nil
      end

      # A per-query resolver over +catalog+ (memoizes the held-item probes).
      def resolver(catalog) = Resolver.new(self, catalog)

      def work(id) = @works.find { |work| work.id == id }

      # Resolves labels to Anchors against one catalog connection.
      class Resolver
        def initialize(table, catalog)
          @table = table
          @catalog = catalog
          @held = {}
        end

        # The Anchor for +label+, or nil when no configured work claims it.
        def anchor(label)
          match = @table.match(label) or return nil

          volume = @table.work(match.work).volumes[match.volume]
          item = volume&.item
          return build(match, item: item, status: :unconfigured) if item.nil?
          return build(match, item: item, status: :not_held) unless held?(item)
          return build(match, item: item, urn: item, status: :uncalibrated) if volume.leaf_offset.nil?

          leaf = volume.leaf_for(match.locus)
          return build(match, item: item, urn: item, status: :out_of_range) unless leaf.positive?

          page_urn = "#{item}:p#{leaf}"
          if page_passage?(page_urn)
            build(match, item: item, leaf: leaf, urn: page_urn, status: :anchored)
          else
            build(match, item: item, leaf: leaf, urn: item, status: :held)
          end
        end

        private

        def build(match, item:, status:, leaf: nil, urn: nil)
          Anchor.new(work: match.work, title: match.title, volume: match.volume, page: match.page,
                     column: match.column, line: match.line, item: item, leaf: leaf, urn: urn, status: status)
        end

        def held?(item)
          return @held[item] if @held.key?(item)

          @held[item] = !@catalog[:documents].where(urn: item, withdrawn: false).empty?
        end

        def page_passage?(urn)
          !@catalog[:passages].where(urn: urn, withdrawn: false).empty?
        end
      end

      private

      def parse_work(id, spec)
        pattern = compile(id, spec["pattern"])
        unit = parse_unit(id, spec["unit"])
        raise ConfigError, "scan_anchors: #{id} pattern needs a (?<#{unit}>…) capture" \
          unless pattern.names.include?(unit.to_s)

        other = (UNITS - [unit]).first
        if pattern.names.include?(other.to_s)
          raise ConfigError, "scan_anchors: #{id} is #{unit}-numbered — its pattern must not capture " \
                             "(?<#{other}>…) (declare unit: #{other} for a #{other}-numbered work)"
        end

        multi = spec.key?("volumes")
        if multi != pattern.names.include?("volume")
          raise ConfigError, "scan_anchors: #{id} — a (?<volume>…) capture and a volumes: map go together " \
                             "(single-volume works declare item/leaf_offset directly)"
        end

        volumes = if multi
                    (spec["volumes"] || {}).to_h { |key, row| [key.to_s, parse_volume(id, row || {}, unit: unit)] }
                  else
                    { nil => parse_volume(id, spec, unit: unit) }
                  end
        Work.new(id: id, title: (spec["title"] || id).to_s, pattern: pattern, volumes: volumes, unit: unit)
      end

      # unit: page (the default) or column.
      def parse_unit(id, value)
        return :page if value.nil?

        unit = value.to_s.to_sym
        raise ConfigError, "scan_anchors: #{id} unit must be one of #{UNITS.join(', ')}; got #{value.inspect}" \
          unless UNITS.include?(unit)

        unit
      end

      def compile(id, source)
        raise ConfigError, "scan_anchors: #{id} needs a pattern" if source.to_s.empty?

        Regexp.new(source.to_s)
      rescue RegexpError => e
        raise ConfigError, "scan_anchors: #{id} pattern does not compile — #{e.message}"
      end

      def parse_volume(id, row, unit:)
        item = row["item"]
        offset = row["leaf_offset"]
        raise ConfigError, "scan_anchors: #{id} item must be a urn string or null" \
          unless item.nil? || item.is_a?(String)
        raise ConfigError, "scan_anchors: #{id} leaf_offset must be an integer or null" \
          unless offset.nil? || offset.is_a?(Integer)

        Volume.new(item: item, leaf_offset: offset, unit: unit,
                   breaks: parse_breaks(id, row["breaks"], base: offset, key: "from_#{unit}"))
      end

      def parse_breaks(id, rows, base:, key:)
        return [] if rows.nil?
        raise ConfigError, "scan_anchors: #{id} breaks need a calibrated leaf_offset beside them" if base.nil?
        raise ConfigError, "scan_anchors: #{id} breaks must be a list" unless rows.is_a?(Array)

        parsed = rows.map do |row|
          from = row.is_a?(Hash) ? row[key] : nil
          offset = row.is_a?(Hash) ? row["leaf_offset"] : nil
          raise ConfigError, "scan_anchors: #{id} break rows are {#{key}: int, leaf_offset: int}" \
            unless from.is_a?(Integer) && from.positive? && offset.is_a?(Integer)

          [from, offset]
        end
        parsed.sort_by { |from, _| -from }
      end
    end
  end
end
