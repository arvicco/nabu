---
title: "Celtic — The Celticist"
permalink: /axis/celtic/
description: >-
  The Celticist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Celticist — from Lepontic stones to the Old Irish glossators.

Continental Celtic epigraphy (RIIG, Lexicon Leponticum and its word shelf), ogham Primitive Irish, CorPH's Early Irish, the UD Old Irish treebanks, and the kaikki attested-Celtic extracts riding wiktionary-recon.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these seven answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 36 docs / 238,032 passages |
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `riig` | inscriptions | attribution | enabled · manual | 495 docs / 1,357 passages |
| `ogham` | inscriptions | nc | enabled · manual | 873 docs / 1,053 passages |
| `corph` | texts | attribution | enabled · manual | 76 docs / 17,942 passages |
| `lexlep` | inscriptions | nc | enabled · manual | 494 docs / 570 passages |
| `lexlep-words` | dictionary | nc | enabled · manual | 627 entries |

## The desk's instruments

- **Gold-lemma language:** sga (Early Irish — CorPH's Annals of Ulster and
  the Milan / St Gall / Würzburg glosses, plus the Old Irish UD treebanks).
- **Epigraphy:** RIIG (Gaulish), ogham (Primitive Irish), Lexicon
  Leponticum and its word shelf (Lepontic).
- **Etymology:** the kaikki attested-Celtic extracts on `wiktionary-recon`
  carry the Proto-Celtic ancestry on the dictionary card — `nabu define rí
  --lang sga` names *rīxs and *h₃rḗǵs. (There is no Proto-Celtic
  reconstruction shelf yet, so `nabu etym`'s crosswalk ascent is thin from
  this desk — the cards are the richer walk.)

## Working the celtic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis celtic          # the shelf census, this desk only
nabu axis celtic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis celtic   # a query scoped to this desk's shelves
nabu sync celtic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu show urn:nabu:ogham:e-dev-001 --parallel  # an ogham stone beside its transliteration sibling
nabu search túath --axis celtic       # a query scoped to just the Celticist's shelves — túath in the glosses
nabu search --lemma rí --lang sga --axis celtic  # CorPH's gold Early Irish by dictionary form — every king in the Annals
nabu define rí --lang sga             # the Old Irish card, with its Proto-Celtic *rīxs ancestry
```


## Terminal setup

- **Ogham (pgl):** nabu spaces the letters with U+1680 so the stemline
  reads continuously; install `font-noto-sans-ogham`.
- **Old Irish / Gaulish / Lepontic:** Latin-script (CorPH carries per-token
  Latin code-switch coloring in `show`); the terminal default font works.
- Note: RIIG and ogham are **not** in the `--fuzzy` index — use plain
  `search --axis celtic` for them.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
