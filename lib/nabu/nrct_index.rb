# frozen_string_literal: true

require "csv"
require_relative "pleiades"

module Nabu
  # The NRCT read seam (P108-2, the chgis mold): the 日本歴史地名大系
  # placename dataset (Heibonsha's historical gazetteer of Japan,
  # published machine-readable by ROIS-DS/NII geoshape; CC BY 4.0, DOI
  # 10.20676/00000448), parsed from the one CSV into the "nrct" slice
  # of the namespaced place index — the Japanese places lane's name
  # keys. Read-only on canonical.
  #
  # == The artifact (censused 2026-09-29, the 2025-07-19 cut)
  #
  # ONE headered CSV, 80,502 rows: 12-digit id, prefecture code, 名称
  # (the placename), 読み (kana reading), 上位地名 (the parent
  # placename — the homonym discriminator), 出典住所 (source address),
  # WGS84 lat/lon, 推定手法 (coordinate-estimation method), and for
  # 20,099 rows a 歴史地名ID + 歴史地名 pair naming the HISTORICAL
  # form where it differs from 名称 (鍛冶町 ← 鍛冶村).
  #
  # == Name keys
  #
  # Each place contributes the 名称 verbatim (the shared key rule
  # leaves Han/kana untouched), the 読み reading, and the 歴史地名
  # when present — so a text's 鍛冶村 finds the modern 鍛冶町 row.
  #
  # == Honest scope notes
  #
  # No time_periods: the dataset maps historical names to modern
  # locations and carries no year spans. 推定手法 and 出典住所 are
  # deliberately unread (coordinate provenance, not identity); the
  # geolod_id column is a future crosswalk seam, unread v1.
  module NrctIndex
    CSV_FILENAME = "nrct.csv"
    GAZETTEER = "nrct"

    Row = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods,
                      :name_keys, :parent)

    module_function

    def csv_path(workdir)
      path = File.join(workdir, CSV_FILENAME)
      File.file?(path) ? path : nil
    end

    def each_row(path)
      return enum_for(:each_row, path) unless block_given?

      CSV.foreach(path, headers: true, encoding: "UTF-8") do |record|
        yield build_row(record)
      end
    end

    def build_row(record)
      name = record["名称"].to_s.strip
      Row.new(
        id: record.fetch("id"),
        title: name,
        lat: float_or_nil(record["緯度"]), lon: float_or_nil(record["経度"]),
        place_types: [], time_periods: [],
        name_keys: [name, record["読み"], record["歴史地名"]]
                   .map { |n| n.to_s.strip }.reject(&:empty?)
                   .map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        parent: blank_to_nil(record["上位地名"])
      )
    end

    def blank_to_nil(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end

    def float_or_nil(value)
      Float(value.to_s.strip, exception: false)
    end

    # The sync/rebuild derivation seam (the chgis Producer mold): the
    # nrct place-index slice, wholesale. No CSV → honest no-op; the
    # 80k-row walk is seconds (line-streamed).
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        path = NrctIndex.csv_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        places = NrctIndex.each_row(path).to_a
        count = Store::PlaceIndex.derive!(
          @catalog, gazetteer: GAZETTEER, places: places, names_for: :name_keys.to_proc
        )
        return nil if count.nil?

        Store::PlaceIndex::Producer::Census.new(
          places: count,
          seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        )
      end
    end
  end
end
