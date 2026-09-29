---
title: "Turkic — The Turkologist"
permalink: /axis/turkic/
description: >-
  The Turkologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Turkologist — the runiform steppe to the Chagatai chancery, one literary continuum.

The Turkic historical lane, opening on ATMO's Jarring-collection Turki manuscripts (line-by-line TEI, Perso-Arabic with transliteration) and the kaikki Old Turkic / Old Uyghur / Chagatai extracts — the Wilkens Old Uyghur dictionary and the runiform inscriptions joining as their packets and asks land.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these four answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 29 September 2026)</span> |
|---|---|---|---|---|
| `atmo` | texts | attribution | wired · manual | 15 docs / 4,934 passages |
| `ud` | treebank | nc | wired · manual | 77 docs / 325,553 passages |
| `westoldturkic` | dictionary | attribution | wired · manual | 480 entries |
| `wiktionary-recon` | dictionary | attribution | wired · manual | 365,213 entries |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 29 September 2026)</span>: `zho` 327,296 · `sga` 6,690 · `gem-pro` 5,749 · `gmw-pro` 5,578 · `sla-pro` 5,461 · `mnc` 2,577 · `txb` 2,484 · `ine-pro` 1,928 · `wlm` 1,046 · `iir-pro` 800 … and 29 more (`nabu axis turkic` lists all).

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the turkic desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable turkic               # first time: put this desk's shelves in this box's profile
nabu sync turkic                 # fetch/refresh the desk's enabled members
nabu list --axis turkic          # the shelf census, this desk only
nabu axis turkic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis turkic   # a query scoped to this desk's shelves
```

---

One of the [27 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
