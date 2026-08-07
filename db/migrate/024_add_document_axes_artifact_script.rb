# frozen_string_literal: true

# The artifact-script field (P61-3, owner ruling D60-b: "where the artifact
# script differs from the source document it should be marked as a separate
# field"). The ~script lect axis claims the HELD text's writing system —
# byte-checkable; where the original artifact's script DIFFERS (a Demotic
# papyrus held as Latin transliteration, an Old Italic inscription held
# romanized), that fact lands here, never folded into the lect id.
#
# Minted ONLY on difference, by Store::ArtifactScripts.derive! from the
# owner-ruled rows in config/artifact_scripts.yml (source → code → script
# tag from the registry's global table) — a pure function of stored codes +
# config, re-derived wholesale, rebuild-safe. Docs without any axes row get
# one under axis_source "artifact-script" (a lane carrying only this
# column; date/place readers filter on their own columns, so the null lane
# never enters their queries).
Sequel.migration do
  change do
    alter_table(:document_axes) do
      add_column :artifact_script, String
      add_column :artifact_script_note, String
    end
  end
end
