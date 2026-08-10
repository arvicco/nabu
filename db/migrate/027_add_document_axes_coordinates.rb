# frozen_string_literal: true

# P69-1 (places survey P-g): the COORDINATES lane on the axes — a WGS84
# find-location pair per document where the source itself asserts one
# (rundata's SRDB latitude/longitude columns, 6,637 live docs at ruling).
# A coordinates feature, not a matching feature: no gazetteer, no
# resolution — the pair rides verbatim beside place_name/place_ref, and
# the future LPF export (the nabu-data arc) reads it from here.
Sequel.migration do
  change do
    alter_table(:document_axes) do
      add_column :place_lat, Float
      add_column :place_lon, Float
    end
  end
end
