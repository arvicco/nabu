# slavistics-pd fixtures

archive.org hOCR derivative pairs (`<stem>_hocr_searchtext.txt.gz` +
`<stem>_hocr_pageindex.json.gz`), laid out as `canonical/slavistics-pd/`
holds them: `<identifier>/<upstream file name>`. Retrieved 2026-10-11 from
`https://archive.org/download/<identifier>/<file name>` (archive.org
302s to a mirror node). All three works are public domain (Kopitar †1844,
Miklosich †1891); the items are marked NOT_IN_COPYRIGHT / PDM 1.0.

- `dasimperfectinde00mikl/` — Miklosich, *Das Imperfect in den slavischen
  Sprachen* (Wien 1874; Sitzungsberichte LXXVII), Library of Congress
  scan. BOTH FILES WHOLE, byte-verbatim (searchtext 23,048 B, sha256
  953ebf85542499ede68f261f897b1a41ca15311661c2b6006c2a1ee50b30371f;
  pageindex 388 B, sha256
  26364f8de767e4cca0130b91a6f01aa8bae72a4ad8df59350e19067f6afa1f6c):
  34 hOCR pages, 4 blank leaves, the OCR's own misreadings
  ("SLAYISCHEN").
- `glagolitaclozia00chrygoog/` — Kopitar, *Glagolita Clozianus* (Vienna
  1836), Google scan of the Oxford copy. TRIMMED to the first 10 hOCR
  pages (upstream: 177 pages; searchtext 435,812 B, sha256
  9794ad631bcaba409ba5c64b29697fc94c47f795e1ad2ab7dfdb3c37be796e7c;
  pageindex 2,136 B, sha256
  56c494899d5bd45a4c3678df2d63704be07dc649488bf8709e96df2b1af177b1):
  Google's usage-guidelines page, blank leaves, a Latin/Greek/Cyrillic
  mixed page — the garbled-OCR case.
- `miklosich-vergleichende-grammatik/4. Vergleichende Syntax (1926)_*` —
  Miklosich, *Vergleichende Grammatik* IV (Syntax; the 1926 Manulneudruck
  of 1868–74), BSB scan in the multi-file item. TRIMMED to the first 13
  hOCR pages (upstream: 907 pages; searchtext 1,151,184 B, sha256
  a1026b8efc9868787071a6a320bf1f3122048c735d9285c5e4ecf0cbb017cbbb;
  pageindex 11,300 B, sha256
  916753a9e203d6ba47747cfdfcfcb886f2bb4059d9e9dc1cd07769780521a953) —
  the spaces-and-parentheses file stem case.

Trim recipe (a prefix of whole pages needs no offset rebasing): keep the
first N rows of the page index verbatim; keep the search text's first
`rows[N-1][1]` CHARACTERS (the index counts code points); re-gzip both
(the index re-serialized as compact JSON with ", " separators, as
upstream writes it).
