# cy-wikisource fixtures

Real api.php captures from cy.wikisource.org, retrieved 2026-10-21, in
the adapter's own envelope shape (`pages/<pageid>.json`: the page's
title/pageid/ns/revid/timestamp/wikitext verbatim + "cone" + "indexes"
(each named Indecs page's stated fields, verbatim) + "html" (the
`action=parse&oldid=<revid>` rendering) and "page_quality" on admitted
pages only).

Delivery grains upstream serves: the ns-0 text page (a book root, a
chapter/poem subpage, or a "(testun cyfansawdd)" composite of the whole
book), the Indecs (scan Index) page, the Tudalen (scan page). The
adapter takes the ns-0 text page; composites are a rejected grain
(aggregate), pinned below.

- `pages/2097.json` — Beibl (1620)/Obadeia: the 1620 Bible (Indecs
  Year=1620, inside the ≤ 1800 band) — ADMITTED, orthography original.
- `pages/14699.json` — Oll synnwyr pen Kembero ygyd/Abyl i pop peth ae
  bodlono: Salesbury's 1547 proverbs — ADMITTED.
- `pages/12427.json` — Gwaith Dafydd ap Gwilym/Y Niwl: the 1901 Cyfres y
  Fil volume (a censused EXTRA_INDEXES print) — ADMITTED, orthography
  modernized.
- `pages/12421.json` — Gwaith Dafydd ap Gwilym/Rhagymadrodd: the
  editor's introduction (apparatus). No rendering.
- `pages/68678.json` — Beirdd y Berwyn 1700-1750 (testun cyfansawdd): the
  whole-book composite (aggregate). No rendering.

All whole. Re-cut: the adapter's own fetch into a scratch directory
(never canonical/) with its cone narrowed to these titles — or by hand:
prop=revisions for the page and its Indecs pages, action=parse
(oldid=<revid>) for admitted pages, prop=templates (tlnamespace=104) +
prop=proofread for the levels.
