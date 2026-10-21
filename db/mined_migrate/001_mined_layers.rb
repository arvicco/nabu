# frozen_string_literal: true

# The mined-layers store's own table (local/mined-links.sqlite3,
# Nabu::Store::MinedLinks; architecture §15, the cost law).
#
# The store's EDGE shape is the links journal's, by construction: the
# gateway applies db/links_migrate first, so links / link_runs /
# link_run_chunks are byte-for-byte the journal's tables and every
# LinksJournal verb (supersede!, record_run!, the chunked-run cursor,
# write_edge!) works unchanged against it. This track adds only what the
# journal has no use for — one provenance row per mined LAYER — and
# records its versions in its own counter table (mined_schema_info), so
# the two tracks never collide inside the one file.
#
#   mined_layers  one row per heavy layer (producer + the recorded
#                 link_scopes.yml scope string): the runs that hold its
#                 edges, its edge count, when it was mined (the runs'
#                 finish time — what every reader shows beside an edge),
#                 the producer's engine marker, and the identity of its
#                 inputs at mine time: +stamp+/+inputs_json+ (the
#                 Nabu::LinkStamps preimage — code digest, resolved
#                 params, member content identities, index identity) and
#                 +catalog_json+ (the member sources'
#                 sources.last_ingest_identity — the CHEAP identity health
#                 compares to call a layer stale). +origin+ is "mine" or
#                 "migrated" (moved out of db/links.sqlite3 with its stamp).
Sequel.migration do
  change do
    create_table(:mined_layers) do
      String :producer, null: false
      String :scope, null: false
      String :run_scope, null: false
      String :run_ids_json, null: false
      Integer :edges, null: false
      String :code_version
      String :stamp
      String :inputs_json
      String :catalog_json
      String :origin, null: false
      Float :seconds
      DateTime :mined_at, null: false
      DateTime :recorded_at, null: false

      primary_key %i[producer scope]
    end
  end
end
