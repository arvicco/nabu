# frozen_string_literal: true

module Nabu
  module Store
    # The maintenance rail (the incrementality review, R4): the ONE owner
    # of corpus-scale index work, run by `nabu index maintain`.
    #
    # == Why a rail
    #
    # The proportionality law (architecture §1) keeps online sync/refresh
    # stages O(Δ). The work that law pushes off the write path does not
    # vanish — it is owed: aggregates the delta grain could not move
    # exactly (Store::StaleAggregates), fts5 merge debt the sync path only
    # probes, a WAL a pinned reader kept from truncating. Paid inline, that
    # work was the measured multi-hour class (merge debt repaid inside
    # whichever statement tripped it; corpus re-censuses behind one-slice
    # heals). So it is SCHEDULED instead: owner- or cron-fired between
    # phases (the cost law's §1 pattern), announced stage by stage with the
    # ledger's estimate, ledgered under its own kind ("maintain"),
    # supervised by the index watcher with a kill armed from that ledger
    # (the CLI), and resumable by construction:
    #
    #   - each stale flag is cleared by the recompute that settles it, in
    #     the same transaction where the recompute allows — a killed run
    #     leaves exactly the unfinished flags, and a flag a sibling
    #     recompute already settled (the corpus census re-closes the
    #     closure too) is re-checked and skipped;
    #   - merge consolidation persists in the index itself: every chunk is
    #     its own committed statement, so a second run continues from the
    #     structure the first left, never from scratch.
    #
    # Order: recomputes first (they write — any merge work they cause is
    # then consolidated in the same run), consolidation per fts table to the
    # no-op probe, then the WAL TRUNCATE, with the structure gauges read
    # before and after for the report.
    module IndexMaintenance
      KIND = "maintain"

      # Every fts5 table the rail consolidates, wherever it lives (the
      # lanes resolve through their ATTACHed files).
      TABLES = [Indexer::TABLE, Indexer::CJK_TABLE, Indexer::TRIGRAM_TABLE].freeze

      # The debt line the sync path reports past (debt_line): a level
      # holding this many segments is one fts5's positive merge has work
      # on — usermerge's default, the engine's own line.
      DEBT_LEVEL_SEGMENTS = 4

      Report = Data.define(:recomputed, :merge_chunks, :gauges_before, :gauges_after, :checkpoint)

      module_function

      def run!(catalog:, fulltext:, ledger: nil, progress: nil)
        before = gauges(fulltext)
        flags = StaleAggregates.all(fulltext)
        flags.each { |flag| recompute_for(flag) } # an unknown flag refuses before any work
        recomputed = flags.filter_map do |flag|
          next unless StaleAggregates.stale?(fulltext, aggregate: flag[:aggregate], scope: flag[:scope])

          recompute!(catalog: catalog, fulltext: fulltext, flag: flag, ledger: ledger, progress: progress)
        end
        chunks = TABLES.select { |table| fulltext.table_exists?(table) }.sum do |table|
          timed(ledger, table.to_s, "fts_merge", "maintain: merge consolidation — #{table}", progress) do
            Indexer.consolidate_merges!(fulltext, table, progress: progress)
          end
        end
        checkpoint = Indexer.checkpoint_wal!(fulltext, progress: progress)
        Report.new(recomputed: recomputed, merge_chunks: chunks, gauges_before: before,
                   gauges_after: gauges(fulltext), checkpoint: checkpoint)
      end

      # The recompute for one flag (announced, ledgered); returns its label.
      def recompute!(catalog:, fulltext:, flag:, ledger:, progress:)
        label = "#{flag[:aggregate]} (#{flag[:scope]})"
        timed(ledger, flag[:scope], "recompute_#{flag[:aggregate]}",
              "maintain: recompute #{label} — stale since #{flag[:marked_at]} (#{flag[:reason]})", progress) do
          recompute_for(flag).call(catalog, fulltext, flag[:scope])
        end
        label
      end

      # The settling recompute per aggregate. A name with no recompute
      # refuses loudly — a guessed recompute would clear a flag it never
      # settled.
      def recompute_for(flag)
        case flag[:aggregate]
        when Indexer::POSTINGS_AGGREGATE
          lambda { |catalog, fulltext, slug|
            Indexer.recompute_char_postings!(catalog: catalog, fulltext: fulltext, slug: slug)
          }
        when ReflexRootsIndexer::CLOSURE_AGGREGATE
          ->(catalog, fulltext, _) { ReflexRootsIndexer.rebuild_closure!(catalog: catalog, fulltext: fulltext) }
        when Indexer::CENSUS_AGGREGATE
          ->(catalog, fulltext, _) { recompute_census!(catalog, fulltext) }
        else
          raise Nabu::Error, "index maintain: no recompute for stale aggregate #{flag[:aggregate].inspect} " \
                             "(scope #{flag[:scope]}) — a full rebuild settles every aggregate"
        end
      end

      # The corpus lemma census: the frequency table re-derived wholesale,
      # then the reflex corpus pass (stats from the lemma table + the
      # closure walk — it settles a closure flag too), the flag cleared
      # last.
      def recompute_census!(catalog, fulltext)
        LemmaFrequencies.rebuild!(fulltext)
        ReflexRootsIndexer.rebuild!(catalog: catalog, fulltext: fulltext)
        StaleAggregates.clear!(fulltext, aggregate: Indexer::CENSUS_AGGREGATE, scope: "corpus")
      end

      # { table => FtsStructure gauges } for every present fts table.
      def gauges(fulltext)
        TABLES.filter_map do |table|
          found = FtsStructure.gauges(fulltext, table)
          [table, found] if found
        end.to_h
      end

      # The sync path's report (Indexer.consolidate_deferred_merges!): the
      # first level still holding positive-merge work after the probe, as
      # one line naming the rail — nil when there is none.
      def debt_line(fulltext, table)
        structure = FtsStructure.read(fulltext, table)
        return nil if structure.nil?

        level = structure.levels.index { |entry| entry[:segments].size >= DEBT_LEVEL_SEGMENTS }
        return nil if level.nil?

        "merge debt on #{table}: level #{level} holds #{structure.levels[level][:segments].size} segments " \
          "(#{structure.total_segments} total) past the sync path's one probe chunk — run nabu index maintain"
      end

      # Announce with the ledger's estimate, run, record (kind "maintain").
      def timed(ledger, scope, stage, label, progress)
        eta = ledger && Nabu::Eta.for(ledger, kind: KIND, scope: scope, stage: stage)
        progress&.stage(label, eta: eta)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        if ledger
          StageTimings.record!(ledger, kind: KIND, scope: scope, stage: stage,
                                       seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        end
        result
      end
    end
  end
end
