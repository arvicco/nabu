# ACLT — acquiring the Luwian corpus (manual drop)

Where from: a personal research grant — the corpus arrives **by email**
from the ACLT team. The public surface is the search UI at
luwian.web-corpora.net (Tsakorpus); no download URL exists.

The grant's terms, honored by the adapter: personal research use only
(`license_class: research_private` — excluded from every public
surface), per-text credit to the corpus and its editorship as
provenance, the Tsakorpus platform named as the technical channel, no
redistribution.

## The drop, step by step

1. Receive (or request a refresh of) the corpus archive from the ACLT
   team by email — one 7z file of per-inscription Tsakorpus JSON.
2. Save the attachment as downloaded — no re-archiving; the sha pin
   records the bytes as supplied:
   - `luwian_aclt.7z` (required)
3. Place it under `incoming/aclt/` in the library root.
4. Run `bin/nabu sync aclt`. The drop is validated (7z magic bytes),
   moved into `canonical/aclt/`, sha-stamped in `.manual-fetch.json`,
   and its `luwian_aclt/json/` tree extracted beside it (bsdtar; a
   declared materialization). The parse then loads one document per
   inscription — 266 at the 2026-09 delivery, with upstream's one
   tombstone file skipping by rule.

## Refresh

A newer corpus export drops the same way; an identical re-drop is a
sha-verified no-op. The format is the Tsakorpus data model
(tsakorpus.readthedocs.io/en/latest/data_model.html); the tagset is
documented in the corpus site's grammar-selection tables.
