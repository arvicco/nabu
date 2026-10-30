---
title: "Baltic — The Balticist"
permalink: /axis/baltic/
description: >-
  The Balticist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Balticist — the Lutheran-print littoral, Mancelius' Latvian to Agricola's Finnish.

The early vernaculars of the eastern Baltic shore, where the Reformation and the Counter-Reformation first put Baltic and Finnic languages into print: SENIE's Old Latvian (1507–1800 — the catechisms, Mancelius, Glück's Bible, the manuscript dictionaries), with the Old Literary Finnish and the Old Lithuanian, Old Prussian and Old Estonian shelves joining as their packets land.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 30 October 2026)</span> |
|---|---|---|---|---|
| `senie` | texts | attribution | wired · manual | 183 docs / 48,995 passages |
| `vakk` | texts | nc | wired · manual | 3,052 docs / 148,875 passages |
| `vks` | texts | attribution | wired · manual | 128 docs / 65,311 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 30 October 2026)</span>: `et` 3,052 · `lv` 172 · `fi` 128 · `de` 10 · `lat` 1.

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the baltic desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable baltic               # first time: put this desk's shelves in this box's profile
nabu sync baltic                 # fetch/refresh the desk's enabled members
nabu list --axis baltic          # the shelf census, this desk only
nabu axis baltic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis baltic   # a query scoped to this desk's shelves
```

---

One of the [30 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
