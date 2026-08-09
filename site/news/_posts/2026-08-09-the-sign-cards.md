---
title: "One glyph in, everything out — sign cards for Cuneiform and Egyptian"
date: 2026-08-09 21:10:00 +0000
description: >-
  nabu char grows beyond the Sinoverse: a cuneiform sign card re-joined
  entirely from data already on the shelf (the Oracc Sign List and the
  CDLI glosses riding inside it), and an Egyptian card anchored on
  Unicode 17's Unikemet file — 5,067 hieroglyphs with descriptions,
  functions, values, and three catalog concordances. Both cards count
  their signs in the wild, across millions of held passages.
---

`nabu char` has been the Han character desk since March: one glyph in,
the full held identity out — structure, readings, a diachronic column.
Today the same door opens for the two oldest writing systems in the
library.

**The cuneiform card cost no new source.** Everything it shows was
already on the shelf: the Oracc Sign List (CC0) has carried the sign
names, the readings with their language qualifiers, the variant forms,
and — quietly, in its `@list` lines — the concordances into every print
sign list an Assyriology student meets (Borger's MZL, Deimel's ŠL, LAK,
ABZL, HZL), and a CDLI concordance file riding in the same repository
carries the meaning glosses. The card is a re-join:

```
$ bin/nabu char 𒊬
𒊬  SAR  ·  U+122AC
sign lists: LAK 215 · ABZL 385 · HZL 353 · MZL 541 · KWU 650 · …
values (OSL): kiri₆ · mu₂ · nisi · sar · šar · … (26 readings)
meanings (CDLI): sar → v. to write; n. vegetable · kiri₆ → n. garden
in the corpus: sar 100333 · nisi 27997 · kiri₆ 8737 · …
```

That last line is the part no sign list can print: the card asks the
library's own full-text index how often each spelled reading actually
occurs across the 4.8 million held cuneiform passages. A sign list says
what a sign *can* read; the corpus says what it *does* read.

Input is anything a reader might have in hand: the glyph itself, the
sign name (`SAR`, ASCII `SZESZ` folds too), or a spelled value
(`szesz`). A value that belongs to several signs — `idₓ` lives on six —
lists every candidate, never one silently.

**The Egyptian card needed one new source, and it is a single file.**
Unicode 17's Unikemet data file is the quiet find of this program: the
first machine-readable Egyptian sign list to cover the full extended
repertoire — 5,067 hieroglyphs, each with a Gardiner-plus catalog code,
an English description of what the glyph depicts, its function
(phonogram, logogram, classifier), phonetic value, and concordances
into JSesh, Hieroglyphica, and the IFAO catalogue. The Egyptian
analogue of Unihan, under the same permissive license, at one stable
versioned URL.

```
$ bin/nabu char G5
𓅃  U+13143  ·  G5 (Gardiner/JSesh)  ·  core
A falcon.
function: Logogram (Horus)  ·  value: ḥr
in the wild (AES): 852 signs across 752 passages
```

The "in the wild" line reads the sign-level annotations the Ancient
Egyptian Sentences corpus carries on every token — so the falcon's 852
attestations are real occurrences in dated, sourced sentences, one
`nabu show` away.

Both sign cards speak JSON under `--json` — a frozen contract, because
the first consumer besides the owner is
[Nabu Edubba](https://arvicco.github.io/nabu-edubba/), the sister
school, whose reading panels are built on exactly this kind of answer.

The honesty rules that govern every desk card govern these: a field the
held data cannot back is absent, never dashed; an unencoded sign says
so; a reading the corpus has never used simply does not appear in the
attestation line.
