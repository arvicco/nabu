# Peshitta fixture — ETCBC Peshitta OT (P31-4)

Byte-verbatim trimmed slices of the pinned `tf/0.2` Text-Fabric dataset
of [github.com/ETCBC/peshitta](https://github.com/ETCBC/peshitta) — the
OCR'd (syrocr) electronic text of the Leiden *Vetus Testamentum Syriace*
/ Codex Ambrosianus, WITHOUT the Brill-copyrighted critical apparatus.

- **Retrieved:** 2026-07-19, from commit
  `9850f5addade26f681334aa475570bef9b0b440a` (master), via raw GETs of
  `https://raw.githubusercontent.com/ETCBC/peshitta/master/tf/0.2/<name>.tf`.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches
  (`tf/0.2/*.tf`); the license-bearing `docs/about.md` (also in the
  sparse cone) is quoted below rather than checked in. Upstream's
  `__checkout__.txt` marker is not part of the dataset.
- **Trim recipe:** headers byte-verbatim; kept data lines byte-verbatim
  for the five books below (their word-slot ranges + their book/chapter/
  verse nodes), gap-anchored (the dss recipe); empty-value lines drop.
  `otype.tf` and `otext.tf` ride WHOLE — the census of record.

## Upstream census (at the pinned commit, from otype.tf — checked in WHOLE)

`tf/0.2` = 12 feature files ≈ 9 MB. otype.tf declares: **426,835 words /
65 books / 1,269 chapters / 31,341 verses** — every P31-4 briefed number
exact. Corpus-wide facts censused at the pin:

- (book, chapter, verse) globally unique; verse coverage is total
  (426,835/426,835 slots) with zero overlaps; verse node order equals
  slot order; zero empty verse renders.
- **The versification is MASORETIC, measured**: chapter counts of all 39
  protocanonical books match the MT grid exactly (Joel 4 / Malachi 3 /
  Proverbs 31 / Psalms 150 Hebrew-numbered); verse spot-checks Jonah
  1:16 + 2:11 (the MT split), Ps 22 opening at verse 2 with "my God, my
  God" (MT titulus-as-verse-1, superscription unprinted), Ps 23:1 = the
  shepherd. This measurement is what the ot-hub seventh leg and the
  psalms-work P13-5 remap rest on (config/alignments.yml).
- `book@en.tf` carries English names beside the sigla; ten books are A/B
  MANUSCRIPT RECENSION pairs (EpBar, Mc1, OrM, ApcPs, Tb) stamped by
  `witness.tf` at book+chapter+verse grain (uniform per book).
- **~492 word values are NOT NFC** (dot-above before dot-below, seyame
  order) → the adapter NFCs at the boundary (syc is not hbo/arc — no
  exemption). 10 of them ride this fixture (8 in Ruth).
- ONE word slot corpus-wide (40311, Leviticus) carries no word value —
  the token keeps its place with no "form" key (bhsa/dss precedent; not
  attested in these slices, documented here so the absence is honest).
- `trailer.tf` has 14 distinct values (space, ". ", the Syriac
  punctuation marks ܆ ܇ ܈ ܉ …).

## License (verbatim, docs/about.md, retrieved 2026-07-19)

> The plain text of the Peshitta, its conversion to Text-Fabric format,
> is subject to the CC-BY-NC license

> If you would like to use the textual data commercially, contact the
> ETCBC or Brill.

> The conversion program itself it subject the liberal MIT license.

Citation: DOI `10.5281/zenodo.1464757` → source class `nc`.

## The five book slices (2,960 words / 187 verses)

| book | siglum | node | words | verses | why |
|---|---|---|---|---|---|
| Obadiah | Ob | 426864 | 299 | 21 | smallest protocanonical book, single chapter |
| Jonah | Jon | 426865 | 718 | 48 | THE versification pin: 1:16 + 2:11 = the MT split (English bibles say 1:17/2:10) |
| Ruth | Ru | 426875 | 1,392 | 86 | carries 8 of the ~492 non-NFC word forms → the NFC-boundary regression (Ru 1:5 slot 282789) |
| Prayer of Manasseh A | OrM_A | 426892 | 259 | 16 | the A/B recension pair: witness.tf stamps at |
| Prayer of Manasseh B | OrM_B | 426893 | 292 | 16 | book + verse grain; genuinely different text, never merged |
