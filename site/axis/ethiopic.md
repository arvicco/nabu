---
title: "Ethiopic — The Ethiopicist"
permalink: /axis/ethiopic/
description: >-
  The Ethiopicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Ethiopicist — Aksum to the scriptoria: Enoch, Jubilees, and the Geʿez Bible.

The Ethiopic (Gǝʿǝz) desk in the Oriental-Christian neighborhood: the Beta maṣāḥǝft transcriptions (the Geʿez Bible, 1 Enoch, Jubilees, the Kebra nagast, royal chronicles), Dillmann's Lexicon, and the TraCES analyzed corpus with its Aksumite inscriptions — riding beside the biblical hat by design.

The desk opens with the **Beta maṣāḥǝft Works** transcriptions
(Hamburg): the Geʿez Bible at verse grain — near-complete OT, all four
Gospels — beside **1 Enoch** and **Jubilees**, books that survive
complete *only* in Geʿez, the *Kebra Nagast*, and the royal chronicles.
**Dillmann's Lexicon** (13,727 entries) and the **TraCES** analyzed
corpus (75,440 morph-annotated tokens, lemma-linked into Dillmann's
entries) complete the trio as their syncs land.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these three answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 July 2026)</span> |
|---|---|---|---|---|
| `betamasaheft-works` | texts | attribution | wired · manual | 3,796 docs / 66,516 passages |
| `dillmann` | dictionary | nc | wired · manual | 13,727 entries |
| `traces` | texts | nc | wired · manual | 15 docs / 75,436 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 28 July 2026)</span>: `gez` 17,516 · `amh` 22.

## The desk's instruments

- **Verse-grain citations:** the Works TEI carries upstream verse
  numbering, so `urn:nabu:betamasaheft-works:LIT2711Mark:1.1` is Mark
  1:1, citable and shown with its per-document transcription credit.
- **The dictionary crosswalk:** TraCES tokens carry `lex` links into
  Dillmann entry ids — lemma to lexicon in one ecosystem (both shelves
  `nc`-classed, held locally, MCP-excluded).

## Working the ethiopic desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable ethiopic               # first time: put this desk's shelves in this box's profile
nabu sync ethiopic                 # fetch/refresh the desk's enabled members
nabu list --axis ethiopic          # the shelf census, this desk only
nabu axis ethiopic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis ethiopic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu show urn:nabu:betamasaheft-works:LIT2711Mark:1.1  # Mark 1:1 in Geʿez — ቀዳሚሁ፡ ለወንጌለ፡ …
nabu search ወንጌል --lang gez           # the word 'gospel' across the Geʿez shelf, fold-aware
```

## Terminal setup

- **Ethiopic script (gez):** fidäl needs a font with Ethiopic coverage —
  install `font-noto-sans-ethiopic` (or fill the terminal's non-ASCII
  slot with a Noto face). The script is NFC-stable; nabu stores it
  byte-faithful with its explicit word dividers (፡) intact.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
