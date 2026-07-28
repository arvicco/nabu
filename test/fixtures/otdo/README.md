# OTDO fixtures

Real pages from Old Tibetan Documents Online (<https://otdo.aa-ken.jp>;
Research Institute for Languages and Cultures of Asia and Africa, Tokyo) —
414 critically edited Old Tibetan texts in Wylie transliteration.
Retrieved 2026-07-28. License: CC BY 4.0 (the /about Site Policy: "The
materials published on this site is licensed under a Creative Commons
Attribution 4.0 International License (CC-BY)").

The site is a live application: every page body carries a per-request CSRF
`_token` hidden input, so no fixture is byte-refetchable — a fresh GET of
the same URL serves the same content under a different token. Fixtures are
therefore kept as-served (the token bytes of the 2026-07-28 retrieval) and
marked non-refetchable in `manifest.yml`.

## Document pages (`/archives?p=<slug>`)

- `Pt_1287.html` — Pelliot tibétain 1287, the Old Tibetan Chronicle
  (the corpus flagship; plain-numbered lines `(1)`…`(536)`; tooltip
  glosses — OTDO's re-segmentation of surface forms, e.g. `bgyisna` →
  `bgyis na` — on lines 3 and 6). **TRIMMED**: transliteration lines
  `(13)`–`(536)` spliced out (the spans through `<br id="br11">` kept,
  splice to after `<br id="br535">`); header, metadata block and page
  furniture intact. 127 KB → 10 KB.
- `insc_Zhol.html` — the Zhol pillar inscription, Lhasa (whole). The
  inscription page kind: numbered metadata fields Content / Location /
  Date ("post 763", free text) / Condition / Photos / References; face-
  prefixed line labels `e1`… `s1`… `n1`… (east/south/north, the
  edition's own order), 158 lines.
- `Or_15000_0018.html` — Or.15000/18, a Dunhuang-region wood-slip letter
  (whole). Recto/verso labels `r1`–`r10`, `v1`–`v2`; heavy lacuna
  brackets `[---]` kept verbatim.
- `OZ_5.html` — the fifth Old Zhangzhung text (whole): a medical text
  OTDO's own catalog describes as "mostly Old Zhangzhung language" →
  language `xzh`, the one non-`otb` slice; 47 lines `r1`–`r47`.

## Catalog trims (`fetch/`, the OtdoFetch fixtures)

The live `/archives` catalog is ONE numbered table (rows 1..414, one
`datatxt[]` checkbox per document). Both fixtures are documented row
splices of the real 2026-07-28 page — header, form and footer untouched:

- `fetch/archives-6rows.html` — rows 1–6 kept (Pt_0016 Pt_0037 Pt_0126
  Pt_0149 Pt_0239 Pt_0366), rows 7–414 spliced out. Numbering 1..6 is
  self-consistent: the happy-path manifest.
- `fetch/archives-truncated.html` — rows 2–3 spliced out of the 6-row
  page: 4 rows under a top row number of 6, the count-assertion abort
  shape (a truncated or reshaped catalog must never crawl).
