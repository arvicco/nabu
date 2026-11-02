# Steingass 1892 — acquisition (library-shelf reference scan)

F. Steingass, *A Comprehensive Persian-English Dictionary, including the
Arabic words and phrases to be met with in Persian literature* (London:
Routledge & Kegan Paul; first edition 1892) — the standard Persian
reference dictionary of the classical language, as a public-domain scan
for the local-library shelf. A scan for the shelf, not an adapter: the
PDF is filed through `nabu ingest` (the library shelf's one write
gateway) and becomes a citable, page-addressable library document.

**Why by hand**: the acquisition itself is one unattended download, but
filing onto the owner's library shelf is the owner-shelf gateway's act
(`nabu ingest`, interactive or `--yes` with flags), never an adapter
fetch. This document keeps that intake replayable.

## The item (verified 2026-11-02)

- archive.org item **`a-comprehensive-persian-english-dictionary_202208`**
  — <https://archive.org/details/a-comprehensive-persian-english-dictionary_202208>
  (collection folkscanomy; added 2022-08-05; 300 ppi; metadata API
  <https://archive.org/metadata/a-comprehensive-persian-english-dictionary_202208>).
- **License capture:** the item's `licenseurl` field reads
  `https://creativecommons.org/publicdomain/mark/1.0/` (Public Domain
  Mark 1.0). This is the uploader's mark; the public-domain status rests
  on the work itself: Steingass died in 1903, so the 1892 text is out of
  copyright everywhere on life + 70. Record the field verbatim at
  acquisition time.
- **Which printing:** the scanned title-page verso reads "FIFTH
  IMPRESSION … ROUTLEDGE & KEGAN PAUL LIMITED … First Edition 1892 /
  Second Impression 1930 / Third Impression 1947 / Fourth Impression
  1957 / Fifth Impression 1963" — a reprint impression of the 1892 text
  with no new editorial matter (the Preface is Steingass's). The item's
  `date` field ("2005") is uploader metadata the scan does not support;
  catalogue the work as 1892.
- **Intact:** the scandata lists **1,545 leaves** (1 Title + 1,544
  Normal, every one in the access formats); the first 7 leaves are the
  unnumbered front matter (title, verso, Preface), and the OCR text runs
  from the title page through the final yā' entries (yā'is, yāyān). The
  catalogued collation is viii + 1,539 pp. A spot collation of the printed
  page numbers against the leaves is the acceptance check at ingest —
  the page map's OCR-detected numbers are not reliable for it (they read
  up to "1589" and miss 98 values).
- **Files** (sizes and sha1 from the item's files.xml):

  | File | Bytes | sha1 |
  |---|---|---|
  | `A Comprehensive Persian-English Dictionary.pdf` (the uploaded original, text PDF) | 106,876,101 | `144228b2f0c791574d7d3ea79fca6c0afc7c8c64` |
  | `A Comprehensive Persian-English Dictionary_page_numbers.json` | 263,032 | `790b254fab2988509e13c0d27f56db6b897df20c` |
  | `A Comprehensive Persian-English Dictionary_djvu.txt` (machine OCR) | 7,241,663 | `ae116de1966f646c88016d096dd087be79f093f8` |

  The OCR text layer strips the transliteration's diacritics and reads
  the Perso-Arabic headwords as garbage ("A Us® ya'ts"), so it is NOT a
  text source; a structured Steingass belongs to a transcription
  enrichment, never to the scan's OCR.

## The route

1. Open the item page above and confirm the license field still reads
   the Public Domain Mark (capture it verbatim).
2. File the PDF onto the library shelf through the gateway — the URL is
   downloaded by `nabu ingest` itself:

   ```
   bin/nabu ingest "https://archive.org/download/a-comprehensive-persian-english-dictionary_202208/A%20Comprehensive%20Persian-English%20Dictionary.pdf" \
     --collection dictionaries \
     --title "A Comprehensive Persian-English Dictionary" \
     --creator "Steingass, Francis Joseph" --year 1892 \
     --languages fas,ara,eng --tags dictionary,persian \
     --provenance "Public Domain Mark 1.0 per archive.org item a-comprehensive-persian-english-dictionary_202208 (Routledge & Kegan Paul fifth impression 1963 of the 1892 first edition; Steingass d. 1903)" \
     --license-class open --yes
   ```

3. Verify the downloaded bytes against the sha1 above (`shasum` on the
   shelf copy) and spot-collate a few printed pages against the PDF's
   leaves (front matter = 7 leaves).

## Where it goes

`canonical/local-library/dictionaries/` with one manifest entry (the
`dictionaries` collection beside the Lange/Ulmann/Dravnieks scans); the
shelf's own sync mints the urn. No adapter, no ManualDrop contract.

## Not used (and why)

- **DSAL** (dsal.uchicago.edu/dictionaries/steingass/) serves a
  structured digitization under a stated CC BY-NC-ND 2.0 license — not
  this shelf's route.
- **alpheios-project/stg** (a TEI of Steingass, 69,868 entries) states
  no license and no provenance independent of DSAL — parked until its
  lineage is shown.

## Refresh

A finished 1892 work in a static archive.org item — expect no churn. If
archive.org re-derives the item, the sha1s change: re-verify the
license field and the leaf count before refiling.
