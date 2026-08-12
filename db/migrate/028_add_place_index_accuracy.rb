# frozen_string_literal: true

# P76 U-4 (№R-6, the uncertainty doctrine's one place-index storage
# change): the CIGS accuracy grade finally reaches disk. CONFIRMED
# semantics (full-CSV census 2026-08-12, correcting the survey's
# [claimed] guess): a 0–3 COORDINATE-accuracy scale, higher = more
# accurate — 3 site-exact, 2/1 approximate, 0 unlocated (those rows
# carry no coordinates at all). It grades the point, not the
# identification: a precision fact under "precision is not certainty",
# so it maps to NO house tier and renders verbatim on the place card.
# Nullable; only the cigs slice populates it (rebuild-safe: the derive
# is wholesale per gazetteer).
Sequel.migration do
  change do
    alter_table(:place_index) do
      add_column :accuracy, Integer
    end
  end
end
