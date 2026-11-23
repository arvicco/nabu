# frozen_string_literal: true

# The text_normalized diet widens the P112 read seam (migration 037)
# by ONE stored class. Besides "" (search form == text), the loader now
# stores the one-byte sentinel char(1) when the search form equals
# SQLite's own lower(text) — ASCII-only downcase, byte for byte — and this
# virtual column recomputes it:
#
#   CASE WHEN text_normalized = ''      THEN text
#        WHEN text_normalized = char(1) THEN lower(text)
#        ELSE text_normalized END
#
# The served form is bit-identical to the old expression for every row
# that existed before (no stored value was char(1)), so readers — all of
# which select text_search — are untouched by construction.
#
# SQLite cannot alter a generated column's expression in place, so the
# column is DROPPED and re-ADDED. Both are schema-only for a VIRTUAL
# column (no stored bytes exist to rewrite): instant at any catalog size,
# pinned by test/store/text_search_migration_test.rb (page_count, root
# page and every passages page byte-identical across the migration).
# Sequel's SQLite drop_column takes the native ALTER path because no index
# covers text_search — an index on it would force a table rebuild here.
#
# down: materializes any sentinel rows back to their lower(text) form
# BEFORE restoring the narrower seam (which would otherwise serve the raw
# sentinel byte) — a full-table scan, the price of an honest rollback.
Sequel.migration do
  up do
    alter_table(:passages) { drop_column :text_search }
    alter_table(:passages) do
      add_column :text_search, String,
                 generated_always_as: Sequel.case(
                   [[{ text_normalized: "" }, :text],
                    [{ text_normalized: Sequel.function(:char, 1) }, Sequel.function(:lower, :text)]],
                   :text_normalized
                 ),
                 generated_type: :virtual
    end
  end

  down do
    self[:passages].where(text_normalized: Sequel.function(:char, 1))
                   .update(text_normalized: Sequel.function(:lower, :text))
    alter_table(:passages) { drop_column :text_search }
    alter_table(:passages) do
      add_column :text_search, String,
                 generated_always_as: Sequel.function(
                   :coalesce, Sequel.function(:nullif, :text_normalized, ""), :text
                 ),
                 generated_type: :virtual
    end
  end
end
