# blbooks fixtures — British Library Digitised Books c.1510–c.1900 (JSONL)

Retrieved 2026-11-08 from the BL repository's bitstreams of the dataset
"Digitised Books. c. 1510 - c. 1900. JSONL (OCR derived text + metadata)"
(DOI 10.23636/r7w6-zy15; record
https://bl.iro.bl.uk/entities/product/af56d5ab-a384-4880-ba78-eca1ffd6a54d):

- `1510_1699.tar.gz` — https://bl.iro.bl.uk/bitstreams/c3fcee4c-1b01-4846-b0f9-7387ce0117a3/download
  (42,320,165 B, sha256 `6795dd54…`)
- `1700_1799.tar.gz` — https://bl.iro.bl.uk/bitstreams/e64fdf0c-9d5f-4474-82a0-81a33f0e5420/download
  (95,137,895 B, sha256 `da6ca859…`)
- `1800_1809.tar.gz` — https://bl.iro.bl.uk/bitstreams/f3eaf7ab-20f7-46e8-8d4d-fe99857066bb/download
  (first 3 MB only, ranged GET — enough to stream out one member)
- `unk.tar.gz` — https://bl.iro.bl.uk/bitstreams/dc7a1b27-903a-4653-b21a-62d879f8b10c/download
  (20,434,696 B)

License: CC0 1.0 (the record's dc.rights.license) / Public Domain Mark 1.0
(the HF card prose); the texts are pre-1900 prints.

## Upstream's delivery grains

1. **Period tarball** — 13 bitstreams: `1510_1699`, `1700_1799`, ten 1800s
   decades (`1800_1809` … `1890_1899`) and `unk` (undated). Each holds ONE
   top directory `<period>/`.
2. **Book file** — `<period>/<year>_<record_id>.jsonl.gz` (`UNKOWN_<id>` in
   `unk/`, upstream's spelling); exactly one record_id per file.
3. **Page row** — one JSON line per page: the page's `pg`, `empty_pg`,
   `text`, `mean_wc_ocr`/`std_wc_ocr`, plus the book's catalogue fields
   repeated on every row.

The adapter takes the **book** as the document and the **page with text**
as the passage. Rejected, each pinned here and skipped by rule:

| file | grain | rule |
|---|---|---|
| `1800_1809/1802_001246397.jsonl.gz` | 1800s decade book | outside the pre-1800 cone |
| `unk/UNKOWN_000188981.jsonl.gz` | undated book | outside the cone (no date; it is in fact a 1615-ish play — a dating lane is a follow-up) |
| `1700_1799/1778_001370315.jsonl.gz` | cone book with no OCR on any page | `Blbooks::EMPTY_BOOKS` (Capell's MS. catalogues) |
| every `"empty_pg": true` row | empty page | mints no passage |

## The trim

Each file keeps its LEADING page rows only, every kept line byte-identical
to upstream's (no re-serialization — upstream's bare `NaN` place literal
survives), re-gzipped:

| file | rows kept | with text | why it is here |
|---|---|---|---|
| `1510_1699/1510_002938347.jsonl.gz` | 8 | 4 | Plutarch, *Apophthegmata* (Paris 1510): catalogued English, actually Latin — the LANGUAGE_ERRATA case; no country |
| `1700_1799/1753_001734097.jsonl.gz` | 9 | 4 | Horace's *Art of Poetry* tr. Popple (London 1753): multi_language en + Latin, two [person] names |
| `1700_1799/1785_000744225.jsonl.gz` | 15 | 3 | *A collection of English, Scots, and Irish songs* (Salisbury): raw_date `1780-1790` widens the envelope; no names |
| `1700_1799/1778_001370315.jsonl.gz` | 5 | 0 | the all-empty book (414 rows upstream), place `NaN` |
| `1800_1809/1802_001246397.jsonl.gz` | 12 | 2 | the 1800s rejected-grain specimen |
| `unk/UNKOWN_000188981.jsonl.gz` | 9 | 2 | the undated rejected-grain specimen, place `NaN` |

Recipe: stream the tarball member, keep lines until N non-empty pages are
held, write them back with `gzip` (mtime 0).

## Census (both cone tarballs, through the adapter, 2026-11-08)

682 + 1,816 = 2,498 book files → 2,497 documents + 1 skipped by rule;
259,760 page rows → 230,206 passages (29,554 empty rows). Language_1:
English 2,463 · none 16 · French 10 · Latin 6 · Italian 2 · German 1
(Language_2: Latin 9 · Italian 3 · French 1) → after the 24 errata: en
2,470 · fr 10 · lat 8 · it 4 · de 3 · es 1 · nl 1.
