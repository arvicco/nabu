---
title: "Americas — The Americanist"
permalink: /axis/americas/
description: >-
  The Americanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Americanist — the colonial record of the indigenous Americas, Zapotec testaments to the Andean chronicle.

The indigenous-Americas lane, colonial-era first: Ticha's Valley Zapotec TEI (Córdova's 1578 Arte, Agüero's 1666 Miscelaneo, the testaments and their period Spanish translations), the Royal Danish Library's Guaman Poma Nueva corónica (Spanish with Quechua and Aymara passages), and the UD Tupinambá and Old Guaraní treebanks of the Jesuit grammars and catechisms — the modern UD treebanks of American languages deliberately out.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 30 October 2026)</span> |
|---|---|---|---|---|
| `guaman-poma` | texts | open | wired · manual | 1,189 docs / 5,911 passages |
| `ticha` | texts | attribution | wired · manual | 93 docs / 1,103 passages |
| `ud` | treebank | nc | wired · manual | 83 docs / 329,980 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 30 October 2026)</span>: `spa` 1,280 · `lat` 11 · `grc` 9 · `orv` 9 · `ota` 5 · `lzh` 4 · `cop` 3 · `egy` 3 · `frm` 3 · `fro` 3 … and 17 more (`nabu axis americas` lists all).

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the americas desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable americas               # first time: put this desk's shelves in this box's profile
nabu sync americas                 # fetch/refresh the desk's enabled members
nabu list --axis americas          # the shelf census, this desk only
nabu axis americas                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis americas   # a query scoped to this desk's shelves
```

---

One of the [30 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
