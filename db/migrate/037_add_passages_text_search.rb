# frozen_string_literal: true

# P112-2 (Q113): the search-form read seam. text_normalized measured
# byte-identical to text on the vast majority of rows (ø191.8 B vs
# 191.6 B — the CJK-majority corpus folds to itself), so the loader now
# stores the EMPTY STRING when the two are equal (~12–18 GB reclaimed at
# the next rebuild). Every catalog reader of the search form goes through
# this VIRTUAL generated column: computed on read, stored never — the
# ALTER is instant on any catalog size. Readers select it aliased AS
# text_normalized, so row consumers downstream are untouched.
#
# Why "" and not NULL: passages.text_normalized is NOT NULL in the base
# schema, and SQLite cannot drop that constraint without rewriting the
# 99.8 GB table — the empty string costs the same zero bytes. The one
# documented edge: a passage whose TRUE search form is empty while its
# text is not (an all-combining-marks fragment folds to "") now serves
# its raw text as the search form — strictly MORE discoverable than the
# empty form, never less.
Sequel.migration do
  change do
    alter_table(:passages) do
      add_column :text_search, String,
                 generated_always_as: Sequel.function(
                   :coalesce, Sequel.function(:nullif, :text_normalized, ""), :text
                 ),
                 generated_type: :virtual
    end
  end
end
