# analecta-hymnica fixtures

Retrieved 2026-11-04 from archive.org. Public domain (the *Analecta Hymnica
Medii Aevi*, Leipzig: Reisland, 1886–1922; editors Dreves †1909, Bannister
†1919, Blume †1932).

## Delivery grains upstream serves

archive.org serves the series as ITEMS; each item carries the scan (an
original or derived PDF, the JP2 page images, a black-and-white PDF) and
OCR derivatives (hOCR HTML, the hOCR search-text + page-index pair, DjVu
text). The adapter takes, per volume, ONE single-volume item's hOCR
search-text + page-index pair as the document (page grain, the
IaScanShelf family). The scan files themselves are never fetched (the
family precedent: the hOCR pair is the held asset; `ia_url` points at the
scan).

Item grains the census REJECTS, one real specimen each in `census/` (the
item's `/metadata/<identifier>` response, trimmed — see below), each
asserted to skip by `AnalectaHymnica.census_verdict`:

- `census/analectahymnicam13drev_0.json` — a **bundle**: Princeton
  Theological Seminary's "v. 1-3", three volumes in one hOCR stream.
- `census/analectahymnica01drevuoft.json` — **no hOCR pair**: the Toronto
  "drevuoft" catalogue copy of Bd. 1 (PDF only, no page grain).
- `census/analecta-hymnica-medii-aevi.json` — a **folder upload**: all 55
  volumes as PDFs inside one community item (files trimmed to Vol. 1 and the
  swapped Vol. 28 / Vol. 48 pairs; the item's `curation` field kept as the
  dark/un-dark evidence).
- `census/11338315bsb.json` — **not the series**: Wetzel's *Analecta
  hymnica* (Gotha 1751), a title-query false hit.

And the accepted grain's own metadata:
`census/analectahymnicam01drev.json` (eligible, adopted).

Specimen trim: the response's `metadata` block verbatim except the
person-identifying operator fields (`uploader`, `operator`, `updater`,
`adder`, `republisher*`, and `curation` on the two items where it is not
evidence), plus `files` restricted to the PDF and hOCR-pair entries
(`name`/`source`/`format`/`size` kept) and the original `files_count`.

## hOCR pairs (laid out as `canonical/analecta-hymnica/` holds them)

`<identifier>/<identifier>_hocr_searchtext.txt.gz` +
`_hocr_pageindex.json.gz`, from
`https://archive.org/download/<identifier>/<file name>`. Both are PREFIX
TRIMS:

- `analectahymnicam01drev/` — Bd. 1, *Cantiones Bohemicae* (1886), PIMS –
  University of Toronto. First 10 hOCR pages (upstream: 218; searchtext
  153,585 B, sha256
  949b20e66b4dcf69b1b0df2b7e415d5cb9f434a8d0acf9573e08327cb91d75c3;
  pageindex 2,554 B, sha256
  791f52a876884cce2c6a4e49253e2b06d829c7ab3f5e035f3e9a247de7e12abe): blank
  leaves, the series and special title pages, the library stamp, the first
  page of Dreves's Einleitung.
- `hymniineditilitu55drev/` — Bd. 55, *Thesauri hymnologici prosarium* II/2
  (1922), PIMS – University of Toronto (catalogued under Bd. 4's subtitle
  "Hymni inediti"). First 22 hOCR pages (upstream: 442; searchtext 468,788
  B, sha256 6cb02ec53f4788307fc54c1fe9382306f5a40c080ad26cf1a8c45afc036c9e77;
  pageindex 5,381 B, sha256
  ac656cbf024bb9efafc06b5aa9cbfd20aa83b9db25cdbbbbd3e3fec799271aee): the
  digitization leaf, both title pages, Blume's Vorwort, the first sequence
  ("Stola regni laureatus", ascribed to Adam of St Victor).

Trim recipe (the slavistics-pd one; a prefix of whole pages needs no offset
rebasing): keep the first N rows of the page index verbatim; keep the search
text's first `rows[N-1][1]` CHARACTERS (the index counts code points);
re-gzip both (the index re-serialized as compact JSON with ", " separators).
