# mahan-kosh fixture

Trimmed REAL excerpt of the Sikhi.io JSON packaging of Bhai Kahan Singh
Nabha's *Gurushabad Ratnakar Mahan Kosh* (1930). Retrieved 2026-11-02
from https://github.com/redroyals/mahan-kosh-multilingual (branch main
at b298c32e, pushed 2026-09-08):

- `data/entries/core.json` — 15,970,316 bytes, 68,150 grid rows (64,218
  live + 3,932 excluded), sha256
  509c846358f193694690bd465fea80f724d02ae58ca9a3529d880cd112bf2a2f
- `data/entries/gurmukhi.json` — 24,090,398 bytes, 60,196 bodies, sha256
  e5c5b768180d62338ee8e37e7fb44d0189d405131456ad04b2f88a78850ed8c7

The adapter fetches each into its own directory (`core/`,
`gurmukhi/` — one FileFetch pin per directory); the fixture mirrors
that layout.

## Delivery grains

`data/entries/` serves one JSON file per column on one id grid:

- `core.json` — the grid (id, hw, tr, vol, page, sources; excluded rows
  flagged) — **ACCEPTED** as the one dictionary document, each live row
  an entry; excluded rows (front matter, tables, abbreviation keys,
  duplicate artefacts) skipped by rule inside the file.
- `gurmukhi.json` — the original 1930 Gurmukhi body per id —
  **ACCEPTED**, joined to the grid.
- `en.json`, `hi.json` — the Punjabi University Patiala English
  (2006–2011) and its Hindi — **REJECTED**: a modern translation whose
  rights the packager is not shown to hold. Never fetched.
- the 25 other language columns — **REJECTED**: machine translations of
  the English. Never fetched.
- `corruption_flags.json` (flags on the English), `data/pages/`,
  `data/reading-aids/` (a separate Faridkot Teeka dataset), `site/` (the
  viewer) — not dictionary grains.

Reconciliation against `data/manifest.json` ("total_entries": 68150,
"live_entries": 64218, "excluded_entries": 3932): 64,218 entries +
3,932 excluded rows = 68,150; 60,196 bodies (README "60,196 / 64,218").

## Cut

- `core/core.json` — the 4 rows with id 1-2-0 (excluded front matter),
  1-37-0 (ਉ, the letter article), 1-37-13 (ਉਸਟਰੂ ਨੇਨ — its body records the
  book lemma ਉਸਟ), 1-37-21 (ਉਸਤ੍ਰ ਖਾਨ — no recovered body), values
  verbatim, re-serialized in upstream's own layout (one-space indent;
  the `count` field kept at upstream's 68150).
- `gurmukhi/gurmukhi.json` — the bodies of 1-37-0 and 1-37-13, values
  verbatim, compact one-line as upstream (1-37-0 carries upstream's
  private-use legacy-font codepoint U+F032).

## Refresh

Re-fetch the two raw URLs and re-select the same ids.
