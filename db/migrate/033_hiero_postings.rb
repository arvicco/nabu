# frozen_string_literal: true

# P103-2 (the AED hieroglyph seam): the precompiled per-glyph census
# over canonical/aed's per-text stand-off hieroglyph files — one row
# per hieroglyph codepoint: how many TEXTS attest it and how many
# total SIGN occurrences it has. Written by Store::HieroPostingsBuilder
# (drop-and-reproject, a pure function of canonical/aed — the
# derivability law); read by the HieroCard corpus panel as its third
# counted source, one row per card (the desk-commands law: cards touch
# only precompiled data).
Sequel.migration do
  change do
    create_table(:hiero_postings) do
      String :glyph, null: false
      Integer :texts, null: false
      Integer :signs, null: false
      index :glyph, unique: true
    end
  end
end
