# frozen_string_literal: true

# P105-1 (Q86): the parent administrative unit reaches the derived place
# index — the CHGIS discriminator the review board needs to tell homonym
# candidates apart (two 清水 rows separate instantly once one says
# "under 秦州" and the other "under 汀州"). A DISPLAY string verbatim
# from the gazetteer ("顺天府 (Shuntian Fu)"), not a graph edge: the
# dump's part_of table stays deliberately unread (chgis module note).
# Nullable; only slices whose rows carry a parent populate it
# (rebuild-safe: the derive is wholesale per gazetteer).
Sequel.migration do
  change do
    alter_table(:place_index) do
      add_column :parent, String
    end
  end
end
