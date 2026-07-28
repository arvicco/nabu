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

A source wears every desk it serves — these six answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 July 2026)</span> |
|---|---|---|---|---|
| `gretil` | texts | nc | wired · manual | 780 docs / 703,068 passages |
| `suttacentral` | texts | open | wired · manual | 12,348 docs / 697,650 passages |
| `sarit` | texts | attribution | wired · manual | 78 docs / 345,601 passages |
| `cbeta` | texts | nc | wired · manual | 3,679 docs / 8,749,319 passages |
| `e84000` | texts | nc | not yet wired | not synced yet |
| `mvp` | dictionary | open | not yet wired | not synced yet |

## The desk's instruments

- **Cross-canon by design:** SuttaCentral (the Pali canon and the Āgamas),
  SARIT, GRETIL whole (only part is Buddhist — the honest whole-source
  note), and CBETA (the Buddhist canon in Literary Chinese).
- Monier-Williams is reachable through the Indic overlap; no alignment work
  rides this desk.

## Working the buddhist desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable buddhist               # first time: put this desk's shelves in this box's profile
nabu sync buddhist                 # fetch/refresh the desk's enabled members
nabu list --axis buddhist          # the shelf census, this desk only
nabu axis buddhist                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis buddhist   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search dharma --axis buddhist    # one query across the Pali, Sanskrit and Chinese canons
nabu search dukkha --lang pli --axis buddhist  # the Pali canon
nabu search 涅槃 --lang lzh --axis buddhist  # CBETA's Literary Chinese — nirvāṇa in the Taishō
nabu parallels urn:nabu:suttacentral:an1.11-20:an1.11:1.1  # reception and echo across the canon — the AN refrain found in SN
nabu formulas urn:nabu:suttacentral:an1 --lang pli  # the repeated formulas of the Aṅguttara, mined from the Pali lane
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“What are the Chinese parallels to the Saccavibhaṅga Sutta?”** → `nabu_links urn:nabu:suttacentral:mn141` — SuttaCentral's curated parallels as edges: MN 141 ↔ 中阿含經 31 (分別聖諦經, the Madhyama Āgama parallel, lzh) plus DN 22 and two Ekottara Āgama parallels — cross-canon navigation in one call.

## Terminal setup

- **Sanskrit / Pali (IAST):** **Noto Sans Mono**; Devanagari needs a
  conjunct-capable fallback (system default is fine).
- **CBETA Literary Chinese (lzh):** install the Noto CJK casks plus
  **Jigmo** for rare Ext-B+ Han, and keep iTerm2's "treat ambiguous-width
  as double-width" **off** to match nabu's narrow measurement.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
