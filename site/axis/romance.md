---
title: "Romance — The Romanist"
permalink: /axis/romance/
description: >-
  The Romanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Romanist — the Latin-to-vernacular continuum, charter Latin to Roland to the troubadours.

The Latin-to-vernacular continuum: CroALa's medieval and neo-Latin opens the desk; late-antique prose, the MGH critical editions, and the Old French treebanks and texts join as their shelves land.

The desk opens with **CroALa** (`croala`) — Croatian Latin from a 976 CE
charter through the neo-Latin centuries, the continuum's Latin side
(dual-tagged with `classical`). The vernacular side — Old French
treebanks and texts, the late-antique band, the MGH critical editions —
is landing shelf by shelf.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these five answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 25 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 73 docs / 322,114 passages |
| `croala` | texts | attribution | wired · manual | 570 docs / 309,180 passages |
| `digiliblt` | texts | attribution | wired · manual | 372 docs / 459,451 passages |
| `openmgh` | texts | attribution | wired · manual | 57 docs / 9,594 passages |
| `bfm` | texts | attribution | wired · manual | 219 docs / 333,819 passages |

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the romance desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis romance          # the shelf census, this desk only
nabu axis romance                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis romance   # a query scoped to this desk's shelves
nabu sync romance                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search ragusa --source croala    # Filelfo's 1470 Ragusaeis and Palmotić's carmina — Dubrovnik in Latin verse
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Who sang of Ragusa in Latin?”** → `nabu_search ragusa (lang: lat)` — Croatian Latin verse from the CroALa shelf (live-verified 2026-07-25): Filelfo's 1470 Ragusaeis (AFFECTUS RAGVSA TVAE CLARISSIMA LAVDI) and Palmotić's carmina — the medieval-Latin edge of the continuum, positionally cited (d1.d2.l198) for nabu_show.
---

One of the [twenty-one research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
