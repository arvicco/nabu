# archiv-slav-phil fixtures

archive.org hOCR derivative pairs (`<stem>_hocr_searchtext.txt.gz` +
`<stem>_hocr_pageindex.json.gz`), laid out as `canonical/archiv-slav-phil/`
holds them: `<identifier>/<upstream file name>`. Retrieved 2026-10-11 from
`https://archive.org/download/<identifier>/<file name>`. Public domain
(published 1876 and 1894).

- `archiv-fur-slavische-philologie-v-1-1876/` — *Archiv für slavische
  Philologie* Bd. 1 (Berlin 1876), a user upload (PDM 1.0) scanning
  Weidmann's 1964 facsimile reprint, Tesseract 5 OCR. TRIMMED to the first
  10 hOCR pages (upstream: 653 pages; searchtext 655,824 B, sha256
  77d0ef7e22e1925476924ad96a07da3260f51548afeea2b8b71b9742d58519cc;
  pageindex 7,971 B, sha256
  0ce84054f32c867541a01f574646ee1d9ae9059455978e512449d292967bf195):
  the title page, the reprint's licence page, the contributors list, the
  contents, the opening of Jagić's Zographos study.
- `archivfrslavis16berluoft/` — Bd. 16 (Berlin 1894), University of
  Toronto scan (NOT_IN_COPYRIGHT). TRIMMED to the first 14 hOCR pages
  (upstream: 664 pages; searchtext 728,221 B, sha256
  b591b2cbe13d34cd59a0ad2994a873efbfd3b6b4a62ff6d7d86385789a6ccff9;
  pageindex 8,156 B, sha256
  07171229677562f7f4f65ca910014300bdbf860f24d36ca3ec88b379c4693d9b):
  a marbled-endpaper OCR-noise page, six blank leaves, the title page,
  the contents with a Cyrillic entry mis-read as Latin.

Trim recipe (a prefix of whole pages needs no offset rebasing): keep the
first N rows of the page index verbatim; keep the search text's first
`rows[N-1][1]` CHARACTERS (the index counts code points); re-gzip both
(the index re-serialized as compact JSON with ", " separators).
