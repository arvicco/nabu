# korpus16 fixtures

Korpus 16 — Korpus besedil slovenskih protestantskih piscev 16. stoletja
(Inštitut za slovenski jezik Frana Ramovša ZRC SAZU; https://fran.si/korpus16,
version 1.0, 2019). License: CC BY-SA 4.0 — the colophon
(https://fran.si/korpus16/o-portalu?page=Colofon) reads verbatim "To delo je
dostopno pod licenco Creative Commons Priznanje avtorstva-Deljenje pod enakimi
pogoji 4.0".

Retrieved 2026-11-05 by direct HTTP GETs, paced at ~1 request/second
(robots.txt disallows only /iskanje/). Every file is stored exactly as the
adapter stores it in canonical/korpus16/.

## Delivery grains (census 2026-11-05)

| Grain | URL | Taken? |
|---|---|---|
| corpus index | `/korpus16` | yes — the book list (45 ids, each tiled twice: the all-authors tab + its author tab) |
| book | `/korpus16/Knjiga/<id>/<slug>` | DOCUMENT — no TOC grain of its own; page 1 carries the book header and the pager (max = page count) |
| page | `/korpus16/Knjiga/<id>/<slug>?stran=<n>` | PASSAGE (one per page with body text) |
| portal pages | `/korpus16/o-portalu?page=Info\|Colofon\|Bibliography` | REJECTED as text — kept as count/license provenance, skipped by rule |
| news | `/korpus16/o-portalu?page=News` | not fetched (one line: "1.0, 30. oktober 2019, Portal začne delovati") |
| search | `/korpus16/iskanje` | robots-disallowed, never touched |
| cover images | `/korpus16/slika/*.jpeg` | not text, never fetched |

No bulk deposit exists: the colophon's promised CLARIN.SI deposit links hdl
11356/1166 (the Thesaurus of Modern Slovene, unrelated), and a full OAI-PMH
harvest of the CLARIN.SI repository (1,362 records, 2026-11-05) holds no
Korpus 16 record.

Reconciliation: Info advertises "45 knjižnih del na 12.945 straneh"; the index
lists 45 book ids; the 45 page-1 pagers sum to exactly 12,945.

## Files

- `map/korpus16.html` — the index (`https://fran.si/korpus16`), TRIMMED: the
  carousel tiles kept for books 9, 25, 39, 43, 58 only (10 of 90 tiles: each
  book twice); everything else verbatim.
- `map/about-Info.html`, `map/about-Colofon.html`, `map/about-Bibliography.html`
  — whole (the rejected portal grain, pinned).
- `books/9/00001–00007.html` — COMPLETE: Trubar, *Ena molitov tih
  kerszhenikou* (TM 1555), all 7 pages; p. 1 carries an Italian epigraph, p. 3
  an upstream `#` (illegible) marker, p. 7 is a blank placeholder.
- `books/39/00001–00008.html` — COMPLETE: Trubar, *Ta pervi psalm shnega
  triiemi islagami* (TPs 1579), all 8 pages (a German title block, catchwords).
- `books/58/00001.html`, `00200.html` — PARTIAL: Dalmatin's *Biblia* (DB
  1584, 1,565 pages); p. 200 = folio I,56a (running heads, marginal notes, a
  column break). Skips by rule as a crawl in progress.
- `books/25/00001.html` — PARTIAL: *Eni psalmi* (TPs 1567, 31 pages) — the
  "(ur.)" editor header.
- `books/43/00001.html` — PARTIAL: *Ta celi novi testament* (TT 1581-82, 1,136
  pages) — the two-year siglum against a one-year imprint.

## Recipe (re-cut)

GET each URL above with a 1 s pause; store raw bytes at the listed path
(`books/<id>/<nnnnn>.html`, five-digit page index); re-trim the index by
dropping every `<div class="thumbnail">` tile (23 lines) whose link is not one
of the five book ids.
