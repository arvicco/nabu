# mongolic-pd fixtures

archive.org hOCR derivative pairs (`<stem>_hocr_searchtext.txt.gz` +
`<stem>_hocr_pageindex.json.gz`), laid out as `canonical/mongolic-pd/`
holds them: `<identifier>/<upstream file name>`. Retrieved 2026-11-08 from
`https://archive.org/download/<identifier>/<file name>`. All three works
are public domain (Zakharov †1885, Kowalewski †1878, Jülg †1886; prints
1844–1875).

Delivery grain: archive.org serves an ITEM (identifier) holding one or
more scanned volumes, each with its derivatives (PDF, djvu.txt, hOCR,
page images). The shelf takes the hOCR derivative PAIR of one curated
volume as the document; djvu.txt-only volumes are not read (the census
in `lib/nabu/adapters/mongolic_pd.rb` names the skipped ones). The
census is a curated table, so there is no rejected grain on disk.

All three are PREFIX TRIMS:

- `polnyimanchzhurs00zakh/` — I. I. Zakharov, *Полный маньчжурско-русскій
  словарь* (St Petersburg 1875), Library of Congress scan. First 10 hOCR
  pages (upstream: 1,254; searchtext 1,700,038 B, sha256
  c5a5a6b7817c2518f36da3c8a563b5c8d5964a74e559facb2f0496760c8813bd;
  pageindex 15,613 B, sha256
  fb268a25922dfd901d4cc05b640c2f0f8a6e1e6d230d2ea836df49e59dfbd5b9):
  five blank leaves, the two title pages, the faculty imprimatur and the
  first preface page — the mnc flagship, the blank-leaf case.
- `kovalevskij-dictionnaire-mongol-russe-francais-1844-49-volumes-1-3/` —
  J. É. Kowalewski, *Dictionnaire mongol-russe-français*, tome I (Kazan
  1844), a community upload (PDM 1.0) of Google's Bavarian State Library
  copy; the item holds all three volumes, each its own hOCR pair whose
  stem carries a comma, parentheses and a COMBINING CEDILLA (U+0327,
  "Franca̧is"). Volume 1, first 11 hOCR pages (upstream: 638; searchtext
  557,165 B, sha256
  228656aa27da7176be4fa5cbde5bc67ce9eb2a68f8febf808537c6b1103e58f2;
  pageindex 7,740 B, sha256
  6764d7a7e4b32e6a876f8cb3142a2f2d5a1918ff82e960fcba364b9c79616d80):
  Google's usage-guidelines pages, the bilingual title pages, the
  dedication — the cmg item, the identifier ≠ file-stem case.
- `10250287bsb/` — B. Jülg, *Die Märchen des Siddhi-Kür* (Leipzig 1866),
  BSB scan. First 9 hOCR pages (upstream: 261; searchtext 172,709 B,
  sha256 e9c6577a8f2cdec496155daf133c7966cf105011972dedd1724bcf2e33633b42;
  pageindex 3,052 B, sha256
  0056e4efd150704be3de3b5180e68625ee6d9a4d8ff9d6931662730d8640d622):
  the library stamps, the title page, the dedication to Gabelentz and
  Schiefner, the first preface page — the xwo item.

Trim recipe (the slavistics-pd one; a prefix of whole pages needs no offset
rebasing): keep the first N rows of the page index verbatim; keep the search
text's first `rows[N-1][1]` CHARACTERS (the index counts code points);
re-gzip both (the index re-serialized as compact JSON with ", " separators,
as upstream writes it).
