---
title: "Tibetan — The Tibetologist"
permalink: /axis/tibetan/
description: >-
  The Tibetologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Tibetologist — Dunhuang's first histories to the classical canon, syllable by tagged syllable.

The Tibetan gold-annotation lane: the SOAS Classical Tibetan POS corpus (xct) and the Old Tibetan Annals and Chronicle with Dotson's aligned translation (otb), beside kaikki's bo extract riding wiktionary-recon.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these two answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 July 2026)</span> |
|---|---|---|---|---|
| `soas-tibetan` | texts | attribution | not yet wired | not synced yet |
| `old-tibetan` | texts | attribution | not yet wired | not synced yet |

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the tibetan desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable tibetan               # first time: put this desk's shelves in this box's profile
nabu sync tibetan                 # fetch/refresh the desk's enabled members
nabu list --axis tibetan          # the shelf census, this desk only
nabu axis tibetan                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis tibetan   # a query scoped to this desk's shelves
```

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
