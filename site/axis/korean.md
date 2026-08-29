---
title: "Korean — The Koreanist"
permalink: /axis/korean/
description: >-
  The Koreanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Koreanist — the hanmun state record and the first hangul vernacular.

The Korean desk opens on the dynastic record itself: the Veritable Records of Joseon (sillok) in the original hanmun via NIKH's open XML dumps, joined by the Goryeosa family on the same DTD (the pre-Joseon dynastic history, its chronological digest, and the state council's daily register), with the Seungjeongwon ilgi and the ITKC classics to follow, and the Middle Korean Wikisource shelf as the vernacular leg.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these seven answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 29 August 2026)</span> |
|---|---|---|---|---|
| `sillok` | texts | attribution | wired · manual | 743 docs / 414,321 passages |
| `sjw` | texts | attribution | wired · manual | 297 docs / 1,896,858 passages |
| `ko-wikisource-mk` | texts | attribution | wired · manual | 1 docs / 159 passages |
| `goryeosa` | texts | attribution | wired · manual | 138 docs / 31,207 passages |
| `goryeosa-jeoryo` | texts | attribution | wired · manual | 36 docs / 11,226 passages |
| `bibyeonsa` | texts | attribution | wired · manual | 273 docs / 93,528 passages |
| `itkc` | texts | attribution | wired · manual | 473 docs / 13,185 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 29 August 2026)</span>: `lzh` 1,960 · `okm` 1.

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the korean desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable korean               # first time: put this desk's shelves in this box's profile
nabu sync korean                 # fetch/refresh the desk's enabled members
nabu list --axis korean          # the shelf census, this desk only
nabu axis korean                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis korean   # a query scoped to this desk's shelves
```

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
