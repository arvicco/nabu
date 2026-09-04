# frozen_string_literal: true

require "zlib"

module Nabu
  # Producer #10 for the links journal (P96-5): the KITAB text-reuse
  # statistics (zenodo 11501559, v2023.1.8, CC BY-NC-SA 4.0) over the
  # HELD OpenITI corpus — kind=reuse edges at DOCUMENT grain, the
  # intertext desk's Arabic feeder. v1 reads the 164 MB stats TSV (one
  # row per book-version pair with alignment counts and character-match
  # statistics); the 10 GB passage-grain pairwise archive is a
  # deliberate v2.
  #
  # == The join
  #
  # The stats file keys pairs by OpenITI version ids (_T1/_T2 —
  # "JK000710", "Shamela0005978"); the held openiti documents carry the
  # same id inside their urns (…​.JK000710-ara1), so the producer builds
  # {version id → urn} from the catalog once and joins in memory. Rows
  # where either side is not held are skipped and censused — the stats
  # cover OpenITI whole, the library holds its ruled first wave.
  #
  # == The floor (censused, never silent)
  #
  # MIN_INSTANCES: a pair attested by a single aligned instance is kept
  # out of the journal (the release's own long tail of one-window
  # touches); the census reports how many rows the floor dropped so the
  # constant stays an era-bound, revisitable claim.
  class KitabReuse
    PRODUCER = "kitab-reuse"
    KIND = "reuse"
    CODE_VERSION = "kitab-reuse/1 nabu/#{VERSION}".freeze

    STATS_FILENAME = "KITAB-TextReuse-stats.csv.gz"
    SOURCE_SLUG = "openiti"

    # const: the v1 pair floor (class note) — census-reported
    MIN_INSTANCES = 2
    TICK = 50_000

    VERSION_ID = /\.([A-Za-z0-9]+)-[a-z]{3}\d*\z/

    Census = Data.define(:rows, :held_pairs, :skipped_unheld, :skipped_floor)
    Result = Data.define(:census, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges)

    def initialize(catalog:, journal:, progress: nil)
      @catalog = catalog
      @journal = journal
      @progress = progress
    end

    # The reference-producer seam signature (SyncRunner passes the slug).
    def run(_slug = nil, workdir:)
      path = File.join(workdir, STATS_FILENAME)
      return nil unless File.file?(path)

      versions = held_versions
      @progress&.stage("kitab-reuse: joining the stats TSV against #{versions.size} held " \
                       "openiti versions (streamed; ~1.6M pairs upstream)")
      counts = { inserted: 0, refreshed: 0 }
      census = { rows: 0, held_pairs: 0, skipped_unheld: 0, skipped_floor: 0 }
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: SOURCE_SLUG)
        run_id = Store::LinksJournal.record_run!(
          @journal, producer: PRODUCER, scope: SOURCE_SLUG,
                    params: { kind: KIND, min_instances: MIN_INSTANCES }, code_version: CODE_VERSION
        )
        each_stats_row(path) do |row|
          census[:rows] += 1
          @progress&.load_tick(census[:rows], 0) if (census[:rows] % TICK).zero?
          process_row(row, versions, run_id, counts, census)
        end
      end
      Result.new(census: Census.new(**census), run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1])
    end

    private

    # { OpenITI version id => held document urn } — the urn's version
    # segment (….<VersionId>-ara1) is the stats file's _T1/_T2 space.
    def held_versions
      @catalog[:documents]
        .join(:sources, id: :source_id)
        .where(Sequel[:sources][:slug] => SOURCE_SLUG, Sequel[:documents][:withdrawn] => false)
        .select_map(Sequel[:documents][:urn])
        .each_with_object({}) do |urn, map|
          id = urn[VERSION_ID, 1]
          map[id] = urn if id
        end
    end

    def each_stats_row(path)
      Zlib::GzipReader.open(path) do |gz|
        header = nil
        gz.each_line do |line|
          fields = line.chomp.split("\t")
          if header.nil?
            header = fields
            next
          end
          yield header.zip(fields).to_h
        end
      end
    end

    def process_row(row, versions, run_id, counts, census)
      from = versions[row["_T1"]]
      to = versions[row["_T2"]]
      if from.nil? || to.nil?
        census[:skipped_unheld] += 1
        return
      end
      instances = row["instances"].to_i
      if instances < MIN_INSTANCES
        census[:skipped_floor] += 1
        return
      end

      census[:held_pairs] += 1
      outcome = Store::LinksJournal.write_edge!(
        @journal, from_urn: from, to_urn: to, kind: KIND,
                  score: instances, run_id: run_id,
                  detail: "#{instances} aligned instances · #{row['ch_MATCHES_Min']}–" \
                          "#{row['ch_MATCHES_Max']} chars · #{row['chrono_B1B2']}"
      )
      counts[outcome == :inserted ? :inserted : :refreshed] += 1
    end
  end
end
