# ntvmr fixtures

Real answers of the INTF New Testament Virtual Manuscript Room's anonymous
web-service API (`https://ntvmr.uni-muenster.de/community/vmr/api/`),
retrieved 2026-11-23 — a handful of single requests, each at least 10 s
apart. The tree has the shape the adapter's fetch leaves in
`canonical/ntvmr/`.

**Etiquette (read first-hand the same day):** `robots.txt` disallows
`/community/vmr/api/` for every agent ("not for search-engine crawling:
several endpoints execute expensive database queries. Bulk data consumers:
please contact the INTF, or use the documented exports rather than walking
the API"), `Crawl-delay: 10`. These fixtures are a few one-off requests,
never a crawl; the adapter's crawl lane is declared SUSPENDED until the
INTF grants bulk access. Re-cut only under that permission (or from a held
`canonical/ntvmr/`).

**License:** every transcript's TEI header carries, verbatim, "(C) 2026
Institut für Neutestamentliche Textforschung." and "This work is licensed
under a Creative Commons Attribution 4.0 Unported License" linking
`https://creativecommons.org/licenses/by/4.0/`. CC BY 4.0 permits these
copies with credit: Institut für Neutestamentliche Textforschung, Münster.

## Upstream's delivery grains (enumerated at fixture time)

| Grain | Where | Taken? |
|---|---|---|
| The Liste: every catalogued VMR document, one empty `<manuscript>` each (docID, gaNum, lang, orig, origEarly/origLate, primaryName) | `metadata/liste/get/` (no parameters; 1,074,627 bytes, `count="7772"`, 7,772 records) | **yes, as the census** |
| Liste records of the GA manuscripts — docIDs 1xxxx papyri, 2xxxx majuscules, 3xxxx minuscules, 4xxxx lectionaries (6,200) | inside the Liste | yes — the crawl universe |
| Liste records outside those classes — versional witnesses (Coptic, Syriac, Latin, Armenian, Arabic …), LXX/Qumran items, printed editions, project copies re-using a GA number, family and test records (1,572) | inside the Liste | **no — rejected by rule**, specimens kept in `liste.xml` |
| The whole published transcription of one manuscript, TEI | `transcript/get/?docID=<id>&pageID=ALL&format=teiraw` | **yes — the document grain** |
| A page or verse-range cut of the same TEI | `pageID=<n>` / `indexContent=Phlm` | no — subsumed by the whole-manuscript answer (one fixture uses a verse-range cut, see below) |
| The error answer for an untranscribed manuscript (HTTP 200) | same URL: `<error code="1" message="No Transcription Available for GA: … page: ALL"/>` | **no — ledgered no-transcript**; a specimen kept on disk, skipped by rule |
| The error answer for an uncatalogued docID (HTTP 200) | same URL: `<error code="300" message="docID: 34000 not found"/>` | no — ledgered not-found (the body is quoted in the test) |
| Page images | `image/…` | no — restricted, licensed by the holding institutions |
| Manuscript/institute metadata, collation, CBGM, regularization services | `metadata/manuscript/`, `collate/`, `cbgm/` … | no — not the transcription; the Liste is the census |

The Liste carries no place; `origEarly`/`origLate` are `0` on all 7,772
records. The TEI `msIdentifier` (country, settlement, repository, idno) is
the manuscript's present holding library.

## Files

- `liste.xml` — TRIMMED: the real Liste answer cut to 24 of its 7,772
  records, each `<manuscript …/>` element byte-identical and in upstream
  order (docID ascending), the root `<manuscripts count="7772">` kept
  verbatim — so the file is itself a truncated answer, which the fetch
  defense refuses (the test stubs it with `count="24"`). In scope (14):
  P1, P46, P52, 01, 03, 059, 0189, 304, 1674, 2306a, 1674a, L1, L500,
  l 102a. Rejected (10): `MS Syriac 99` (50004), a blank gaNum (53002),
  Var1 (100001), sa 1 (620001), Test (888000), Erasmus 1516 (2151600),
  19 (8000019 — a project copy of minuscule 19), yo2 (9900000), 03
  (9993001 — a copy of Vaticanus), f1 1 (90030001).
- `transcripts/10052.xml` — WHOLE (7,649 bytes): P52 (Manchester, Rylands
  Gr. P. 457), `pageID=ALL` — two folios, John 18:31–33, 37–38, the page-
  edge verses `part="F"` / `part="I"`, `supplied source="na28"`.
- `transcripts/20189.xml` — WHOLE (19,700 bytes): 0189 (Berlin, P. 11765),
  `pageID=ALL` — two pages, Acts 5:3–21, verse 12 and the word ομοθυμαδον
  split across the page break, nomina sacra, punctuation.
- `transcripts/20001.xml` — WHOLE answer of a verse-range query
  (12,911 bytes): 01 Sinaiticus (London, BL Add. 43725) with
  `indexContent=Phlm` — Philemon 1–25 with corrector2/2a/2b readings in
  `app/rdg`, ab keyed in OSIS (`Phlm.1.1`) rather than `B18K1V1`. Stands
  in for the rich specimen: the small whole-manuscript answers probed
  (0189, 0220, 0162) carry no corrections.
- `transcripts/20059.xml` — WHOLE (76 bytes), the REJECTED grain: the
  real answer for 059 (Liste docID 20059, IV/V), `<error code="1"
  message="No Transcription Available for GA: 059 page: ALL"/>`. The crawl
  ledgers it; found on disk it is skipped by rule.

## Re-cut

Only under the INTF's permission (see Etiquette). Liste:
`GET metadata/liste/get/`, keep the 24 elements by docID. Transcripts:
`GET transcript/get/?docID=10052&pageID=ALL&format=teiraw` (likewise
20189, 20059) and `transcript/get/?docID=20001&indexContent=Phlm&format=teiraw`.
The `(C) <year>` line in each header is generated per request.
