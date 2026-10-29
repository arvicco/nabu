# jaschke-1881 fixtures

H. A. Jäschke, *A Tibetan-English Dictionary, with special reference to the
prevailing dialects; to which is added an English-Tibetan vocabulary*
(London: Secretary of State for India in Council, 1881). The Robarts Library
(University of Toronto) copy, scanned by the Internet Archive 2007:
archive.org item `tibetanenglishdi00jsuoft`
(https://archive.org/details/tibetanenglishdi00jsuoft).

**Retrieved 2026-10-29** from the item's stable download URLs
(`https://archive.org/download/tibetanenglishdi00jsuoft/<file>`).

**License:** public domain. Jäschke died 1883; printed 1881. The item's own
rights fields: `possible-copyright-status` NOT_IN_COPYRIGHT, evidence "no
visible notice of copyright; stated date is 1881" (reported by
lexw@archive.org, 2007-07-23).

## Files (trimmed real upstream files)

| File | Upstream (full) | Fixture |
|---|---|---|
| `tibetanenglishdi00jsuoft/tibetanenglishdi00jsuoft.pdf` | 80,960,908 bytes, 702 pages, sha1 `146fad4ff870fcf8efc3affb278d6928db8019f4` | leaves 27–28 (print pp. 1–2) cut with `mutool merge -o out.pdf full.pdf 27-28` |
| `tibetanenglishdi00jsuoft/tibetanenglishdi00jsuoft_page_numbers.json` | 119,002 bytes, 702 leaf entries, sha1 `d4cea0cdec1ef012e36a5479a3c651bb71bd41fa` | the header verbatim + the entries for leaves 1, 3, 27, 28, 637, 695, 698, 702 |

The sha1 values are the item's own `files.xml` checksums, verified against
the downloaded bytes on 2026-10-29; the adapter pins them.

## Delivery grains upstream serves (enumerated at fixture time)

- **The item** (the whole volume) — not the document grain: the dictionary
  is cited by printed page ("Jäschke p. 135"), and a 702-leaf volume as one
  document has no page handle.
- **Scan leaves** — the PDF's 702 pages = the page map's 702 `leafNum`
  entries (leaf *k* is PDF page *k*). **ACCEPTED at leaf grain**, one
  document per printed leaf, classed by the curated leaf map (verified by
  reading the scan, 2026-10-29):

  | Leaves | Print | Section | Fate |
  |---|---|---|---|
  | 1–2 | — | binding (front cover, endpaper) | skipped by rule |
  | 3–26 | unnumbered | front matter (title, preface, introduction with the transliteration key, dialect tables, abbreviations, half-title) | accepted |
  | 27–634 | pp. 1–608 | Tibetan–English dictionary | accepted |
  | 635–694 | pp. 609–668 | English–Tibetan vocabulary (half-title, blank verso, pp. 611–668) | accepted |
  | 695–697 | pp. 669–671 | Corrections | accepted |
  | 698 | [p. 672] | printer's colophon (Unger Brothers, Berlin) | accepted |
  | 699–702 | — | binding (endpapers, library card pocket, back cover) | skipped by rule |

  Print page *N* sits on leaf *N* + 26 throughout; the page map's own
  `pageNumber` agrees on every leaf it numbers (it leaves pp. 1–9 and
  671–672 blank).
- **jp2 images** (`_jp2.zip`, 706 files) — the same leaves as images plus
  **4 calibration cards** (scandata `pageType` Color Card ×2, White Card ×2)
  that the PDF and the page map omit; never discovered, counted only in the
  reconciliation (706 = 702 + 4).
- **OCR derivatives** (ABBYY, hOCR, djvu.txt, chOCR, searchtext, EPUB) —
  rejected: the machine OCR strips the romanisation's diacritics and reads
  the Tibetan script as garbage. Documents carry `text_layer: none`; a page
  transcription is a future enrichment.
- **Item metadata** (`_meta.xml`, MARC, Dublin Core) — read once for the
  license and bibliographic facts above; not a document grain.

## Specimens kept

- leaf 1 — binding (front cover): the skip-by-rule specimen (front)
- leaf 3 — front matter (title page)
- leaves 27, 28 — dictionary pp. 1–2 (the PDF trim holds exactly these two
  page images; the converter's verified headword pairs were read from them)
- leaf 637 — vocabulary p. 611
- leaf 695 — corrections p. 669
- leaf 698 — colophon [p. 672]
- leaf 702 — binding (back cover): the skip-by-rule specimen (back)

The adapter never reads the PDF's contents (no text layer is taken), so the
two-page trim stands in for the full scan as the documents' canonical path.
