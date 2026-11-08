# nb-no fixtures

Nasjonalbiblioteket (National Library of Norway) — public-domain books through
the keyless catalog API (https://api.nb.no/catalog/v1). License per item:
accessInfo `"license": "publicdomain"`, `"accessAllowedFrom": "EVERYWHERE"`;
the IIIF manifest (license https://www.nb.no/lisens/#public-domain) attributes,
verbatim: "Du kan kopiere, endre, spre, vise og fremføre dette verket, selv for
kommersielle formål, uten å spørre om tillatelse."

Retrieved 2026-11-08 by direct HTTP GETs, paced at ~1 request/second
(api.nb.no serves no robots.txt and no rate-limit headers). `canonical/` is
stored exactly as the adapter stores it in canonical/nb-no/ (ALTO pages
gzipped with the adapter's byte-stable writer, mtime 0); `api/` holds the
search answer the fetch tests stub.

## Delivery grains (census 2026-11-08)

| Grain | URL | Taken? |
|---|---|---|
| search answer | `/catalog/v1/items?q=*&filter=…` | CENSUS — the cone query, paged 100 rows; reduced to census.tsv |
| item record | `/catalog/v1/items/<id>` | DOCUMENT metadata (`items/<id>/item.json`) |
| ALTO list | `/catalog/v1/metadata/<id>/altos` | the page list (`items/<id>/altos.json`) |
| ALTO page | `/catalog/v1/metadata/<id>/altos/<URN>_<tail>` | PASSAGE (`items/<id>/alto/<tail>.xml.gz`) |
| IIIF manifest | `/catalog/v1/iiif/<id>/manifest` | not fetched — page labels + images; its license line is quoted above |
| MODS / MARCXML / Dublin Core | `/catalog/v1/metadata/<id>/mods` … | not fetched — the item record carries the same catalogue fields as JSON |
| content fragments | `/catalog/v1/items/<id>/contentfragments` | not fetched — search snippets |
| whole-book text | (accessInfo names a "text" action) | no public endpoint answers it (probed) |

Rejected by rule at the item grain: a record whose accessInfo is not public
domain is never paged (pinned: `items/0056d274e30fd6246b3d29373c35ab97`, a
1608 *Grammaticae Hebraeae* catalogue row in content class "public" with
`isDigital: false`, `license: copyrighted` — the class whose larger counts
hold such rows; skipped by rule).

Reconciliation (the cone, 2026-11-08): the cone query answers totalElements
1,910; the paged census holds 1,910 unique ids (530,042 pages by pageCount).
`api/search-cone.json` is the same query narrowed by
`filter=sesamid:(<the four PD ids>)` — a real answer, totalElements 4.

## Files

- `canonical/items/3d460ef4040b4bc7a4c849f4b6ceec1b/` — COMPLETE: Ambrosius
  Rhodius, *Potentissimo Principi … Friderico III … Carmen* (Christianiae:
  Michael Thomasson, 1660; Latin; pre-1700 arm) — all 4 pages (C1 the title
  page, I1, I3, C3 an OCR-noise back page). FineReader 12.
- `canonical/items/59aa6dee234eab2f582dd5ba75f57597/` — COMPLETE BY TRIM:
  *Þorfinns saga karlsefnis* (Reykjavík 1902; Old Norse) — `altos.json`
  TRIMMED from 48 entries to the three held pages (0001 title page, 0003
  preface, 0010 saga text with a hyphenated line break). FineReader 12.
- `canonical/items/9353c8a56ea655710692a548673b9618/` — COMPLETE BY TRIM:
  N. V. Stockfleth, *Abes ja låkkam-girje* (Kristianiast 1837; North Sámi;
  the record's genres ABC-bøker/Lesebøker/Lærebøker) — `altos.json` TRIMMED
  from 53 entries to 0001, 0005, 0012. Tesseract 5.2 ALTO (a re-processed
  scan: no CCS processing step).
- `canonical/items/0148f6ba555e6d8ec9b5aaea23d39cbc/` — PARTIAL: *Edda Snorra
  Sturlusonar* (København 1931, ed. Finnur Jónsson; Old Norse) — the full
  353-entry `altos.json`, one page held (0011); skips by rule as a crawl in
  progress (352 pages to go).
- `canonical/items/0056d274e30fd6246b3d29373c35ab97/item.json` — the
  not-public-domain specimen (above).
- `api/search-cone.json` — the cone search answer narrowed to the four public
  domain ids above.

## Recipe (re-cut)

GET `https://api.nb.no/catalog/v1/items/<id>` → `item.json`;
`…/metadata/<id>/altos` → `altos.json`; each listed page href → gunzip-able
`alto/<tail>.xml.gz` (gzip, mtime 0 — re-gzip with Ruby's
`Zlib::GzipWriter`, mtime 0, so the bytes equal the adapter's). For the two
trimmed items, drop every `_links.alto` entry whose tail is not held and
re-serialize compactly. The search answer: the census query
(`NbNo.census_url(0)`) plus `filter=sesamid:(id OR id …)`.
