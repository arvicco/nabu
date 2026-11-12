# frozen_string_literal: true

require "json"
require "time"

module Nabu
  module Store
    # The engine-config INTENT JOURNAL (the incrementality review, R6's
    # partner piece). fts5 merge settings are PERSISTED index config: the
    # bulk write mode sets deletemerge=0 for its pass and ensure-restores
    # the default — but a SIGKILL (a watchdog's kill, an OOM, the owner's
    # kill -9 on a wedged statement) runs no ensure, and a killed run has
    # twice left deletemerge=0 behind on this box, an index silently never
    # compacting its tombstones.
    #
    # So every bulk application is journaled FIRST: one row naming the fts
    # table, the settings that restore it, and the writer's pid, committed
    # before the bulk setting itself is applied. The ensure arm restores
    # and clears the row as before; when it never ran, the row survives,
    # and the next read-write connect_fulltext replays it — applies the
    # restore, deletes the row — provided the journaled writer is gone
    # (Nabu::ProcessProbe). A writer still running keeps its bulk window:
    # replaying under it would only re-arm the merges it deferred. Read-only
    # connects never replay (they cannot write); the index watcher's
    # post-kill hygiene opens a read-write connect precisely to trigger it.
    #
    # The journal lives in the fulltext file itself (engine_intents): the
    # settings it restores are that file's, so the two share every crash
    # and every rebuild — a full rebuild drops both together. Derived
    # bookkeeping, never a migration (the Indexer's stance).
    module EngineIntents
      TABLE = :engine_intents

      module_function

      # Journal one table's restore BEFORE its bulk settings apply; returns
      # the row id for #clear!.
      def journal!(db, table:, restore:, pid: Process.pid)
        create_table(db)
        db[TABLE].insert(fts_table: table.to_s, restore_json: JSON.generate(restore), pid: pid,
                         journaled_at: Time.now.utc.iso8601)
      end

      # The ensure arm's half: the restore ran, the intents are spent.
      def clear!(db, ids)
        ids = Array(ids).compact
        return if ids.empty? || !db.table_exists?(TABLE)

        db[TABLE].where(id: ids).delete
      end

      # Replay every intent whose writer is gone: apply its restore (when
      # its table still exists — a dropped table needs none) and delete
      # the row. Returns the replayed rows.
      def replay!(db)
        return [] unless db.table_exists?(TABLE)

        db[TABLE].order(:id).all.reject { |row| ProcessProbe.alive?(row[:pid]) }.each do |row|
          table = row[:fts_table].to_sym
          if db.table_exists?(table)
            JSON.parse(row[:restore_json]).each { |key, value| db[table].insert(table => key, :rank => value) }
          end
          db[TABLE].where(id: row[:id]).delete
        end
      end

      def create_table(db)
        db.create_table?(TABLE) do
          primary_key :id
          String :fts_table, null: false
          String :restore_json, null: false
          Integer :pid
          String :journaled_at, null: false
        end
      end
    end
  end
end
