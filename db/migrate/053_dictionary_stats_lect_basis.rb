# frozen_string_literal: true

# The dictionary shelf grain of lect staging (Nabu::LectShelfDates): a
# dictionary source whose shelves carry their work's own year (LEME's
# lexicon_year) stages each covered shelf by date band — so the census row
# now says WHY its lect is what it is, the document grain's journal stamp
# at shelf grain:
#
# - lect_basis: "rule:date-band" when the shelf's year staged it; NULL =
#   the plain resolution ladder (per-source override > codemap > identity).
# - lect_note: the evidence ("dated 1604..1604 (lexicon_year)") — and, for
#   a rule-covered shelf that stays bare, the declared reason ("bare:
#   undated", "bare: spans bands — dated 1700..1700 (lexicon_year)").
#
# Derived like the rest of the table: drop-and-reproject at rebuild, per
# source after a dictionary-bearing sync; no backfill.
Sequel.migration do
  change do
    alter_table(:dictionary_stats) do
      add_column :lect_basis, String
      add_column :lect_note, String
    end
  end
end
