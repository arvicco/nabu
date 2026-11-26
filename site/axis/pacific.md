---
title: "Pacific — The Pacific philologist"
permalink: /axis/pacific/
description: >-
  The Pacific philologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Pacific philologist — the Polynesian languages in their first prints, the Māori press to the mission Bibles.

The languages of the Pacific in their own historical texts, opening on the Niupepa collection: the Māori-language newspapers of 1842–1932 at the page grain, with the island print shelves joining as their packets land.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 26 November 2026)</span> |
|---|---|---|---|---|
| `ceipp-rongorongo` | texts | nc | wired · manual | 25 docs / 314 passages |
| `ebible-pacific` | texts | open | wired · manual | 100 docs / 48,762 passages |
| `niupepa` | texts | research_private | wired · manual | 1,465 docs / 14,816 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 26 November 2026)</span>: `mri` 1,465 · `haw` 66 · `pon` 28 · `rap` 25 · `cha` 6.

## The desk's instruments

No desk-specific instruments curated yet — the generic surfaces above apply.

## Working the pacific desk

The generic desk surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable pacific               # first time: put this desk's shelves in this box's profile
nabu sync pacific                 # fetch/refresh the desk's enabled members
nabu list --axis pacific          # the shelf census, this desk only
nabu axis pacific                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis pacific   # a query scoped to this desk's shelves
```

---

One of the [31 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
