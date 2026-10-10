# uk-wikisource fixtures

Real api.php captures from uk.wikisource.org, retrieved 2026-10-10,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "html", the `action=parse&oldid=<revid>` rendering, only
on pages the wikitext rules admit):

- `pages/40746.json` — Сборникъ лѣтописей/Добромильская лѣтопись: the
  1888 Kyiv edition, a ProofreadPage transclusion (рік 1888,
  рік_секції 1700) — ADMITTED. Whole.
- `pages/48952.json` — Львівський літопис: a {{версії}} shell. Whole
  wikitext; no rendering.
- `pages/50958.json` — Львівський літопис і Острозький літописець/С
  кройніки Бельського речі потребнії вибрані (Острозький літописець):
  the shell's edition page, keyed to Бевзо's 1971 edition — the
  EDITION_TAINT_POST_1930 case ("cone" records the versions follow).
  Whole wikitext; no rendering.
- `pages/9072.json` — Про князя Олега: a modern-Ukrainian retelling
  (a censused exclusion). Whole wikitext; no rendering.

Re-cut: fetch each title's current revision via api.php
(prop=revisions, rvslots=main) and, for admitted pages, action=parse
with oldid=<revid>.
