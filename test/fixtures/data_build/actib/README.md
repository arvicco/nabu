# xct/actib-anchors fixtures (P55-4)

Real trimmed slices for the ActibAnchorsBuilder tests — the ACTib side and
the Derge Kangyur volume skeletons the folio→page walk reads. The CATALOG
side (documents/passages) is synthetic in the tests by convention; the
UPSTREAM bytes here are real.

## actib/seg/UT4CZ5369-I1KG9167-0000.txt

ACTib v2.0 — The Annotated Corpus of Classical Tibetan (Meelen, Hill &
Faggionato), Zenodo record 3951503 (DOI 10.5281/zenodo.3951503), file
`SegPOS-eKangyur_July2020.zip`, seg layer. License: **cc-by-4.0 on the
Zenodo record** (API-verified 2026-07-31); the zip itself contains NO
license files — the record, not in-zip text, is the license basis.

- Retrieved: 2026-07-30 (from the Zenodo record file above).
- Trimmed: 2026-07-31. This is BDRC volume I1KG9167 = Esukhia volume 41
  (identity — the tail permutation only touches volumes 100–102), cut to
  two page regions at the LINE grain (whole real lines, nothing edited):
  pages **p1–p8** (the volume head: the ln-less title page p1, then
  ln-marked pages) and pages **p65–p70** (the folio-33x region — see the
  derge trim below). Page markers are absolute inline tokens (`p<N>`),
  so the middle cut does not renumber anything. Boundary lines that
  straddle a cut keep their whole line (a few tokens of the adjacent
  page ride along — harmless, and honest to the line grain).

## derge-kangyur/text/041_དཀོན་བརྩེགས།_ག.txt

Digital Derge Kangyur (github.com/Esukhia/derge-kangyur, pinned archival
HEAD `a582cf47…`, Public Domain per README §License), volume 041.
Retrieved 2026-07-28 with the main derge-kangyur fixtures; trimmed
2026-07-31 for the folio→page walk:

- lines 1–55 verbatim (folios 1a–4b, full text — the synthetic catalog
  passages anchor here), then
- the bare folio bracket lines only (`[5a]` … `[34b]`, 62 real lines in
  original order) for folios 5a–34b. Every folio side has such a bare
  line upstream; the walk counts folio sides, so the skeleton preserves
  the volume's ABSOLUTE physical page numbering — including the
  duplicated x-folios **[33xa]/[33xb]** (pages 67/68), which shift folio
  34a to page 69 (the naive 2F−1 rule would say 67).

## derge-kangyur/text/031_ཁྲི་བརྒྱད།_ག.txt

Same corpus, volume 031 — the mid-volume folio-restart witness (the
census's vol-31 correction). Two real line regions, concatenated:

- lines 1–12 (folios 1a, 1b, 2a head — the Toh 10 continuation region;
  the {D10} marker lives back in volume 029, so this trim carries no
  marker before the restart), then
- lines 3282–3288: the `[1b]` folio RESTART and the `{D11}` Tohoku
  boundary on `[1b.1]` — folio numbering restarts mid-volume where
  Toh 11 begins, which is why folio→page maps must be kept PER DOCUMENT
  (walk tests assert the disambiguation, not absolute page numbers,
  which the middle cut compresses).
