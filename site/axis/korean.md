---
title: "Korean — The Koreanist"
permalink: /axis/korean/
description: >-
  The Koreanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Koreanist — the hanmun state record and the first hangul vernacular.

The Korean desk opens on the dynastic record itself: the Veritable Records of Joseon (sillok) in the original hanmun via NIKH's open XML dumps, with the Seungjeongwon ilgi, the Goryeosa family and the ITKC classics to follow on the same DTD, and the Middle Korean Wikisource shelf as the vernacular leg.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

The single shelf below answers this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 18 August 2026)</span> |
|---|---|---|---|---|
| `sillok` | texts | attribution | not yet wired | not synced yet |

**Languages on this desk** — nothing held yet.

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
