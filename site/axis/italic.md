---
title: "Italic — The Italicist"
permalink: /axis/italic/
description: >-
  The Italicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Italicist — the languages of pre-Roman Italy, Oscan to Etruscan to Raetic.

The Sabellic, Etruscan, Venetic and Raetic epigraphic shelves (CEIPoM, ItAnt, the Etruscan editions, TIR), Lepontic at the Celtic border, I.Sicily's island mix, and the Sabellic-to-Latin loan lane.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these ten answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 12 August 2026)</span> |
|---|---|---|---|---|
| `wiktionary-recon` | dictionary | attribution | wired · manual | 30,261 entries |
| `isicily` | inscriptions | attribution | wired · manual | 6,723 docs / 17,921 passages |
| `itant` | inscriptions | nc | wired · manual | 1,160 docs / 1,283 passages |
| `sabellic-loans` | dictionary | attribution | wired · frozen | 85 entries |
| `ceipom` | inscriptions | attribution | wired · frozen | 3,871 docs / 5,303 passages |
| `open-etruscan` | inscriptions | attribution | wired · frozen | 8,047 docs / 8,047 passages |
| `larth-etp` | dictionary | attribution | wired · manual | 1,122 entries |
| `lexlep` | inscriptions | nc | wired · manual | 494 docs / 570 passages |
| `lexlep-words` | dictionary | nc | wired · manual | 627 entries |
| `tir` | inscriptions | nc | wired · manual | 389 docs / 434 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 12 August 2026)</span>: `ett` 7,874 · `sga` 6,564 · `gem-pro` 5,717 · `gmw-pro` 5,551 · `sla-pro` 5,431 · `eng` 3,290 · `grc` 3,201 · `lat` 2,662 · `ine-pro` 1,905 · `osc` 954 … and 24 more (`nabu axis italic` lists all).

## The desk's instruments

- **The languages of pre-Roman Italy:** Sabellic — Oscan, Umbrian,
  Faliscan (CEIPoM), Etruscan (open-etruscan, larth-etp), Venetic and
  Raetic (TIR, ItAnt), Lepontic at the Celtic border, I.Sicily's island mix.
- **The equivalence tier:** CEIPoM's scholar-curated Classical-Latin keys
  sit on the pre-Roman passages — `search --lemma precor` reaches the
  Iguvine Tables' `pesnimu`, tagged `[equivalence]` (never counted as
  attestation; `--gold-only` excludes it).
- **Etymology:** the Sabellic-to-Latin loan lane (`sabellic-loans`) and the
  Proto-Italic reconstructions reachable through `nabu etym`.

## Working the italic desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable italic               # first time: put this desk's shelves in this box's profile
nabu sync italic                 # fetch/refresh the desk's enabled members
nabu list --axis italic          # the shelf census, this desk only
nabu axis italic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis italic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search --lemma precor --axis italic  # the CEIPoM equivalence key onto the Iguvine Tables
nabu etym rufus                       # the Sabellic-loan etymon chain (Old Italic headwords)
nabu search tular --axis italic       # the Etruscan boundary stones — tular raśnal
nabu define "*deiwos"                 # a Proto-Italic reconstruction, with its attested reflexes
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Etruscan inscriptions naming Larth?”** → `nabu_search larth (lang: ett)` — CIE 1772 with both faces of the stone transcribed — the Tyrsenian shelves answer alongside the Sabellic ones on this desk.

## Terminal setup

- **Old Italic (osc/xum):** the inscription text is stored in Latin
  transliteration (the language tags, e.g. `osc-Ital-x-oscetr`, name the
  alphabet). The U+10300 block itself appears only in the sabellic-loans
  etymon headwords (𐌓𐌖𐌚𐌓𐌉𐌉𐌔) — install `font-noto-sans-old-italic` to
  read those.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
