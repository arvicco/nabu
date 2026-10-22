# tipitaka.lk (tipitaka-lk) fixtures

Real files from github.com/pathnirvana/tipitaka.lk (branch `master`, commit
`4fe56eb061d10722a605640a7fd0bd80c0ca33d3`, 2026-10-22), retrieved
2026-10-22 by raw GETs of
`https://raw.githubusercontent.com/pathnirvana/tipitaka.lk/master/<path>`.
The layout mirrors the repository: the adapter discovers
`public/static/text/*.json` (its sparse fetch cone).

License: CC BY-ND 4.0 with upstream's sync condition (the repo's
LICENSE.md, which names the Buddha Jayanthi Pāli text: no modification —
errors are reported upstream; keep in sync with the repository; attribute
tipitaka.lk). The Sinhala translation and the CST aṭṭhakathā with its
Sinhala translation are covered on the same terms by Path Nirvana's grant
(by email, 2026-10-22). Class `research_private`.

## Recipe (trimming)

Each text fixture keeps the file's top-level keys verbatim and a SUBSET of
its `pages` array, whole pages only (entries and footnotes untouched),
re-serialized exactly as upstream serializes (`json.dumps(indent=4,
ensure_ascii=False)`, no trailing newline — a round-trip of the untrimmed
upstream files through that serializer is byte-identical, checked at
retrieval). Re-cut from canonical/tipitaka-lk/ the same way once the source
is synced.

## Delivery grains

- `public/static/text/<file>.json` — 285 files at the commit above (canon
  190: vp/dn/mn/sn/an/kn/ap; aṭṭhakathā 93: atta-*; Visuddhimagga 2:
  anya-vm*). ACCEPTED: one file → a Pāli root document + a Sinhala `-si`
  sibling (none for the seven Pāli-only ap-pat* files).
- pages × entries inside a file — the passage grain, cited
  `<pageNum>.<entry n>` on both layers; entries whose plain text is empty
  skip by rule.
- `public/static/data/` (tree.json, file-map.json, sitemap,
  footnote-abbreviations*.json), `dev/alignments/`, `db/dict.db.zip`, the
  dictionary submodule — generated or reference data. REJECTED: outside the
  fetch cone. Specimen pinned: `public/static/data/footnote-abbreviations.json`
  (whole, 9.8 KB — the footnote-sigla key); the adapter test asserts
  discovery never reaches it.

## Files

- `public/static/text/kn-khp.json` — Khuddakapāṭha (canon, collection
  `mula`, bookId 28). Pages 2, 4, 6, 18 of 11 (pages[0,1,2,8]). Carries
  Pāli footnotes with `{n}` pointers (2.6 → "සරණත්තයං – මඡසං"), a Sinhala
  footnote (18.4), gāthā entries with line breaks, and an EMPTY Pāli
  paragraph (6.4) whose Sinhala counterpart is present — the by-rule skip.
  66 pli + 67 si passages.
- `public/static/text/atta-an-11.json` — Aṅguttara aṭṭhakathā,
  Ekādasakanipāta (collection `atta`, bookId 15). Pages 1, 3, 21 of 11
  (pages[0,1,10]). Bold lemmata (`**…**`), `keyOffset` headings, and an
  empty Sinhala centered entry on page 21. 42 pli + 41 si passages.
- `public/static/text/ap-pat-2-83.json` — Paṭṭhāna (Pāli-only upstream:
  every `sinh` column empty; NO `collection` key; pageOffset -135). Pages
  1137–1138 of 38 (pages[0,1]). 11 pli passages, no sibling.
- `public/static/data/footnote-abbreviations.json` — WHOLE; the rejected
  grain specimen (above).
