# damos fixtures

Real captures from DĀMOS (Database of Mycenaean at Oslo,
https://damos.hf.uio.no), retrieved 2026-10-18. Site footer, verbatim:
"Content: CC BY-NC-SA 4.0" — small trimmed samples ride public, the
proiel/torot nc precedent.

- `items/755.json` — `GET https://damos.hf.uio.no/ajaxitem/755/`,
  KN B 822: the po-ḍạ-qe-re-ṣị-je-wo line, combining under-dots
  (U+0323), the VIR logogram, `vac.`. Whole.
- `items/4985.json` — `GET …/ajaxitem/4985/`, PY Tn 316: recto and
  verso (the `v.` side marker restarts the line numbering), unlabeled
  margin lines ("reliqua pars sine regulis", "di-we si-p̣ọ-ṛọ ti-mi-ṭọ"),
  editorial notes. Whole.
- `items/277.json` — `GET …/ajaxitem/277/`, KN Vc <295>: a LOST tablet
  (`lost: -1`, meta "Preserved": "No"), one unlabeled line. Whole.
- `items/5755.json` — `GET …/ajaxitem/5755/`, TH Z 839: an inscribed
  stirrup jar in the "Vases - Thebes" collection, clay provenance
  "West Crete α", U+00A0 inside its Context label. Whole.
- `map/ajaxgetfilter.json` — `POST https://damos.hf.uio.no/ajaxgetfilter`
  (empty body), TRIMMED: `tables` cut to the rows of six ids (the four
  above + 4972 PY Ta 641 + 5443 TH Ug 1), `collections` cut to those
  ids' four collections with each `count` RESTATED to the kept ids (so
  the trimmed listing passes the adapter's truncation defense); every
  other filter array cut to its first 2 entries. The live response
  (2026-10-18): 29 collections, 7,687 table rows over 5,932 unique ids.

Re-cut: GET the four ajaxitem URLs; POST the listing and apply the
trim above.
