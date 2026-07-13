# frozen_string_literal: true

# Per-edge evidence for the P16-2 producers (formulas, cognates). A parallel
# edge's meaning is fully carried by (pair, score, run params); a formula or
# cognate edge asserts a MEET — the shared refrain, or the reconstruction root
# two witnesses descend from — and that meet differs per edge, so it cannot
# ride params_json (run grain: one row for thousands of edges) and score is a
# float. `detail` is a nullable display-grade string:
#
#   formula:  the folded gram itself ("saga hwaet ic hatte")
#   cognate:  ref + root + SHELF ("MARK 2.1 · *kaisaraz [gem-pro]") — the
#             shelf is part of the answer (a gem-pro meet for a Slavic
#             witness reads as a borrowing, design §6)
#
# Nullable so existing parallel edges are untouched: this migration applies
# forward to a live journal (LinksJournal.open! migrates on the write path)
# with zero data loss; a journal opened READ-ONLY before its next write
# simply reads nil details.
Sequel.migration do
  change do
    alter_table(:links) do
      add_column :detail, String
    end
  end
end
