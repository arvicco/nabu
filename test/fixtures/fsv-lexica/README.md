# fsv-lexica fixture

Trimmed REAL excerpts of Språkbanken's three Old Swedish dictionaries in
their Karp LMF export. Retrieved 2026-11-02:

- https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/soederwall/soederwall.xml
  — 24,555,441 bytes, 22,572 LexicalEntry, sha256
  9eddf1d7f94dc34aa4a2b0620734dee7fe164a879df195ee96a2f6098f7ce1f4
- https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/soederwall-supp/soederwall-supp.xml
  — 16,204,745 bytes, 19,172 LexicalEntry, sha256
  58cb1e3e6370cff44a7aecd09c5bc89536d8f422ec92d8a2c5ac5055d843717f
- https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf/schlyter/schlyter.xml
  — 7,204,419 bytes, 10,067 LexicalEntry, sha256
  3875816d7c59fdd4f73065d76fef2ea1d9f5b1d6a972068854cea593986e1800

Resource pages (license "CC-BY-4.0" on each, read 2026-11-02):
spraakbanken.gu.se/resurser/soederwall, /soederwall-supp, /schlyter.

## Delivery grains

Each resource page offers ONE download, the whole dictionary as one
LMF file (`LexicalResource/Lexicon/LexicalEntry`, every datum a
`<feat att val>` pair). The adapter takes each file as one dictionary
document and each `LexicalEntry` as an entry; there is no rejected
grain (no other file is served; the Karp web view `karp-red` is the
same data, not fetched). Reconciliation: 22,572 / 19,172 / 10,067
entries = the pages' own "Ingångar" counts exactly.

## Cut

Byte-verbatim `LexicalEntry` blocks in upstream order inside the
file's own header and closing tags (the head and tail of each file kept
verbatim):

- `soederwall/soederwall.xml` — 0-based entries 0, 906, 1061:
  `fsvm--a..nn.1` (a full article with forms and a quoted citation,
  `&amp;quot;` double-escaped upstream), `fsvm--aterlösilse..nn.1` (an
  entry with no article text at all), `fsvm--avisning..nn.1` (its
  writtenForm keyed as "avisning . ").
- `soederwall-supp/soederwall-supp.xml` — entries 290, 438:
  `fsvm--alkali..e.1` (writtenForm "alkali  subst."; an `oldlemma`
  feat), `fsvm--argha..e.1` (the whole first sentence keyed into the
  writtenForm — the case for headword = lemgram baseform).
- `schlyter/schlyter.xml` — entries 0, 617, 3294: `fsvm--a..nn.1`
  (a morphosyntactic-tag att `NC?PNI` on a WordForm),
  `fsvm--avisning..nn.1` (the same lemgram as Söderwall's — the
  cross-dictionary key), `fsvm--hemuls__eþer..nn.1` (a double
  underscore in the lemgram, print hyphenation in the body).

## Refresh

Re-fetch the three URLs and re-select the same lemgrams (the lemgram is
upstream's own stable key).
