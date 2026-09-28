# frozen_string_literal: true

require "csv"
require_relative "store/links_journal"
require_relative "version"

module Nabu
  # The Qieyun–Guangyun small-rime crosswalk producer (P107, the Q78
  # sidecar harvest; the Burman/KyotoKanripo mold): re-derives
  # kind=reference edges from the qieyun-restored repo's
  # to_tshet_uinh_data/small_rimes.csv after every sync — 3,385 small
  # rimes, each carrying the upstream-curated 對應廣韻小韻號 join into
  # the held guangyun shelf. One edge per small rime, representative
  # entry to representative entry: the qieyun side resolves through
  # 藤田條目號 (= the representative row's 序数 in the main table, whose
  # (頁, 行) pair is the shelf's entry id), the guangyun side is the
  # small-rime head 小韻號.1. The mapping is the TABLE's, never
  # arithmetic — the Guangyun's added rimes shift the numbering from 冬
  # on (qieyun 33 → guangyun 35), which is the crosswalk's whole value.
  #
  # The 序数 numbering is SHARED with Li Yongfu's witness restoration
  # (its variant rows count too), so 46 of the 3,385 pointers name
  # ordinals Fujita's own table skips. Second lane: exact match on
  # upstream's own (音韻地位, 代表字) pair against Fujita's small-rime
  # HEAD rows (min-序数 per (聲調, 韻目, 小韻) group; ambiguous keys
  # dropped) — resolves the 20 rimes Fujita holds one row over (猪:
  # pointer 1679, head 1680; live census 2026-09-28, zero ambiguity).
  #
  # Honesty counters: a row neither lane resolves — the 26 rimes
  # genuinely absent from Fujita's restoration (19 marked 藤田無此小韻
  # upstream) — or with an empty 對應廣韻小韻號 counts skipped_unmapped,
  # never guessed. Edges mint independent of catalog presence —
  # dangling-but-stable (the P32-6 doctrine).
  class QieyunCrosswalk
    PRODUCER = "qieyun-restored"
    KIND = "reference"
    CODE_VERSION = "qieyun-crosswalk/1 nabu/#{VERSION}".freeze

    MAIN_CSV = "切韻 藤田拓海復元.csv"
    RIMES_CSV = File.join("to_tshet_uinh_data", "small_rimes.csv")
    QIEYUN_PREFIX = "urn:nabu:dict:qieyun:"
    GUANGYUN_PREFIX = "urn:nabu:dict:guangyun:"

    Result = Data.define(:scope, :run_id, :edges_written, :edges_refreshed,
                         :superseded_runs, :superseded_edges, :skipped_unmapped)

    def initialize(catalog:, journal:)
      @catalog = catalog
      @journal = journal
    end

    # Re-derive every small-rime edge from the canonical tables,
    # superseding the prior (producer, scope) run. A workdir without
    # either table is the honest no-op (pre-first-sync).
    def run(slug, workdir: nil)
      main = workdir && File.join(workdir, MAIN_CSV)
      rimes = workdir && File.join(workdir, RIMES_CSV)
      return absent_result(slug) unless main && File.file?(main) && File.file?(rimes)

      counts = Hash.new(0)
      main_rows = CSV.read(main, headers: true)
      edges = rime_edges(rimes, entry_ids_by_ordinal(main_rows), head_entry_ids(main_rows), counts)
      run_id = superseded = nil
      @journal.transaction do
        superseded = Store::LinksJournal.supersede!(@journal, producer: PRODUCER, scope: slug)
        run_id = Store::LinksJournal.record_run!(@journal, producer: PRODUCER, scope: slug,
                                                           params: { kind: KIND }, code_version: CODE_VERSION)
        write_edges(edges, run_id, counts)
      end
      Result.new(scope: slug, run_id: run_id,
                 edges_written: counts[:inserted], edges_refreshed: counts[:refreshed],
                 superseded_runs: superseded[0], superseded_edges: superseded[1],
                 skipped_unmapped: counts[:unmapped])
    end

    private

    def absent_result(slug)
      Result.new(scope: slug, run_id: nil, edges_written: 0, edges_refreshed: 0,
                 superseded_runs: 0, superseded_edges: 0, skipped_unmapped: 0)
    end

    # 序数 → the shelf's entry id (頁.行) — the resolution 藤田條目號
    # keys into.
    def entry_ids_by_ordinal(rows)
      rows.to_h { |row| [row["序数"].to_s, "#{row['頁']}.#{row['行']}"] }
    end

    # The second lane: (音韻地位描述, 字頭) of each small rime's HEAD
    # row (min 序数 per (聲調, 韻目, 小韻) group). Ambiguous keys drop —
    # a fallback that could point two ways points nowhere.
    def head_entry_ids(rows)
      index = {}
      rows.group_by { |r| [r["聲調"], r["韻目"], r["小韻"]] }.each_value do |group|
        head = group.min_by { |r| r["序数"].to_i }
        key = [head["音韻地位描述"], head["字頭"]]
        index[key] = index.key?(key) ? :ambiguous : "#{head['頁']}.#{head['行']}"
      end
      index
    end

    def rime_edges(path, ordinals, heads, counts)
      CSV.foreach(path, headers: true).filter_map do |row|
        entry_id = ordinals[row["藤田條目號"].to_s] ||
                   resolve_head(heads, row["音韻地位"], row["代表字"])
        guangyun = row["對應廣韻小韻號"].to_s.strip
        if entry_id.nil? || guangyun.empty?
          counts[:unmapped] += 1
          next
        end

        { from: "#{QIEYUN_PREFIX}#{entry_id}", to: "#{GUANGYUN_PREFIX}#{guangyun}.1",
          detail: detail_for(row, guangyun) }
      end
    end

    def resolve_head(heads, position, representative)
      value = heads[[position, representative]]
      value == :ambiguous ? nil : value
    end

    # The rime's own line: number, representative, 音韻地位, the join,
    # and the two restorations' disagreement note when upstream carries
    # one.
    def detail_for(row, guangyun)
      parts = ["Qieyun 小韻 #{row['小韻號']} #{row['代表字']} #{row['音韻地位']} " \
               "= Guangyun 小韻 #{guangyun}"]
      note = row["兩家差異注釋"].to_s.strip
      parts << "兩家差異: #{note}" unless note.empty?
      parts.join(" · ")
    end

    def write_edges(edges, run_id, counts)
      edges.each do |edge|
        outcome = Store::LinksJournal.write_edge!(
          @journal, from_urn: edge[:from], to_urn: edge[:to],
                    kind: KIND, score: nil, run_id: run_id, detail: edge[:detail]
        )
        counts[outcome == :inserted ? :inserted : :refreshed] += 1
      end
    end
  end
end
