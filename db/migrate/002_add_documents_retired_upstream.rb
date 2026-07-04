# frozen_string_literal: true

# P5-2 retention contract: a document whose canonical file upstream scrapped
# (now preserved under canonical/<slug>/.attic/) is RETIRED, not withdrawn —
# it stays live for search/index/export; `withdrawn` keeps meaning "absent
# from canonical entirely". Forward-only, like every migration here.
Sequel.migration do
  change do
    alter_table(:documents) do
      add_column :retired_upstream, TrueClass, null: false, default: false
    end
  end
end
