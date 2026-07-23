# frozen_string_literal: true

# P42-0: the source_stats DERIVED table — the write-time census behind
# `nabu status` / `nabu list` / the axis and language cards. Measured
# 2026-07-23 at 62.8M passages: every one of those read surfaces ran full
# GROUP BY / count(*) aggregates over the passages join PER INVOCATION
# (status 142–247s, list 222s, cards >130s) for numbers that change only at
# load/rebuild time. The doctrine (architecture, derived data): anything
# O(corpus) runs at write time; read time is for probes.
#
# == Shape: one parent row per source + a language child table
#
# - source_stats: the per-source scalars (live/withdrawn/retired document
#   counts, live passage count) plus the license-override mix as a tiny
#   {class => live doc count} JSON object. Overrides — not effective
#   classes — are stored on purpose: sources.license_class can be relabeled
#   by any sync without touching documents, so storing effective classes
#   would go stale; readers compose the effective mix at read time
#   (override classes + the source class when any live doc has no
#   override). The JSON is tiny (overrides are rare) and read whole-row.
# - source_stats_languages: (source_id, language) → live document count
#   (documents.language) and live passage count (passages.language, both
#   sides of the withdrawn rule). A child TABLE, not JSON, because the
#   language card sums one code ACROSS sources and the census wants
#   per-source language lists — natural relational reads. NULL languages
#   are carried only in the parent totals, never as child rows.
#
# There is NO stored global roll-up row: the global census is SUM over the
# per-source rows (O(#sources), milliseconds) — a stored global would be a
# second maintained fact that could drift from its own parts.
#
# == Lifecycle
#
# Loader-maintained incrementally (same transaction as each document write;
# Store::SourceStats), re-derived WHOLESALE by `nabu rebuild` (the
# rebuildability invariant), and health-checked by `nabu health` (D42-a: a
# write path that bypasses the loader is a bug the drift probe catches).
# `updated_at` + `note` say which path last touched a row.
#
# == The inline backfill
#
# Readers feature-detect this table and switch to it as soon as it exists,
# so an EMPTY table on a populated live catalog would read as zero holdings.
# The backfill therefore runs here, inside the migration — deliberately
# DUPLICATING Store::SourceStats.derive! in frozen form (the 001 rule:
# migrations never depend on application code; the app-side derive evolves,
# this snapshot stays; any divergence is healed by the next rebuild).
# Expect a pause of a few minutes on a 60M-passage catalog: this is the one
# full aggregation pass every future status/list/card read stops paying.
Sequel.migration do
  up do
    create_table(:source_stats) do
      primary_key :id
      foreign_key :source_id, :sources, null: false, unique: true
      Integer :live_documents, null: false, default: 0
      Integer :live_passages, null: false, default: 0
      Integer :withdrawn_documents, null: false, default: 0
      Integer :retired_documents, null: false, default: 0
      String :license_overrides_json, null: false, default: "{}"
      DateTime :updated_at, null: false
      String :note, null: false
    end

    create_table(:source_stats_languages) do
      primary_key :id
      foreign_key :source_id, :sources, null: false
      String :language, null: false
      Integer :documents, null: false, default: 0
      Integer :passages, null: false, default: 0

      index %i[source_id language], unique: true
      index :language
    end

    # -- backfill (frozen duplicate of Store::SourceStats.derive!) ----------
    stats = Hash.new do |hash, source_id|
      hash[source_id] = { live: 0, withdrawn: 0, retired: 0, passages: 0,
                          langs: Hash.new { |h, k| h[k] = { documents: 0, passages: 0 } },
                          overrides: Hash.new(0) }
    end
    from(:documents)
      .group(:source_id, :language, :withdrawn, :retired_upstream, :license_override)
      .select(:source_id, :language, :withdrawn, :retired_upstream, :license_override,
              Sequel.function(:count).*.as(:n))
      .each do |row|
        source = stats[row[:source_id]]
        if row[:withdrawn]
          source[:withdrawn] += row[:n]
        else
          source[:live] += row[:n]
          source[:retired] += row[:n] if row[:retired_upstream]
          source[:langs][row[:language]][:documents] += row[:n] if row[:language]
          source[:overrides][row[:license_override]] += row[:n] if row[:license_override]
        end
      end
    from(:passages)
      .join(:documents, id: Sequel[:passages][:document_id])
      .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
      .group(Sequel[:documents][:source_id], Sequel[:passages][:language])
      .select(Sequel[:documents][:source_id].as(:source_id), Sequel[:passages][:language].as(:language),
              Sequel.function(:count).*.as(:n))
      .each do |row|
        source = stats[row[:source_id]]
        source[:passages] += row[:n]
        source[:langs][row[:language]][:passages] += row[:n] if row[:language]
      end
    now = Time.now
    stats.each do |source_id, source|
      from(:source_stats).insert(
        source_id: source_id, live_documents: source[:live], live_passages: source[:passages],
        withdrawn_documents: source[:withdrawn], retired_documents: source[:retired],
        # License classes are bare enum words (001/018) — safe to quote by hand,
        # keeping the migration free of any require.
        license_overrides_json: "{#{source[:overrides].sort.map { |k, v| "\"#{k}\":#{v}" }.join(',')}}",
        updated_at: now, note: "migration 019 backfill"
      )
      source[:langs].sort.each do |language, counts|
        from(:source_stats_languages).insert(
          source_id: source_id, language: language,
          documents: counts[:documents], passages: counts[:passages]
        )
      end
    end
  end

  down do
    drop_table(:source_stats_languages)
    drop_table(:source_stats)
  end
end
