# Diorisis fixtures

Real files from the Diorisis Ancient Greek Corpus, figshare v1 (2018):
retrieved 2026-07-18 from https://ndownloader.figshare.com/files/11296247
(article https://figshare.com/articles/dataset/The_Diorisis_Ancient_Greek_Corpus/6187256,
DOI 10.6084/m9.figshare.6187256.v1). The zip is 194,443,428 bytes;
**md5 `f3a26efa7e7d2b93d1bcca26900d180a`** — verified byte-for-byte against
figshare's own published `computed_md5` at download — and
**sha256 `fb32b7ff4bcfc433f1234aff8134096f524c9a32accbfdf0a072df4a5f019b65`**
(the adapter's `ZIP_SHA256` pin, computed from that verified download).

## License (the in-file doctrine's third proof)

- **In-file, all 820 files** (publicationStmt/licence, verbatim):
  "Creative Commons Attribution-ShareAlike 3.0 United States License"
  (`https://creativecommons.org/licenses/by-sa/3.0/us/`). **This governs.**
- figshare page/API claim, verbatim from the article metadata: license
  `"CC BY 4.0"` (`https://creativecommons.org/licenses/by/4.0/`) — quoted
  for the record, subordinate to the files' own declaration.

## Files

- `Hymns (0013) - Hymn 13 To Demeter (013).xml` — WHOLE file, byte-verbatim
  (8,323 bytes, 3 sentences). Documents: numeric poetry `location`s that
  REPEAT (sentences 2 and 3 both cite line 3), an unlemmatized word
  (`<lemma id="unknown">` with no entry), `TreeTagger="true"` with
  `disambiguated="0.5"` and `"1.0"` confidence fractions, capitals and
  elision in Beta Code (`*dhmh/thr'`).
- `Thucydides (0003) - History (001).xml` — teiHeader + sentences 1–3 of
  the 36.9 MB upstream file, byte-verbatim, with `</body></text></TEI.2>`
  closers appended (the house trim procedure). Documents: dotted
  book.chapter.section `location`s ("1.1.1"), a Perseus-provenance header,
  empty-entry lemmas and fractions in prose.
- `Septuaginta (0527) - Abdias (040).xml` — teiHeader + sentences 1–2 of
  the upstream file, same trim. **PINNED AS EXCLUDED**: `tlgAuthor` 0527 is
  the Septuagint (53 files upstream), Rahlfs-lineage via Bibliotheca
  Augustana and CATSS-encumbered (docs/02-sources.md row 44) — discover
  skips it by rule and parse refuses it; the fixture exists so the
  exclusion stays test-pinned. Note its `location` attributes are EMPTY —
  upstream ships the LXX without citations.

## Re-trim procedure

Download the zip, verify the md5 above, unzip, then for the trimmed files:

    awk '/<sentence id="4" /{exit} {print}' <upstream>.xml > fixture.xml   # Thucydides (id="3" for Abdias)
    printf '    </body>\n  </text>\n</TEI.2>\n' >> fixture.xml
