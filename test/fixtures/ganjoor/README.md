# Ganjoor fixtures (classical Persian poetry) + SCHEMA CENSUS

A small, real, structurally intact slice of the **Ganjoor** library
(ganjoor.net) — the Persian poetry reference corpus — cut from the desktop
release database, plus the matching records of the site's poets endpoint.

- **Retrieved:** 2026-11-02.
- **Release:** `https://github.com/ganjoor/desktop/releases/download/v3.1/ganjoor-db-14050703.zip`
  (120,291,780 B, Last-Modified 2026-09-25; zip sha256
  `cfd74499d8397b197d67433d1a92d7676a3fb09057e5eaf85dd42ec8c6878802`) — one
  member, `ganjoor.s3db` (360,688,640 B, sha256
  `4f435f77d6060eadd554a6e268034eaf986a02c0351657c9882d1b382a403e7a`).
  The file name encodes the Solar Hijri release date 1405-07-03.
- **Poets endpoint:** `https://api.ganjoor.net/api/ganjoor/poets` (112,373 B,
  243 records) — the site's published-poet list with lunar-Hijri birth/death
  years and birth/death places with coordinates. The database itself carries
  NO dates or places for its poets.
- **License:** redistribution and reuse granted by the site operator by
  email, 2026-11-02 ("Redistribution of ganjoor contents is permitted and
  ganjoor data is free to reuse"). Ganjoor is credited as the digitizer.

## Files

| File | What it is |
|---|---|
| `ganjoor.s3db` | the release database's full DDL (all 9 tables + 3 indexes) with the rows of 11 poems, the cat chains they reach, their 7 poets, and `gver` whole (80 KB) |
| `api/poets.json` | 7 verbatim records of the poets endpoint (ids 2, 5, 7, 12, 22, 35 and 242) |

The 11 poems (Ganjoor poem ids):

| Poem | Poet | What it exemplifies |
|---|---|---|
| 2130, 2131 | Hafez (d. 792 AH) | two ghazals — plain right/left couplets; 2130 opens with an Arabic, fully vocalized hemistich whose mark order is NOT NFC upstream |
| 2051 | Hafez | a rubāʿī (the رباعیات section) |
| 33169 | Hafez | a poem from اشعار منتسب (attributed poems) |
| 41334 | Saʿdi (d. 694 AH) | a Golestān anecdote: one prose paragraph (position -1) + one couplet |
| 10680 | Saʿdi | from قصاید و قطعات عربی — an Arabic poem (the section label names the language) |
| 2996 | Mowlavi (d. 672 AH) | a Divān-e Shams ghazal with centered lines (positions 2/3 — band couplets) |
| 25300 | Rudaki (d. 329 AH) | three editorial comment rows (position 5) before the verse |
| 59493 | Ṣāʾeb (d. 1080 AH) | **rejected specimen:** a listed poem with zero verse rows |
| 49100 | Shahriār (d. 1409 AH) | **rejected specimen:** the modern tail (from his Azerbaijani-Turkish selection) |
| 500028 | Nimā Yushij | **rejected specimen:** a poet the release carries but the site does not publish (no poets-endpoint record, no URLs); free verse (position 4) |

Poet 242 (Ṭāleb Āmoli) is on the endpoint but has no rows in this release —
the endpoint is newer than the database (3 such poets live).

Recipe (re-cut from a fetched canonical copy): copy every `CREATE` statement
from `sqlite_master`, then insert the poem rows by id, their verse rows, the
cat rows reached by walking `parent_id` up from each poem's `cat_id`, the poet
rows those cats name, and `gver`; `VACUUM`. The poets file is the endpoint's
array filtered by id, records unchanged.

## Upstream's delivery grains (census of the whole release, 2026-11-02)

| Grain | Count | Disposition |
|---|---|---|
| poet (`poet`) | 281 | MINED — document metadata (name, description); never a document |
| cat — work/section tree (`cat`) | 2,511 | MINED — the poem's work/section path; never a document |
| **poem (`poem`)** | **140,497** | **THE DOCUMENT GRAIN** — `urn:nabu:ganjoor:<poet slug>:<poem id>` |
| verse row (`verse`) | 3,223,069 | grouped into the PASSAGE grain (couplet / band / line / prose paragraph) |
| comment row (`verse`.position 5) | 1,710 | MINED — document metadata `comments`; never a passage |
| desktop-app tables (`fav`, `gil`, `poemsnd`, `sndsync`) | 0 rows each | not content (bookmarks, filters, recitation audio sync) — empty in the release |
| `gver` | 1 row (3) | the schema version — not content |
| poets endpoint record | 243 | MINED — dates, places, coordinates; the published/modern rules read it |

Verse positions over all 3,223,069 rows: 0 right hemistich 1,517,913 · 1 left
hemistich 1,517,837 · 2 centered 1 13,561 · 3 centered 2 7,329 · 4 single
line 78,652 · -1 paragraph 86,067 · 5 comment 1,710.

## The discovery rules and the reconciliation

1. **Unpublished poets → skipped by rule.** 41 poets in the release have no
   record on the poets endpoint (the site does not publish them) — 17
   twentieth-century poets with ids in the 500s (Nimā, Shāmlu, Sepehri,
   Farrokhzād …), 21 more in the 600s (contemporary poets, plus Shāh Esmāʿil
   Ṣafavi's Khaṭāʾi selection), Sadegh Hedayat (701), a modern Persian
   rendering of the Avesta (998) and a modern Persian Qurʾān translation
   (999): **5,178 poems**, none of them with a URL.
2. **The modern tail → skipped by rule.** Published poets who died in or after
   **1324 AH** (1906 CE — the Constitutional Revolution, the conventional
   start of modern Persian literature) stay out this phase: their underlying
   author rights are the remaining caution. Every one of the 243 endpoint
   records carries a death year. **28 poets, 9,144 poems** (from Elhāmi
   Kermānshāhi, d. 1325, to Shahriār, d. 1409). Everything accepted died
   120+ years ago.
3. **Poems without text → skipped by rule.** 4 classical poems have no verse
   rows; 6 more carry only blank or comment rows: **10 poems**.

Accepted: **212 poets, 126,165 documents, 1,453,356 passages** (couplets
1,367,700-odd; the rest prose paragraphs, band couplets and unpaired
hemistichs). Reconciliation: 126,165 + 5,178 + 9,144 + 10 = **140,497** =
the release's own `poem` row count; the endpoint's 243 records = 212
accepted + 28 modern + 3 absent from the release.

Upstream's own advertised total ("1,528,993 bayts" on ganjoor.net/vazn,
2026-10-31) counts the whole published site (modern poets included, and the
site is newer than the release); the release's right-hemistich +
centered-line-1 rows (1,531,474) are the matching figure for the whole
database.
