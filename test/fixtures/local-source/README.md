# local-source fixtures (P24-0)

Three real source dossiers for the canonical/local-source shelf — the shelf
has NO upstream by definition (`sync_policy: local`), so nothing here was or
can be fetched. The dossier bodies are the owner-facing shelf descriptions
distilled verbatim from docs/library.md's per-shelf sections (§8g Latin
inscriptions, §8c reference shelf, §8i local shelves) — exactly the prose
the owner-fired seed export (`nabu list --export-source-dossiers`) writes —
plus one real accretion section (the edh survey witness).

`broken.md.quarantine` is a synthetic malformed dossier; the loader test
renames it to `.md` to exercise the quarantine path.

Written: 2026-07-16.
