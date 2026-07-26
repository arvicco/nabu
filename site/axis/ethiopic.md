---
title: "Ethiopic — The Ethiopicist"
permalink: /axis/ethiopic/
description: >-
  The Ethiopicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Ethiopicist — Aksum to the scriptoria: Enoch, Jubilees, and the Geʿez Bible.

The Ethiopic (Gǝʿǝz) desk in the Oriental-Christian neighborhood: the Beta maṣāḥǝft transcriptions (the Geʿez Bible, 1 Enoch, Jubilees, the Kebra nagast, royal chronicles), Dillmann's Lexicon, and the TraCES analyzed corpus with its Aksumite inscriptions — riding beside the biblical hat by design.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 26 July 2026)</span> |
|---|---|---|---|---|
| `betamasaheft-works` | texts | attribution | not yet wired | not synced yet |
| `dillmann` | dictionary | nc | not yet wired | not synced yet |
| `traces` | texts | nc | not yet wired | not synced yet |

## The desk's instruments

No axis-specific instruments curated yet — the generic surfaces above apply.

## Working the ethiopic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis ethiopic          # the shelf census, this desk only
nabu axis ethiopic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis ethiopic   # a query scoped to this desk's shelves
nabu sync ethiopic                 # sync the desk's enabled members
```

---

One of the [twenty-two research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
