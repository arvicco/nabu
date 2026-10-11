# elektire fixtures

Real upstream samples from **eLektire** (lektire.skole.hr — CARNET's
school reading portal; books by Bulaja naklada), retrieved 2026-10-11, laid
out as `Nabu::ElektireFetch` lands them.

`index/` — real WordPress REST responses, verbatim:

| File | Request |
|---|---|
| `djela-1.json` | `/wp-json/wp/v2/djela?include=<the five works>&_fields=<the fetch's WORK_FIELDS>` (the fetch pages the whole listing; the fixture asks for the five works only) |
| `<taxonomy>-1.json` | `/wp-json/wp/v2/<taxonomy>?per_page=100&page=1&_fields=id,slug,name` — knjizevnost, stoljece_nastanka, knjizevna_vrsta, knjizevni_zanr, epohe, lektira (each one page today) |
| `media-<work id>.json` | `/wp-json/wp/v2/media?parent=<id>&per_page=100&_fields=id,source_url,modified,mime_type` |

`epub/` — five real books, each the most recently modified EPUB attached
to its work, RE-PACKED WITHOUT fonts, images and scripts (binary furniture
the parser never reads); every XHTML/OPF/NCX/CSS entry is byte-identical.

| Book | Why |
|---|---|
| `pjesme-8.epub` | Marin Kaboga, Pjesme — v2 (2013), 16th-c. verse; PD statement; d. 1582 |
| `jedupka.epub` | Mikša Pelegrinović, Jeđupka — v2, footnote anchors with inline glosses (`span.middleNNNpx`) |
| `duga.epub` | Dinko Šimunović, Duga — v3 (2018, CARNET), glossary links, Prije/Metodički/Poticaji/Kviz pages, "…su u javnoj domeni." |
| `mali-od-foguna.epub` | Viktor Car Emin — called public domain by the impressum, but d. 1963: excluded by the life+70 rule |
| `izabrane-pjesme-16.epub` | Grigor Vitez (d. 1966) — no public-domain statement: excluded |

Licence: per work, the impressum's own statement (the works are public
domain; the books' apparatus — glossary, notes, author note — is reserved
by the publisher and is never ingested).
