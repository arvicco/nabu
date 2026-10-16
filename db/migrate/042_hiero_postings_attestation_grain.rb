# frozen_string_literal: true

# The finer AED attestation grain on the precompiled per-glyph census:
# the per-text stand-off files segment every hieroglyph run into word
# tokens (<w corresp="src:tla…">) and mark damaged readings with
# <unclear>. +words+ counts the word tokens attesting the glyph (at
# most +signs+); +unclear+ counts its occurrences read inside
# <unclear> (a subset of +signs+). Additive with zero defaults; the
# table is drop-and-reproject derived data (Store::HieroPostingsBuilder),
# so the next rebuild or aed sync fills both columns.
Sequel.migration do
  change do
    alter_table(:hiero_postings) do
      add_column :words, Integer, null: false, default: 0
      add_column :unclear, Integer, null: false, default: 0
    end
  end
end
