# cs-wikisource fixtures

Real api.php captures from cs.wikisource.org, retrieved 2026-10-10,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "html", the `action=parse&oldid=<revid>` rendering, only
on pages the wikitext rules admit):

- `pages/9925.json` — Rýmovaná kronika česká tak řečeného Dalimila/V
  (Jireček's 1877 edition, verse). Whole.
- `pages/68927.json` — Bible kralická (1613)/Rut: the 1613 print's
  Brethren orthography, a ProofreadPage transclusion with verse
  numbers and inline marginal summaries. Whole.
- `pages/41239.json` — Hospodine, pomiluj ny!: keys to the 1959 Český
  kancionál — the EDITION_TAINT_POST_1930 case. Whole wikitext; no
  rendering.
- `pages/84206.json` — Bible kralická: the {{Rozcestník}} versions
  shell. Whole wikitext; no rendering.

Re-cut: fetch each title's current revision via api.php
(prop=revisions, rvslots=main) and, for admitted pages, action=parse
with oldid=<revid>.
