# frozen_string_literal: true

# The language-slice identity of a mined layer (Nabu::MinedLayers):
# +slice_json+ records, at mine time, the text slice the run consumed —
# the scope's language lane (passages.language in the scope's lang
# variants, visible rows only) as one (count, max revision) pair per
# member source that holds any lane passage. Health compares it against
# the live catalog for each member whose ingest identity moved, so a
# touch outside the lane (a reference source, another language) no
# longer calls the layer stale. NULL on layers mined before this column:
# they keep the coarse per-source verdict until their next mine.
Sequel.migration do
  change do
    alter_table(:mined_layers) do
      add_column :slice_json, String
    end
  end
end
