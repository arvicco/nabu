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

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 36 docs / 238,032 passages |
| `tlhdig` | tablets | attribution | enabled · manual | 23,486 docs / 402,195 passages |

## The desk's instruments

- **The Hittite desk:** TLHdig's tablet corpus (KBo and KUB by tablet and
  line — dual-tagged cuneiform, its lines also carrying Akkadian, Sumerian,
  Luwian, Hattic and Hurrian) and the UD Hittite treebank (gold `hit`).
- No dictionary shelf or alignment work rides this desk yet.

## Working the hittite desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis hittite          # the shelf census, this desk only
nabu axis hittite                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis hittite   # a query scoped to this desk's shelves
nabu sync hittite                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search --lemma kuiš --lang hit --axis hittite  # the gold UD Hittite morphology (kuiš "who", clause by clause)
nabu search --century -13 --axis hittite  # the tablets by date, where dated
nabu search ḫatti --axis hittite      # a query across TLHdig and the treebank — Ḫatti on the tablets
```


## Terminal setup

- **TLHdig tablets** are stored in Latin transliteration, so no cuneiform
  font is needed. No RTL or CJK concerns. Note: TLHdig is not in the
  `--fuzzy` index — use plain `search --axis hittite`.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
