# frozen_string_literal: true

# Nabu::Store::Indexer — the passages_fts write-path classifier (append / rewrite / shadow).
# A partial of lib/nabu/store/indexer.rb, which loads it.
require_relative "../../duration_format"

module Nabu
  module Store
    module Indexer
      module_function

      # -- the write-path classifier (REWRITE_CEILING note) -------------------

      # One run's passages_fts write decision: +path+ is :append (nothing
      # the index holds is deleted — a linear tail append), :rewrite (delete
      # + append in place), :shadow (the append-only full-table shadow) or
      # :fallback (the shadow was due but the sidecar cannot name the old
      # table's membership — written in place, announced, the pre-classifier
      # contract). +written+/+deleted+ are the run's fts rows in each
      # direction; +forecast+ the ledger-priced comparison (FtsPathForecast)
      # when the mid band asked for one, else nil.
      FtsWritePath = Data.define(:path, :written, :deleted, :forecast)

      # Seconds, or nil when the ledger holds no rated row for the stage.
      FtsPathForecast = Data.define(:rewrite, :shadow) do
        def flips? = !rewrite.nil? && !shadow.nil? && rewrite > shadow
      end

      # The decision itself, over counts already taken (fts_write_counts).
      # +member_ids+ are the refreshed sources (one, or a wave's), whose
      # complement shadow_ready? must be able to name.
      def fts_write_path(catalog, fulltext, member_ids:, written:, deleted:, ceiling:, ledger: nil)
        decide = ->(path, forecast = nil) { FtsWritePath.new(path:, written:, deleted:, forecast:) }
        # A legacy contentful file has no sidecar and no shadow: in place, always.
        return decide.call(:rewrite) unless fts_contentless?(fulltext)
        return decide.call(:append) if deleted.zero?

        ready = -> { shadow_ready?(catalog, fulltext, member_ids) }
        if deleted <= ceiling
          forecast = fts_path_forecast(fulltext, ledger, written: written, deleted: deleted)
          return decide.call(forecast.flips? && ready.call ? :shadow : :rewrite, forecast)
        end
        decide.call(ready.call ? :shadow : :fallback)
      end

      # The mid band's ledger-priced comparison: the rewrite at the latest
      # rated fts_rewrite row's seconds-per-row over the rows it touches
      # (deleted + written), against the shadow at the latest rated
      # fts_shadow row's over the rows the shadow would hold. That size is
      # read in O(1) — the index's own row total (the fts5 averages record)
      # less the rows this run deletes plus the rows it writes — never a
      # corpus count on a small delta's path.
      def fts_path_forecast(fulltext, ledger, written:, deleted:)
        rewrite_rate = StageTimings.rate(ledger, kind: "sync", stage: "fts_rewrite")
        shadow_rate = StageTimings.rate(ledger, kind: "sync", stage: "fts_shadow")
        total = (FtsStructure.total_rows(fulltext, TABLE) if shadow_rate)
        shadow_rows = ([total - deleted, 0].max + written if total)
        FtsPathForecast.new(rewrite: rewrite_rate && (rewrite_rate * (deleted + written)),
                            shadow: shadow_rows && (shadow_rate * shadow_rows))
      end

      # [written, deleted] for one source's run. +plan+ nil (the forecast's
      # whole-slice view) or a whole-slice plan counts by query; the delta
      # and heal grains count their own key sets. Written is the run's live
      # insert scope; deleted comes from the sidecar's membership
      # (fts_deleted_rows).
      def fts_write_counts(catalog, fulltext, source_id, plan: nil, delta: nil)
        whole = plan.nil? || (!plan.use_delta && plan.heal.nil?)
        written =
          if whole then live_passages(catalog).where(Sequel[:documents][:source_id] => source_id).count
          elsif plan.use_delta then delta.upserted_ids.size
          else plan.heal.upserted_ids.size
          end
        deleted = fts_deleted_rows(catalog, fulltext, source_id, ids: (plan.ids unless whole),
                                                                 healing: plan&.healing || false)
        [written, deleted]
      end

      # How many of the run's doomed rowids the index actually holds — read
      # from the row-sha sidecar, whose membership IS the index's outside a
      # crash (ROW_SHAS_TABLE invariant: never ahead of it). +ids+ nil is
      # the whole slice (the source's every sidecar row). Conservative —
      # every doomed id counts — wherever the sidecar cannot vouch: no
      # sidecar or the legacy shape; the source's own slice predating the
      # sidecar (fts_membership_recorded?); and a heal's whole-slice
      # rewrite. A heal's exact diff (the one case the sidecar may sit
      # BEHIND the index: a bulk run killed between a batch's fts insert
      # and its sidecar upsert) also probes its unrecorded ids against the
      # index itself, so a crashed append's landed tail counts as deleted
      # and the heal deletes it before re-appending.
      def fts_deleted_rows(catalog, fulltext, source_id, ids:, healing: false)
        unknown = -> { ids ? ids.size : source_passage_count(catalog, source_id) }
        return unknown.call unless fts_contentless?(fulltext) && fulltext.table_exists?(ROW_SHAS_TABLE)
        return unknown.call if ids.nil? && healing
        return unknown.call unless fts_membership_recorded?(catalog, fulltext, source_id)
        return fulltext[ROW_SHAS_TABLE].where(source_id: source_id).count if ids.nil?

        ids.to_a.each_slice(BATCH_SIZE).sum do |batch|
          recorded = fulltext[ROW_SHAS_TABLE].where(rowid: batch).select_map(:rowid)
          unrecorded = healing ? batch - recorded : []
          landed = unrecorded.empty? ? 0 : fulltext[TABLE].where(rowid: unrecorded).select_map(Sequel.lit("rowid")).size
          recorded.size + landed
        end
      end

      # Whether the sidecar names +source_id+'s indexed membership: it has
      # sidecar rows, or no indexed rows at all (its first and last live
      # passages probed in the index — a slice that predates the sidecar
      # was written whole, so both would be there). Two point lookups.
      def fts_membership_recorded?(catalog, fulltext, source_id)
        return true unless fulltext[ROW_SHAS_TABLE].where(source_id: source_id).empty?

        scope = live_passages(catalog).where(Sequel[:documents][:source_id] => source_id)
        probes = [scope.min(Sequel[:passages][:id]), scope.max(Sequel[:passages][:id])].compact
        probes.empty? || fulltext[TABLE].where(rowid: probes).empty?
      end

      # Every passage of the source, withdrawn included (the slice key
      # set's size, counted rather than loaded).
      def source_passage_count(catalog, source_id)
        catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                          .where(Sequel[:documents][:source_id] => source_id).count
      end

      # The one-line decision log, at choice time (the design's
      # instrumentation): path, rows written, rows deleted, forecast.
      # A :fallback says why the shadow it was due could not run.
      def fts_path_line(scope, decision)
        line = "fts write path: #{scope} — #{decision.path} (#{Eta.commas(decision.written)} written, " \
               "#{Eta.commas(decision.deleted)} deleted; forecast #{fts_forecast_words(decision.forecast)})"
        return line unless decision.path == :fallback

        "#{line} — past the rewrite ceiling, but the row-sha sidecar incomplete (a slice predating it): " \
          "writing in place under the governor until a full rebuild backfills it"
      end

      def fts_forecast_words(forecast)
        return "n/a" if forecast.nil?

        price = ->(seconds) { seconds ? "~#{FORECAST_VOICE.format_duration(seconds)}" : "unpriced" }
        "rewrite #{price.call(forecast.rewrite)} vs shadow #{price.call(forecast.shadow)}"
      end
      FORECAST_VOICE = Object.new.extend(DurationFormat)

      # The eager consolidation after an in-place write (append or
      # rewrite): the merge governor's own relief — bounded MERGE_CHUNK_PAGES
      # positive ('merge', N) chunks, its no-op stall detection, its ticks
      # and checkpoints — run once against the fresh structure until every
      # level is back at or under the governor's limit. Outside the write's
      # transaction and after the deferral's defaults are restored (the
      # merge probe's crash-safe order); automerge/crisismerge untouched.
      # Returns the chunks run (0 on a calm structure — one record read).
      # +ledger+ records the relief (FtsGovernor's fts_relief note).
      def eager_consolidate!(fulltext, progress: nil, level_limit: GOVERNOR_LEVEL_LIMIT, ledger: nil)
        return 0 unless governed_fts_tables(fulltext).include?(TABLE)

        FtsGovernor.new(fulltext: fulltext, table: TABLE, progress: progress, level_limit: level_limit,
                        ledger: ledger).check!
      end
    end
  end
end
