# frozen_string_literal: true

# The borrowed flag (P17-3, architecture §12; P15-3 review finding 4):
# kaikki descendant nodes mark loans in raw_tags/tags ("borrowed",
# "learned borrowing" — matched /borrow/i by the parser), and the flag is
# PER EDGE — *hlaibaz's tree flags the proto-to-proto edge to Proto-Slavic
# *xlěbъ, a fact no meet-shelf heuristic can recover. Nullable boolean,
# three honest states:
#
# - true:  the node carried the marker at parse time.
# - false: the node was parsed under the flag-aware parser and carried none.
# - NULL:  the row predates the reparse — "not yet reparsed", never a fake
#   false. The flag joins ContentHash's reflex_fields, so the next
#   owner-fired `sync <shelf> --parse-only` re-mints every reflex-carrying
#   entry's revision and backfills the column (the P16-5 recovery pattern).
#
# NUMBERED 010 with 009 reserved by a parallel phase-17 packet; the
# migrator runs with allow_missing_migration_files until the phase merge
# closes the gap. Do not migrate a live catalog on this branch alone —
# a catalog stamped 010 would never apply a later-landing 009.
Sequel.migration do
  change do
    alter_table(:dictionary_reflexes) do
      add_column :borrowed, TrueClass, null: true
    end
  end
end
