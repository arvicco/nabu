---
title: "Africa — The Africanist"
permalink: /axis/africa/
description: >-
  The Africanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Africanist — Ajami manuscripts beyond the Nile–Ethiopia axis, Hausa praise poems to Wolof Murid verse.

Africa beyond the Egyptian and Ethiopic desks: the NEH Ajami collection's Hausa, Mandinka, Fula and Wolof manuscripts in romanized transcription, the public-domain reference shelf in archive.org's uncorrected OCR — Griffith's Old Nubian texts, the Swahili of Steere, Taylor, Büttner and Velten, Schön's and Robinson's Hausa, Hanoteau's Tuareg grammar and Kabyle poetry, Koelle's Vai — and the Old Nubian UD treebank, the medieval Nile kingdoms' language parsed word by word.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 18 October 2026)</span> |
|---|---|---|---|---|
| `africa-pd` | texts | open | wired · manual | 10 docs / 3,536 passages |
| `bu-ajami` | texts | nc | wired · manual | 80 docs / 705 passages |
| `old-nubian-ud` | texts | nc | wired · manual | 1 docs / 124 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 18 October 2026)</span>: `fuf` 20 · `ha` 20 · `mnk` 20 · `wo` 20 · `eng` 6 · `fra` 2 · `deu` 1 · `onw` 1 · `sw` 1.

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the africa desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable africa               # first time: put this desk's shelves in this box's profile
nabu sync africa                 # fetch/refresh the desk's enabled members
nabu list --axis africa          # the shelf census, this desk only
nabu axis africa                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis africa   # a query scoped to this desk's shelves
```

---

One of the [29 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
