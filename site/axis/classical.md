---
title: "Classical — The Classicist"
permalink: /axis/classical/
description: >-
  The Classicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Classicist — Greek and Latin letters read whole, Homer to the late grammarians.

The Greco-Roman literary lane: the Perseus canons and First1KGreek, Diorisis, LSJ and Lewis & Short, the grc/lat treebanks, and the Vulgate wearing its Latin-literature hat beside its scripture one.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these eight answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 24 July 2026)</span> |
|---|---|---|---|---|
| `perseus-greek` | texts | attribution | enabled · auto | 1,418 docs / 394,706 passages |
| `perseus-latin` | texts | attribution | enabled · auto | 534 docs / 391,785 passages |
| `first1k-greek` | texts | attribution | enabled · auto | 1,129 docs / 256,480 passages |
| `ud` | treebank | nc | enabled · manual | 36 docs / 238,032 passages |
| `proiel` | treebank | nc | enabled · frozen | 12 docs / 51,321 passages |
| `lexica` | dictionary | attribution | enabled · manual | 168,133 entries |
| `vulgate` | texts | open | enabled · manual | 73 docs / 35,809 passages |
| `diorisis` | texts | attribution | enabled · manual | 767 docs / 516,505 passages |

## The desk's instruments

- **Gold-lemma languages:** grc and lat — the Perseus canons, First1KGreek,
  Diorisis, and the grc/lat PROIEL and UD treebanks. `search --lemma`,
  `vocab`, `formulas` and `cognates` are all at their richest here.
- **Dictionaries:** LSJ and Lewis & Short, both on the `lexica` shelf
  (`nabu define μῆνις`, `nabu define virtus`).
- **Alignment works:** `nt` (Greek NT, Vulgate, SBLGNT) and — through the
  LXX and the Vulgate — `ot` and `psalms`. The Classicist owns both
  LXX-side witnesses.

## Working the classical desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis classical          # the shelf census, this desk only
nabu axis classical                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis classical   # a query scoped to this desk's shelves
nabu sync classical                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu align "MARK 2.3"                 # the parallel-witness card, Greek NT beside the Vulgate
nabu parallels urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1  # intertext and reception off Iliad 1.1
nabu vocab urn:nabu:proiel:cic-off    # distinctive vocabulary of Cicero, De officiis
nabu formulas urn:cts:greekLit:tlg0012.tlg001.perseus-grc2  # Homer's repeated formulas, ranked by count x length
nabu search λόγος --near θεός --window 5 --lang grc  # collocation search, lemma- and elision-aware
nabu define μῆνις                     # LSJ and Lewis & Short on the lexica shelf
```


## Terminal setup

- **Polytonic Greek (grc):** nabu leaves it intact (a `monotonic` display
  mode is opt-in). Any font with polytonic coverage works; for uniform
  metrics across Greek, IAST and Cyrillic, fill iTerm2's non-ASCII slot
  with **Noto Sans Mono** at the same size as the ASCII font.
- **Latin (lat):** nothing special — the terminal's default font suffices.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
