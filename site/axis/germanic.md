---
title: "Germanic — The Germanicist"
permalink: /axis/germanic/
description: >-
  The Germanicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Germanicist — Gothic, Old English verse and prose, the northern word-hoard.

Old English poetry (ASPR) and prose (ISWOC) with Bosworth-Toller, Gothic riding the proiel/ud treebanks, and Middle High German manuscripts (ReM).

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these six answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 29 docs / 107,664 passages |
| `proiel` | treebank | nc | enabled · frozen | 12 docs / 51,321 passages |
| `iswoc` | texts | nc | enabled · frozen | 5 docs / 2,536 passages |
| `menotec` | texts | nc | not enabled | not synced yet |
| `aspr` | texts | attribution | enabled · manual | 349 docs / 30,550 passages |
| `bosworth-toller` | dictionary | attribution | enabled · manual | 62,815 entries |
| `rem` | texts | attribution | not enabled | nothing held yet |

## The desk's instruments

- **Gold-lemma languages:** got (Gothic, on the PROIEL and UD treebanks)
  and ang (Old English — ASPR verse and ISWOC prose, the West-Saxon Mark).
- **Dictionary:** Bosworth-Toller (`nabu define aethele --lang ang` folds
  æ/þ/ð to find æþele).
- **Alignment work:** `nt` — Gothic (Wulfila) and Old English (the ISWOC
  West-Saxon Gospel of Mark). The Gothic × OCS `cognates` join is strongest
  from this desk.

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
nabu cognates "LUKE 14.34" --langs got,chu  # salt ~ соль meeting at PIE *sḗh₂l in the salt saying
nabu cognates nt --langs got,chu      # the whole New Testament, Gothic against Old Church Slavonic
nabu define aethele --lang ang        # Bosworth-Toller, with the æ/þ/ð fold
nabu search --lemma cyning --morph case=gen --lang ang  # a morphology facet over the UD/PROIEL feature vocabulary
nabu formulas urn:nabu:aspr:A4.1      # the Old English poetic formulas of Beowulf
```


## Terminal setup

- **Gothic (got):** nabu does nothing; install `font-noto-sans-gothic`.
- **Old English (ang):** Latin script with æ/þ/ð — any extended-Latin font
  (Noto Sans Mono covers it); no install needed.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
