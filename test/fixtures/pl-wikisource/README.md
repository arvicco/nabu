# pl-wikisource fixtures

Real api.php captures from pl.wikisource.org, retrieved 2026-10-10,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "html", the `action=parse&oldid=<revid>` rendering, only
on pages the wikitext rules admit):

- `pages/1481.json` — Bogurodzica (pieśń): a ProofreadPage
  transclusion of Łoś's 1922 edition (Nagłówek adnotacje). Whole.
- `pages/25521.json` — Cyzjojan płocki: direct verse table with
  reference markers (adnotacje "XV wiek"). Whole.
- `pages/11208.json` — Na lipę II (Kochanowski, 1883): a section
  transclusion (fromsection/tosection); the edition is the title's
  parenthetical + the scan index. Whole.
- `pages/1387443.json` — Apologeticus to jest Obrona
  konfederacyej/Lavacrum conscientiae: the 1932 PAU edition (Dane
  tekstu rok wydania 1932) — the EDITION_TAINT_POST_1930 case. Whole
  wikitext; no rendering (excluded pages are never rendered).

Brückner (the dictionary lane), in the lane's own record shapes:

- `bruckner/entries.json` — five {{Bruckner}} entry stubs
  (Słownik etymologiczny języka polskiego/cmentarz, co, cuch, córa,
  gospoda) reduced to title/pageid/revid/section/first_page/last_page.
  gospoda's scan page (170) is deliberately NOT held.
- `bruckner/scans/191732.json`, `bruckner/scans/191923.json` — scan
  pages 084 and 085 (Strona: namespace), wikitext whole; córa's
  section spans the page break with the {{pp}}/{{pk}} hyphenation pair.

Re-cut: fetch each title's current revision via api.php
(prop=revisions, rvslots=main) and, for admitted pages, action=parse
with oldid=<revid>; the stubs and scans the same way.
