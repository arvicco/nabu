---
title: "Syriac — The Syriacist"
permalink: /axis/syriac/
description: >-
  The Syriacist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Syriacist — the Peshitta and the estrangela bookshelf.

The Syriac language desk: the ETCBC Peshitta and the Digital Syriac Corpus, riding beside the biblical hat by design.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these two answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 9 August 2026)</span> |
|---|---|---|---|---|
| `peshitta` | texts | nc | wired · manual | 65 docs / 31,341 passages |
| `syriac-corpus` | texts | attribution | wired · manual | 632 docs / 134,726 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 9 August 2026)</span>: `syc` 697.

## The desk's instruments

- **The Syriac language desk:** the ETCBC Peshitta (Leiden VTS / Codex
  Ambrosianus, by book node) and the Digital Syriac Corpus — a millennium
  of Syriac beside the biblical hat.
- **Alignment works:** `ot` and `psalms` carry the Peshitta as the Syriac
  leg (`urn:nabu:peshitta:<siglum>`).

## Working the syriac desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable syriac               # first time: put this desk's shelves in this box's profile
nabu sync syriac                 # fetch/refresh the desk's enabled members
nabu list --axis syriac          # the shelf census, this desk only
nabu axis syriac                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis syriac   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu align "GEN 1.1"                  # the Peshitta as one leg of the Old Testament hub
nabu align "PSA 22.1"                 # the Peshitta psalter, Masoretic-numbered and remapped
nabu show urn:nabu:peshitta:gn        # a Peshitta book document
nabu cognates ot --langs syriac,hbo   # Syriac against Hebrew, same-root verses
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“ܡܠܟܘܬܐ in the Syriac corpus?”** → `nabu_search ܡܠܟܘܬܐ (lang: syc)` — The Peshitta Mark ("a kingdom divided against itself…") beside homiletic prose from the Digital Syriac Corpus — vocalized and unvocalized spellings fold together.

## Terminal setup

- **Syriac (estrangela) is RTL** — the same terminal requirement as Hebrew:
  the iTerm2 ≥ 3.6.0 RTL toggle on (Terminal.app cannot). display.md names
  no dedicated Syriac font; use a Unicode font with Syriac coverage in the
  fallback cascade (Noto Sans Mono is the general recommendation).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
