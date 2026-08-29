---
title: "Romance — The Romanist"
permalink: /axis/romance/
description: >-
  The Romanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Romanist — the Latin-to-vernacular continuum, charter Latin to Roland to the troubadours.

The Latin-to-vernacular continuum: CroALa's medieval and neo-Latin opens the desk; late-antique prose, the MGH critical editions, and the Old French treebanks and texts join as their shelves land.

The continuum is on the shelves end to end: **digilibLT**'s late-antique
secular prose (2nd–7th c.), **CroALa**'s Croatian Latin (a 976 CE charter
through the neo-Latin centuries, dual-tagged with `classical`), the
**openMGH** critical editions (the *SS rerum Germanicarum* first wave —
Einhard, Widukind, Adam of Bremen), **BFM**'s Old and Middle French from
the 842 *Serments de Strasbourg* onward, and the **UD Romance treebanks**
(Tuscan charters, Dante's Latin, Old French, Old Romanian) carrying the
gold annotation — four gold-lemma languages: `fro`, `frm`, `ro`, `ota`.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these sixteen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 29 August 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 76 docs / 325,533 passages |
| `croala` | texts | attribution | wired · manual | 570 docs / 309,180 passages |
| `digiliblt` | texts | attribution | wired · manual | 372 docs / 459,451 passages |
| `openmgh` | texts | attribution | wired · manual | 153 docs / 36,143 passages |
| `bfm` | texts | attribution | wired · manual | 219 docs / 333,819 passages |
| `cantigas` | texts | attribution | wired · manual | 1,682 docs / 34,162 passages |
| `derom` | dictionary | nc | wired · manual | 233 entries |
| `osta` | texts | nc | wired · manual | 740 docs / 5,177 passages |
| `disco` | texts | attribution | wired · manual | 1,215 docs / 4,527 passages |
| `ctilc` | texts | attribution | wired · manual | 967 docs / 256,685 passages |
| `bdcamoes` | texts | attribution | wired · manual | 127 docs / 69,812 passages |
| `corpus-corporum` | texts | nc | wired · manual | 5,248 docs / 896,770 passages |
| `lo-congres` | texts | attribution | wired · manual | 12 docs / 10,304 passages |
| `cv-sardinian` | texts | open | wired · manual | 1 docs / 5,237 passages |
| `salom` | texts | attribution | wired · manual | 1 docs / 10,685 passages |
| `aranese` | texts | attribution | wired · manual | 2 docs / 839,816 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 29 August 2026)</span>: `lat` 6,343 · `roa-opt` 1,682 · `spa` 1,216 · `cat` 967 · `osp` 684 · `la-vul` 233 · `fro` 222 · `por` 127 · `arg` 49 · `gmh` 11 … and 22 more (`nabu axis romance` lists all).

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the romance desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable romance               # first time: put this desk's shelves in this box's profile
nabu sync romance                 # fetch/refresh the desk's enabled members
nabu list --axis romance          # the shelf census, this desk only
nabu axis romance                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis romance   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search chevalier --lang fro      # Old French across BFM — Erec's chevalier at the head of the hits
nabu search ragusa --source croala    # Filelfo's 1470 Ragusaeis and Palmotić's carmina — Dubrovnik in Latin verse
nabu search --lemma miles --lang lat --axis romance  # lemma search on the desk's Latin — digilibLT answers at an honest [silver] tag; --gold-only narrows to the treebanks
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Who sang of Ragusa in Latin?”** → `nabu_search ragusa (lang: lat)` — Croatian Latin verse from the CroALa shelf (live-verified 2026-07-25): Filelfo's 1470 Ragusaeis (AFFECTUS RAGVSA TVAE CLARISSIMA LAVDI) and Palmotić's carmina — the medieval-Latin edge of the continuum, positionally cited (d1.d2.l198) for nabu_show.

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
