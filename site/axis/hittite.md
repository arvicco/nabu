---
title: "Hittite — The Hittitologist"
permalink: /axis/hittite/
description: >-
  The Hittitologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Hittitologist — Anatolia in cuneiform, KBo and KUB by tablet and line.

The Hittite desk: TLHdig's tablet corpus (dual-tagged cuneiform by ruling — its lines also carry Akkadian, Sumerian, Luwian, Hattic, Hurrian) and the UD Hittite treebank.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these two answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 18 August 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 76 docs / 325,533 passages |
| `tlhdig` | tablets | attribution | wired · manual | 23,486 docs / 402,195 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 18 August 2026)</span>: `hit` 21,210 · `akk` 936 · `xhu` 698 · `xht` 326 · `xlu` 206 · `sux` 80 · `plq` 30 · `lat` 11 · `grc` 9 · `orv` 9 … and 15 more (`nabu axis hittite` lists all).

## The desk's instruments

- **The Hittite desk:** TLHdig's tablet corpus (KBo and KUB by tablet and
  line — dual-tagged cuneiform, its lines also carrying Akkadian, Sumerian,
  Luwian, Hattic and Hurrian) and the UD Hittite treebank (gold `hit`).
- No dictionary shelf or alignment work rides this desk yet.

## Working the hittite desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable hittite               # first time: put this desk's shelves in this box's profile
nabu sync hittite                 # fetch/refresh the desk's enabled members
nabu list --axis hittite          # the shelf census, this desk only
nabu axis hittite                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis hittite   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search --lemma kuiš --lang hit --axis hittite  # the gold UD Hittite morphology (kuiš "who", clause by clause)
nabu show --random --source tlhdig    # pull a random tablet manuscript off the Hittite shelf
nabu search ḫatti --axis hittite      # a query across TLHdig and the treebank — Ḫatti on the tablets
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Find nepišaš — 'of heaven' — in the tablets.”** → `nabu_search "ne-pi-ša-aš" (lang: hit)` — Mythological fragments (KBo 26.91, KBo 26.120) with damage brackets preserved. The desk's lesson: TLHdig stores the syllabified transliteration, so type it hyphenated — the diacritic fold maps pí to pi for you.

## Terminal setup

- **TLHdig tablets** are stored in Latin transliteration, so no cuneiform
  font is needed. No RTL or CJK concerns. Note: TLHdig is not in the
  `--fuzzy` index — use plain `search --axis hittite`.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
