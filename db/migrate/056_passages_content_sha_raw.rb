# frozen_string_literal: true

# The passage content hash stored as 32 raw bytes instead of 64 hex
# characters (~107M rows: ~8 GiB of hex text, ~3.3 GiB saved at the next
# from-scratch rebuild).
#
# The stored column is RENAMED to content_sha_raw and a VIRTUAL generated
# column takes over the old name, serving lower-case hex whatever the
# stored form is:
#
#   CASE WHEN typeof(content_sha_raw) = 'blob'
#        THEN lower(hex(content_sha_raw))
#        ELSE content_sha_raw END
#
# so every reader of passages.content_sha256 is untouched by construction,
# and a live file still holding hex-TEXT rows keeps serving them as they
# are: mixed rows are legal (the loader writes blobs for new and revised
# passages; the full rebuild lands the file all-blob). Writers address
# content_sha_raw (Store::ContentHash.stored); a write through the old name
# is refused by the engine — a generated column cannot be assigned.
#
# Both ALTERs are schema-only — RENAME COLUMN rewrites the CREATE TABLE
# text, ADD COLUMN of a VIRTUAL column stores no bytes — so the migration
# is instant at any catalog size, pinned by
# test/store/content_sha_raw_migration_test.rb (page_count, root page and
# every passages page byte-identical across the migration). NOT NULL rides
# the renamed column; no index or view references it.
#
# down: materializes blob rows back to their hex text BEFORE dropping the
# virtual column and restoring the old name — a full-table scan, the price
# of an honest rollback.
Sequel.migration do
  up do
    alter_table(:passages) { rename_column :content_sha256, :content_sha_raw }
    alter_table(:passages) do
      add_column :content_sha256, String,
                 generated_always_as: Sequel.case(
                   [[{ Sequel.function(:typeof, :content_sha_raw) => "blob" },
                     Sequel.function(:lower, Sequel.function(:hex, :content_sha_raw))]],
                   :content_sha_raw
                 ),
                 generated_type: :virtual
    end
  end

  down do
    self[:passages].where(Sequel.function(:typeof, :content_sha_raw) => "blob")
                   .update(content_sha_raw: Sequel.function(:lower, Sequel.function(:hex, :content_sha_raw)))
    alter_table(:passages) { drop_column :content_sha256 }
    alter_table(:passages) { rename_column :content_sha_raw, :content_sha256 }
  end
end
