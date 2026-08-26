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

A source wears every desk it serves — these sixteen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 26 August 2026)</span> |
|---|---|---|---|---|
| `perseus-greek` | texts | attribution | wired · auto | 1,418 docs / 394,706 passages |
| `perseus-latin` | texts | attribution | wired · auto | 541 docs / 393,921 passages |
| `first1k-greek` | texts | attribution | wired · auto | 1,129 docs / 256,480 passages |
| `ud` | treebank | nc | wired · manual | 76 docs / 325,533 passages |
| `proiel` | treebank | nc | wired · frozen | 12 docs / 51,321 passages |
| `lexica` | dictionary | attribution | wired · manual | 168,133 entries |
| `vulgate` | texts | open | wired · manual | 73 docs / 35,809 passages |
| `lila` | feature module | attribution | wired · manual | nothing held yet |
| `hypotactic` | feature module | attribution | wired · manual | nothing held yet |
| `diorisis` | texts | attribution | wired · manual | 767 docs / 516,505 passages |
| `glaux` | texts | attribution | wired · manual | 1,421 docs / 968,578 passages |
| `croala` | texts | attribution | wired · manual | 570 docs / 309,180 passages |
| `pedecerto` | feature module | nc | wired · manual | nothing held yet |
| `digiliblt` | texts | attribution | wired · manual | 372 docs / 459,451 passages |
| `openmgh` | texts | attribution | wired · manual | 153 docs / 36,143 passages |
| `corpus-corporum` | texts | nc | wired · manual | 5,248 docs / 896,770 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 26 August 2026)</span>: `grc` 120,553 · `lat` 58,418 · `eng` 872 · `gmh` 11 · `orv` 9 · `ota` 5 · `got` 4 · `lzh` 4 · `xcl` 4 · `cop` 3 … and 12 more (`nabu axis classical` lists all).

## The desk's instruments

- **Gold-lemma languages:** grc and lat — the Perseus canons, First1KGreek,
  Diorisis, and the grc/lat PROIEL and UD treebanks. `search --lemma`,
  `vocab`, `formulas` and `cognates` are all at their richest here.
- **Dictionaries:** LSJ and Lewis & Short, both on the `lexica` shelf
  (`nabu define μῆνις`, `nabu define virtus`).
- **Alignment works:** `nt` (Greek NT, Vulgate, SBLGNT) and — through the
  LXX and the Vulgate — `ot` and `psalms`. The Classicist owns both
  LXX-side witnesses.
- **The meter layer (P44–P45):** 167,732 scanned verse lines ride the
  catalog as enrichments — Latin from Pedecerto's scansions, Greek from
  Hypotactic — so `search --meter H` filters hits to hexameters (codes:
  H hexameter, D distich, and the scanner's full repertoire), and a
  scanned line's `nabu show` carries its meter. *Iliad* 1.1 knows it is
  a hexameter.

## Working the classical desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable classical               # first time: put this desk's shelves in this box's profile
nabu sync classical                 # fetch/refresh the desk's enabled members
nabu list --axis classical          # the shelf census, this desk only
nabu axis classical                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis classical   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu align "MARK 2.3"                 # the parallel-witness card, Greek NT beside the Vulgate
nabu search --meter H --lang lat      # metrical browse — every scanned Latin hexameter, corpus order
nabu search vesper --meter H --lang lat  # a text query filtered to hexameters (Catullus 62 opens the hits)
nabu parallels urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1  # intertext and reception off Iliad 1.1
nabu vocab urn:nabu:proiel:cic-off    # distinctive vocabulary of Cicero, De officiis
nabu formulas urn:cts:greekLit:tlg0012.tlg001.perseus-grc2  # Homer's repeated formulas, ranked by count x length
nabu search λόγος --near θεός --window 5 --lang grc  # collocation search, lemma- and elision-aware
nabu define μῆνις                     # LSJ and Lewis & Short on the lexica shelf
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Who quotes the opening of the Iliad?”** → `nabu_parallels urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1` — The reception of μῆνιν ἄειδε across the library: Galen (De placitis), Aristotle's Ars Rhetorica, Sextus Empiricus (seven loci), Dio Chrysostom, a metrical handbook — each hit with the shared folded phrase as evidence and a urn to open.
- **“What does LSJ say about this word, with citations I can open?”** → `nabu_define λόγος (lang: grc)` — The LSJ entry with senses as structured text; citations of works this library holds carry resolved passage urns for nabu_show.

## Terminal setup

- **Polytonic Greek (grc):** nabu leaves it intact (a `monotonic` display
  mode is opt-in). Any font with polytonic coverage works; for uniform
  metrics across Greek, IAST and Cyrillic, fill iTerm2's non-ASCII slot
  with **Noto Sans Mono** at the same size as the ASCII font.
- **Latin (lat):** nothing special — the terminal's default font suffices.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
