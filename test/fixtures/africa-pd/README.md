# africa-pd fixtures

archive.org hOCR derivative pairs (`<stem>_hocr_searchtext.txt.gz` +
`<stem>_hocr_pageindex.json.gz`), laid out as `canonical/africa-pd/`
holds them: `<identifier>/<upstream file name>`. Retrieved 2026-10-13 from
`https://archive.org/download/<identifier>/<file name>`. All three works
are public domain (Hanoteau †1897, Taylor †1927, Velten †1935; prints
1860–1907).

All three are PREFIX TRIMS:

- `prosaundpoesiede00velt/` — C. Velten, *Prosa und Poesie der Suaheli*
  (Berlin 1907), UNC Chapel Hill scan. First 22 hOCR pages (upstream: 470;
  searchtext 308,505 B, sha256
  7f03015828b5ebba9ce5491c4ea6fd37c116fc2569abe94567e6a63a6ca7c0aa;
  pageindex 5,547 B, sha256
  189a126a9c568e67cfa9123cdb456ef78c97cb01bc5f7ce79bd7da30b2b7fece):
  library cards, title page, the German preface and contents, and the first
  Swahili tale page (22) — the one sw-claiming item.
- `AfricanAphorisms/African_aphorisms_*` — W. E. Taylor, *African
  Aphorisms; or, Saws from Swahili-Land* (London: SPCK 1891), a community
  upload of Google's Harvard copy. First 9 hOCR pages (upstream: 206;
  searchtext 144,745 B, sha256
  2162967f131ed5e92326d0bb1f93b212ec37e563db506c83344e776552d094a0;
  pageindex 2,433 B, sha256
  4c8b3f74c7fe17ca89946b7c26bcb3ba0c03afd7a750fc84ba569f36d8ab5e7e):
  Google's two usage-guidelines pages, the title page, the Swahili dedication
  verse — the identifier ≠ file-stem case.
- `hanoteau-essai-de-grammaire-de-la-langue-tamachek-1860-copy-c/` —
  A. Hanoteau, *Essai de grammaire de la langue tamachek'* (Paris 1860),
  Harvard Peabody copy (PDM 1.0). First 10 hOCR pages (upstream: 342;
  searchtext 234,409 B, sha256
  e275e838af751f46c7a6156cba3f8849c9b64cb6c4e20075fe737f892528474a;
  pageindex 4,089 B, sha256
  24aad85c6c05d1ca7376d72332763688b725906ab3679c83009bcf6f740b3cc5) — the
  spaces-comma-and-parentheses file stem case.

Trim recipe (the slavistics-pd one; a prefix of whole pages needs no offset
rebasing): keep the first N rows of the page index verbatim; keep the search
text's first `rows[N-1][1]` CHARACTERS (the index counts code points);
re-gzip both (the index re-serialized as compact JSON with ", " separators,
as upstream writes it).
