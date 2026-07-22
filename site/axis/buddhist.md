---
title: "Buddhist — The Buddhologist"
permalink: /axis/buddhist/
description: >-
  The Buddhologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Buddhologist — the dharma across the Pali, Sanskrit and Chinese canons.

Cross-cutting by design: SuttaCentral, CBETA, SARIT, and GRETIL whole — membership is whole-source, so GRETIL rides here although only part of its shelf is Buddhist.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these four answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `gretil` | texts | nc | enabled · manual | 780 docs / 703,068 passages |
| `suttacentral` | texts | open | enabled · manual | 12,348 docs / 697,650 passages |
| `sarit` | texts | attribution | enabled · manual | 78 docs / 345,601 passages |
| `cbeta` | texts | nc | enabled · manual | 3,679 docs / 8,749,319 passages |

## The desk's instruments

- **Cross-canon by design:** SuttaCentral (the Pali canon and the Āgamas),
  SARIT, GRETIL whole (only part is Buddhist — the honest whole-source
  note), and CBETA (the Buddhist canon in Literary Chinese).
- Monier-Williams is reachable through the Indic overlap; no alignment work
  rides this desk.

## Working the buddhist desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis buddhist          # the shelf census, this desk only
nabu axis buddhist                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis buddhist   # a query scoped to this desk's shelves
nabu sync buddhist                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search --axis buddhist WORD      # one query across the Pali, Sanskrit and Chinese canons
nabu search dukkha --lang pli --axis buddhist  # the Pali canon
nabu search --lang lzh --axis buddhist WORD  # CBETA's Literary Chinese
nabu parallels CBETA-OR-SUTTACENTRAL-URN  # reception and echo across the canon
nabu vocab GRETIL-URN                 # a Buddhist text's vocabulary profile
```


## Terminal setup

- **Sanskrit / Pali (IAST):** **Noto Sans Mono**; Devanagari needs a
  conjunct-capable fallback (system default is fine).
- **CBETA Literary Chinese (lzh):** install the Noto CJK casks plus
  **Jigmo** for rare Ext-B+ Han, and keep iTerm2's "treat ambiguous-width
  as double-width" **off** to match nabu's narrow measurement.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
