# frozen_string_literal: true

# P18-4: the ACCUMULATED per-language knowledge layer — curated context
# (period, family, historical notes, relevance-to-library prose) and any
# future per-language accretion (survey findings, owner notes, references).
# NOT a function of canonical/, so it cannot live in the drop-and-rebuild
# catalog; it lives in the ledger because (a) authored curation is the most
# precious data temperature — the ledger is the never-dropped, always-backed-
# up file; (b) the Phase-8 enrichment plan (architecture §5) already assigns
# replayable non-derived accretions to the ledger; (c) the source_probes
# precedent shows the ledger hosts rebuild-surviving state beyond run
# history; and (d) append-only FITS this data — an update APPENDS a
# superseding note and the read side takes the latest per (lang_code, kind),
# so provenance history is free (unlike batch links, whose wholesale
# replacement forced its own journal file).
#
# kind is an open vocabulary; the shipped kinds are "name" (curated name,
# beats the derived census), "family" (the family line), and "context" (the
# one-to-three-line card prose). Family-level entries for the etymology tail
# ride the family PREFIX as their lang_code ("zle" for zle-*), which is
# Wiktionary's own family-code namespace. `source` records who wrote the
# note ("seed:config/languages.yml", a future "owner:--note", an agent id);
# rows are never updated or deleted.
Sequel.migration do
  change do
    create_table(:language_notes) do
      primary_key :id
      String :lang_code, null: false
      String :kind, null: false
      String :body, text: true, null: false
      String :source, null: false
      DateTime :created_at, null: false

      index %i[lang_code kind]
    end
  end
end
