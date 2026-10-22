# OBIMD fixtures

Real files from the Oracle Bone Inscriptions Multi-modal Dataset on
Hugging Face (<https://huggingface.co/datasets/KLOBIP/OBIMD>, DOI
10.57967/hf/7821), dataset revision
`4820d2f11a8f45f3347591fdcd5f6466706b0dce` (2026-03-11), retrieved
2026-10-21. License: CC BY 4.0 (card front matter `license: cc-by-4.0`;
LICENSE "Creative Commons Attribution 4.0 International / You must give
appropriate credit to the author(s).").

## Delivery grains

The dataset repo serves:

1. `data.json` — ONE JSON array of 10,077 rubbing records (sentence groups
   of reading-ordered glyph boxes). **Accepted**: split into one document
   per record (`RubbingName`).
2. `Hierarchical Character Metadata Supplement/Main-character.json` — the
   main-character UID → reference modern character map. **Accepted** as the
   text layer's lookup table (no documents of its own).
3. `README.md` — the dataset card (license stamp, field table).
   **Rejected**: description, not a record; fetched for license provenance
   and counted in `discovery_skips` — pinned here whole as `card/README.md`.
4. Never fetched (documented in the adapter): `rubbing.zip` (558 MB),
   `facsimile.zip` (211 MB), `Sub-character Images.zip` (40 MB) — the image
   modality; the two XLSX tables (sub-character → platform-font code point,
   sub → main UID); `OBIMD.py` (the `datasets` loader); `figures/`.

## Files

- `data/data.json` — **TRIMMED (record splice)**: 8 whole records of the
  real file, byte-verbatim (upstream's 4-space indent and CRLF line ends),
  rejoined as a JSON array: `H2` (a ligature glyph read 十一月), `H224`
  (sentence + bare `OracleSequence` + outcome; a ligature whose
  transcription holds an unassigned code point → ⬚), `H4413` (two glyphs
  sharing OrderNumber 2), `H8342` (a UID absent from the character map),
  `H9830` (the label `InscriptionSentence2` repeated), `H14717` (Mark 2,
  OrderNumbers starting at 1), `H17138` (an `Uncertain` group, Mark 0, a
  null label), `HD514` (Huadong). 41.7 MB → 18 KB.
- `chars/Main-character.json` — **TRIMMED**: the 25 entries (of 3,936)
  whose UIDs the 8 records use, byte-verbatim entry splices, CRLF kept.
- `card/README.md` — whole, byte-identical (the rejected card grain).
