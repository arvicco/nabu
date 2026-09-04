# frozen_string_literal: true

require_relative "pleiades"
require_relative "adapters/corph_sql_parser"

module Nabu
  # The CHGIS read seam (P96-1): the China Historical GIS / Temporal
  # Gazetteer (Harvard–Fudan; Berman, Bol et al.), parsed from the TGAZ
  # MySQL dump into the "chgis" slice of the namespaced place index —
  # historical-China name keys for Q9 and the place desk. Read-only on
  # canonical.
  #
  # == The artifact and the one table
  #
  # The canonical asset is the CC0 TGAZ backup (Harvard Dataverse
  # doi:10.7910/DVN/H3OB28, tgaz_bak_2018.zip → tgaz_bak_2018.sql,
  # 122 MB, 38 tables). ONE table serves the index: `mv_pn_srch`, the
  # dump's own search materialization — one flat row per placename
  # (82,117 censused 2026-09-04) carrying the tgaz sys_id ("hvd_1"),
  # the hanzi name, the pinyin transcription, begin/end years, WGS84
  # coordinates, the feature type in both scripts, and the parent unit.
  # The dump's INSERTs carry no column list (plain mysqldump), so the
  # walker is fed the CREATE TABLE order below (COLUMNS).
  #
  # == Name keys (the Q9 substrate)
  #
  # Each place contributes BOTH written forms as exact-match keys: the
  # hanzi name verbatim (folded through the shared key rule, which
  # leaves Han text untouched) and the pinyin transcription folded
  # Latin-wise ("Ba Zhou" → "ba zhou"). Q9's Sinitic matching runs on
  # the hanzi keys; `--place` input in either script resolves.
  #
  # == Honest scope notes
  #
  # No crosswalk rows v1: mv_pn_srch asserts no external ids (CHGIS is
  # its own id space; the nabu-places `chgis:` namespace mint rides as
  # a sister PR). Feature types ride place_types (transcribed form);
  # the year span rides time_periods as one "beg–end" string. The
  # dump's other 37 tables (spellings variants, part_of graph,
  # temporal annotations) are future refinements, deliberately unread.
  module ChgisIndex
    SQL_FILENAME = "tgaz_bak_2018.sql"
    GAZETTEER = "chgis"
    TABLE = "mv_pn_srch"

    # CREATE TABLE order, verbatim from the dump (the walker's column
    # list — plain-mysqldump INSERTs omit their own).
    COLUMNS = %w[
      id sys_id data_src name transcription beg_yr end_yr obj_type
      x_coord y_coord ftype_vn ftype_tr parent_id parent_sys_id
      parent_vn parent_tr
    ].freeze

    Row = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods,
                      :name_keys, :parent)

    module_function

    def sql_path(workdir)
      path = File.join(workdir, SQL_FILENAME)
      File.file?(path) ? path : nil
    end

    def each_row(path)
      return enum_for(:each_row, path) unless block_given?

      Adapters::CorphSqlParser.new(path).each_row(TABLE, columns: COLUMNS) do |record|
        yield build_row(record)
      end
    end

    def build_row(record)
      name = record["name"].to_s.strip
      transcription = record["transcription"].to_s.strip
      Row.new(
        id: record.fetch("sys_id"),
        title: name.empty? ? transcription : name,
        lat: float_or_nil(record["y_coord"]), lon: float_or_nil(record["x_coord"]),
        place_types: [record["ftype_tr"], record["ftype_vn"]].compact.map(&:strip).reject(&:empty?).uniq,
        time_periods: time_periods(record),
        name_keys: [name, transcription].reject(&:empty?)
                                        .map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        parent: record["parent_sys_id"]
      )
    end

    def time_periods(record)
      beg_yr = record["beg_yr"]
      end_yr = record["end_yr"]
      return [] if beg_yr.nil? && end_yr.nil?

      [[beg_yr, end_yr].compact.uniq.join("–")]
    end

    def float_or_nil(value)
      Float(value.to_s.strip, exception: false)
    end

    # The sync/rebuild derivation seam (the cigs Producer mold): the
    # chgis place-index slice, wholesale. No dump → honest no-op. The
    # 82k-row walk over a 122 MB file announces via the census result;
    # the walk itself is seconds (line-streamed).
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def run(_slug, workdir:)
        path = ChgisIndex.sql_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rows = ChgisIndex.each_row(path).to_a
        count = Store::PlaceIndex.derive!(
          @catalog, gazetteer: GAZETTEER, places: rows, names_for: :name_keys.to_proc
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
