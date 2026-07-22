---
title: "Germanic — The Germanicist"
permalink: /axis/germanic/
description: >-
  The Germanicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Germanicist — Gothic and Old English to the Norse sagas and the runestones, the word-hoard of all three branches.

Gothic on the proiel/ud treebanks beside the West and North Germanic branches: Old English verse (ASPR) and prose (ISWOC) with Bosworth-Toller, Old Icelandic (IcePaHC via ud), Old Norwegian and the Poetic Edda (Menotec), the Old Saxon Heliand (HeliPaD), Middle High German manuscripts (ReM), and the runic inscriptions (Rundata, dual-tagged epigraphy).

The desk spans all three Germanic branches. **East** is Gothic (Wulfila,
gold-lemmatized in PROIEL). **West** runs Old English (ASPR verse, ISWOC
prose), the Old Saxon *Heliand* (HeliPaD), and Middle High German (the ReM
manuscripts). **North** arrives in force: Old Icelandic through IcePaHC — a
rule-based UD conversion of the Icelandic Parsed Historical Corpus, filed
under `is` — Old Norwegian and the Poetic Edda of Codex Regius through
Menotec (`non`), and, dual-tagged with the epigraphy desk, the runic
inscriptions of Rundata. The wave went live 2026-07-22 with the
owner-verified first syncs — all five shelves hold their corpora below.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these nine answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 36 docs / 238,032 passages |
| `proiel` | treebank | nc | enabled · frozen | 12 docs / 51,321 passages |
| `iswoc` | texts | nc | enabled · frozen | 5 docs / 2,536 passages |
| `menotec` | texts | nc | enabled · manual | 7 docs / 20,308 passages |
| `aspr` | texts | attribution | enabled · manual | 349 docs / 30,550 passages |
| `bosworth-toller` | dictionary | attribution | enabled · manual | 62,815 entries |
| `rem` | texts | attribution | enabled · manual | 406 docs / 355,449 passages |
| `rundata` | inscriptions | odbl | enabled · manual | 30,643 docs / 30,641 passages |
| `helipad` | treebank | attribution | enabled · manual | 1 docs / 3,549 passages |

## The desk's instruments

- **Gold-lemma languages:** got (Gothic, on the PROIEL and UD treebanks),
  ang (Old English — ASPR verse and ISWOC prose, the West-Saxon Mark), and
  — live since the 2026-07-22 wave — gmh (ReM's 2.10M rows, instantly the
  corpus's third-largest gold pool), non (Menotec's PROIEL-scheme Old
  Norwegian and the Edda, 258K) and osx (HeliPaD's gold form-lemma
  Heliand) and is (IcePaHC via the ud sync — 812K rows, straight in at
  #4 of all the gold pools: the deepest North Germanic lemma lane).
- **Dictionary:** Bosworth-Toller (`nabu define aethele --lang ang` folds
  æ/þ/ð to find æþele).
- **Alignment work:** `nt` — Gothic (Wulfila) and Old English (the ISWOC
  West-Saxon Gospel of Mark). The Gothic × OCS `cognates` join is strongest
  from this desk.
- **The runic five-lane design (Rundata):** each inscription is one
  document keyed on its signum (`urn:nabu:rundata:u-344`); the bare urn is
  the scholarly Latin transliteration (the notation legend is content, never
  stripped), and up to four sibling lanes — `-fvn`/`-rsv` normalisations,
  `-eng`/`-swe` translations — ride beside it, reached with `show
  --parallel`.
- **The timeline desk:** Rundata is the germanic desk's first dated lane —
  the RundataDates extractor puts each inscription's SRDB year envelope and
  find-spot on the calendar, so `--from/--to`, `--century` and `--place`
  scope the runestones. (gmq-pro tags the urnordisk-dated inscriptions —
  Proto-Norse, for which no ISO code exists.)

## Working the germanic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis germanic          # the shelf census, this desk only
nabu axis germanic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis germanic   # a query scoped to this desk's shelves
nabu sync germanic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu show urn:nabu:aspr:A4.1:1        # Beowulf, line 1
nabu show urn:nabu:rundata:u-344 --parallel  # the Yttergärde runestone beside its normalisation and translation lanes
nabu show urn:nabu:menotec:non-edda-regius-dep  # the Poetic Edda, Codex Regius (Menotec)
nabu search --word cyning --lang ang  # whole-word match on an Old English form (ASPR/ISWOC)
nabu search liudi --lang osx --axis germanic  # the Old Saxon Heliand text (HeliPaD)
nabu search --lemma konungr --lang non --axis germanic  # the Menotec gold lemma lane — kings across the Edda and the sagas
nabu define aethele --lang ang        # Bosworth-Toller, with the æ/þ/ð fold
nabu formulas urn:nabu:aspr:A4.1      # the Old English poetic formulas of Beowulf
```


## Terminal setup

- **Gothic (got):** nabu does nothing; install `font-noto-sans-gothic`.
- **Old English (ang):** Latin script with æ/þ/ð — any extended-Latin font
  (Noto Sans Mono covers it); no install needed.
- **Old Icelandic / Old Norwegian (is/non):** IcePaHC and Menotec store the
  text in Latin script (þ/ð/æ/ǫ) — the terminal default suffices, no install.
- **Old Saxon (osx):** the HeliPaD Heliand is Latin-script Penn bracketing
  (uu for w); nothing to install.
- **Middle High German (gmh):** ReM's diplomatic transcription keeps the
  long ſ (U+017F) and combining editorial marks — any Unicode font renders
  them (Noto Sans Mono); nabu's search fold maps ſ→s, so you need not type it.
- **Runic (Rundata):** the transliteration IS the text — a scholarly Latin
  transliteration with zero runic codepoints stored, so no runic font is
  needed; the notation legend (`§A`/`§B` sides, `|` boundaries, a leading `"`
  marking a name) is content and never stripped, and the normalisation and
  translation lanes are sibling documents reached with `show --parallel`
  (docs/display.md §4).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
