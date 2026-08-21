# salom fixtures — Şalom Ladino articles text corpus (Hugging Face)

Retrieved 2026-08-19 from the Hugging Face dataset
`collectivat/salom-ladino-articles` (Col·lectivaT + Sephardic Center of
Istanbul; the corpus behind "Preparing an Endangered Language for the
Digital Age: The Case of Judeo-Spanish", EURALI 2022), via the
plain-HTTPS resolve URL:

- `Salom-ladino-2022-01-ext-04_segmented_shuffled.txt` — trimmed from
  <https://huggingface.co/datasets/collectivat/salom-ladino-articles/resolve/main/Salom-ladino-2022-01-ext-04_segmented_shuffled.txt>
  (full artifact 2026-08-19: **991,480 bytes, 10,686 lines**, sha256
  `3201c17619c5d16c1bbfea958f4d47994cfaa5c12696cdb25954b9b839cf0a2e`).
  The fixture holds byte-verbatim lines **1–8** plus the artifact's ONE
  blank line — upstream's final line 10,686 is empty (the file ends
  `\n\n`), so the honest sentence count is **10,685**. The fixture
  mirrors that tail: a trailing blank line that must mint NO passage
  while line-number identity stays put. No BOM/CRLF, all lines NFC.

The corpus is 397 Şalom newspaper Judeo-Espanyol articles **segmented into
sentences and shuffled** — article structure is not recoverable from the
artifact (one document, sentence grain, is the honest shape). Card
language tag: `lad` (Ladino / Judeo-Spanish), Latin-script Turkish-style
orthography. No sentence ids — passage identity is the 1-based line
number in the local canonical file (the tla-hf precedent).

## License (verified 2026-08-19)

Dataset card YAML frontmatter, verbatim: `license: cc-by-4.0`. The card's
prose: "Original sentences and articles belong to Şalom" with the EURALI
2022 paper as the requested citation. → `license_class: attribution`.
