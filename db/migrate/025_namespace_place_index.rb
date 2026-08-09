# frozen_string_literal: true

# P63-3 (ruling Dp-b): the place index goes MULTI-GAZETTEER. Pleiades stops
# being the schema and becomes one namespace among several: rows are keyed
# (gazetteer, place_id) — `pleiades:912855`, `tm:2788`, from P63-5 `cigs:…` —
# and each gazetteer's derive supersedes ONLY its own rows, so the pleiades
# sync and the trismegistos-geo sync own disjoint slices of one table.
#
# Copy-based re-key (not drop-and-recreate): the tables are derived and COULD
# be dropped empty under the 021 no-backfill posture, but the live index
# holds 42k pleiades rows whose re-derive needs an owner-fired dump load —
# a degraded window with no upside when the copy is one INSERT SELECT.
# Existing rows re-key as gazetteer='pleiades' byte-verbatim (zero behavior
# change, test-pinned).
Sequel.migration do
  up do
    create_table(:place_index_v2) do
      String :gazetteer, null: false
      String :place_id, null: false
      String :title
      Float :lat
      Float :lon
      String :place_types_json, null: false, default: "[]"
      String :time_periods_json, null: false, default: "[]"
      Integer :position, null: false

      primary_key %i[gazetteer place_id]
      index :position
    end
    run <<~SQL
      INSERT INTO place_index_v2
        (gazetteer, place_id, title, lat, lon, place_types_json, time_periods_json, position)
      SELECT 'pleiades', pleiades_id, title, lat, lon, place_types_json, time_periods_json, position
      FROM place_index
    SQL
    drop_table(:place_index)
    rename_table(:place_index_v2, :place_index)

    create_table(:place_index_names_v2) do
      String :gazetteer, null: false
      String :place_id, null: false
      String :name_key, null: false

      index %i[gazetteer place_id name_key], unique: true
      index :name_key
    end
    run <<~SQL
      INSERT INTO place_index_names_v2 (gazetteer, place_id, name_key)
      SELECT 'pleiades', pleiades_id, name_key FROM place_index_names
    SQL
    drop_table(:place_index_names)
    rename_table(:place_index_names_v2, :place_index_names)
  end

  down do
    # Forward-only in practice (house rule: never edit applied migrations);
    # the down path restores the 021 single-gazetteer shape, keeping only
    # pleiades rows — non-pleiades derivations are honestly lost.
    create_table(:place_index_v1) do
      String :pleiades_id, primary_key: true
      String :title
      Float :lat
      Float :lon
      String :place_types_json, null: false, default: "[]"
      String :time_periods_json, null: false, default: "[]"
      Integer :position, null: false

      index :position
    end
    run <<~SQL
      INSERT INTO place_index_v1
        (pleiades_id, title, lat, lon, place_types_json, time_periods_json, position)
      SELECT place_id, title, lat, lon, place_types_json, time_periods_json, position
      FROM place_index WHERE gazetteer = 'pleiades'
    SQL
    drop_table(:place_index)
    rename_table(:place_index_v1, :place_index)

    create_table(:place_index_names_v1) do
      String :pleiades_id, null: false
      String :name_key, null: false

      index %i[pleiades_id name_key], unique: true
      index :name_key
    end
    run <<~SQL
      INSERT INTO place_index_names_v1 (pleiades_id, name_key)
      SELECT place_id, name_key FROM place_index_names WHERE gazetteer = 'pleiades'
    SQL
    drop_table(:place_index_names)
    rename_table(:place_index_names_v1, :place_index_names)
  end
end
