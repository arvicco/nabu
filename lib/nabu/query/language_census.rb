# frozen_string_literal: true

require_relative "../languages"
require_relative "../timeline"

module Nabu
  module Query
    # The two language-desk censuses of P121-2, read ONLY from the
    # precompiled rollups Store::LemmaRollup writes (the desk-commands law):
    #
    # - #curve(code) — `nabu language CODE --curve`: documents + passages
    #   per century (envelope-midpoint buckets, undated last) from
    #   language_curve.
    # - #mixing — `nabu language --mixing`: the multilingualism census from
    #   language_mix: documents by language-inventory size, the commonest
    #   mixed inventories, and the switch grain per source — "block"
    #   documents change language exactly (inventory − 1) times (each
    #   language one contiguous run: a facing translation, a bilingual
    #   appendix), "interleaved" ones switch more (line-by-line glossing,
    #   code-switching).
    #
    # Either returns a result whose +status+ is :absent (pre-migration
    # catalog), :unbuilt (tables empty) or :ok — never a live scan.
    class LanguageCensus
      CurvePoint = Data.define(:century, :label, :documents, :passages, :bases)
      CurveResult = Data.define(:status, :code, :points, :documents, :passages, :seconds)

      SourceGrain = Data.define(:slug, :mixed, :block, :interleaved, :switches)
      MixingResult = Data.define(:status, :documents, :by_size, :inventories, :sources, :seconds)

      # const: render ceilings for the census lists — a UX bound, not a corpus claim
      TOP_INVENTORIES = 10
      # const: render ceiling for the per-source switch-grain rows — a UX bound
      TOP_SOURCES = 15

      def initialize(catalog:)
        @catalog = catalog
      end

      def curve(code)
        started = clock
        status = table_status(Store::LemmaRollup::CURVE_TABLE)
        unless status == :ok
          return CurveResult.new(status: status, code: code, points: [], documents: 0, passages: 0,
                                 seconds: clock - started)
        end

        rows = @catalog[Store::LemmaRollup::CURVE_TABLE].where(language: Nabu::Languages.code_variants(code)).all
        points = rows.group_by { |row| row[:century] }
                     .sort_by { |century, _| century.nil? ? Float::INFINITY : century }
                     .map do |century, group|
                       CurvePoint.new(century: century,
                                      label: century ? Nabu::Timeline.century_label(century) : "undated",
                                      documents: group.sum { |row| row[:documents] },
                                      passages: group.sum { |row| row[:passages] },
                                      bases: group.filter_map { |row| row[:basis] }.uniq.sort)
                     end
        CurveResult.new(status: :ok, code: code, points: points,
                        documents: points.sum(&:documents), passages: points.sum(&:passages),
                        seconds: clock - started)
      end

      def mixing
        started = clock
        status = table_status(Store::LemmaRollup::MIX_TABLE)
        unless status == :ok
          return MixingResult.new(status: status, documents: 0, by_size: [], inventories: [], sources: [],
                                  seconds: clock - started)
        end

        mix = @catalog[Store::LemmaRollup::MIX_TABLE]
        by_size = mix.group_and_count(:language_count).order(:language_count)
                     .map { |row| [row[:language_count], row[:count]] }
        mixed = mix.where { language_count > 1 }
        inventories = mixed.group_and_count(:languages).order(Sequel.desc(:count), :languages)
                           .limit(TOP_INVENTORIES).map { |row| [row[:languages], row[:count]] }
        MixingResult.new(status: :ok, documents: by_size.sum(&:last), by_size: by_size,
                         inventories: inventories, sources: source_grains(mixed), seconds: clock - started)
      end

      private

      def table_status(table)
        return :absent unless @catalog.table_exists?(table)

        @catalog[table].empty? ? :unbuilt : :ok
      end

      def source_grains(mixed)
        block = Sequel.case([[{ switches: Sequel[:language_count] - 1 }, 1]], 0)
        mixed.join(:sources, id: :source_id)
             .group(Sequel[:sources][:slug])
             .select(Sequel[:sources][:slug],
                     Sequel.function(:count).*.as(:mixed),
                     Sequel.function(:sum, block).as(:block),
                     Sequel.function(:sum, :switches).as(:switches))
             .order(Sequel.desc(:mixed), Sequel[:sources][:slug])
             .limit(TOP_SOURCES)
             .map do |row|
               SourceGrain.new(slug: row[:slug], mixed: row[:mixed], block: row[:block],
                               interleaved: row[:mixed] - row[:block], switches: row[:switches])
             end
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
