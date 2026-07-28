---
title: "Tibetan — The Tibetologist"
permalink: /axis/tibetan/
description: >-
  The Tibetologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Tibetologist — Dunhuang scrolls and pillar inscriptions to the translators' glossaries and their Sanskrit shadow.

The Tibetan lane, two-fronted while the canon shelves land: OTDO's 414 Old Tibetan critical editions — the Dunhuang manuscripts (Pelliot tibétain, IOL Tib J, Or.15000, Stein), the imperial pillar and rock inscriptions, and the five Old Zhangzhung texts — beside the dictionary shelves: the Mahāvyutpatti crosswalk glossary, the verb tense-stem database, and the kaikki bo extract.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these four answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 July 2026)</span> |
|---|---|---|---|---|
| `otdo` | texts | attribution | not yet wired | not synced yet |
| `mvp` | dictionary | open | not yet wired | not synced yet |
| `tibetan-verbs` | dictionary | open | not yet wired | not synced yet |
| `wiktionary-bo` | dictionary | attribution | not yet wired | not synced yet |

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
