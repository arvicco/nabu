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

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 23 July 2026)</span> |
|---|---|---|---|---|
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `isicily` | inscriptions | attribution | enabled · manual | 6,664 docs / 16,996 passages |
| `itant` | inscriptions | nc | enabled · manual | 1,160 docs / 1,283 passages |
| `sabellic-loans` | dictionary | attribution | enabled · frozen | 85 entries |
| `ceipom` | inscriptions | attribution | enabled · frozen | 3,871 docs / 5,303 passages |
| `open-etruscan` | inscriptions | attribution | enabled · frozen | 8,047 docs / 8,047 passages |
| `larth-etp` | dictionary | attribution | enabled · manual | 1,122 entries |
| `lexlep` | inscriptions | nc | enabled · manual | 494 docs / 570 passages |
| `lexlep-words` | dictionary | nc | enabled · manual | 627 entries |
| `tir` | inscriptions | nc | enabled · manual | 389 docs / 434 passages |

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

The generic axis surfaces — every desk answers to these:

```
nabu list --axis italic          # the shelf census, this desk only
nabu axis italic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis italic   # a query scoped to this desk's shelves
nabu sync italic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search --lemma precor --axis italic  # the CEIPoM equivalence key onto the Iguvine Tables
nabu etym rufus                       # the Sabellic-loan etymon chain (Old Italic headwords)
nabu search tular --axis italic       # the Etruscan boundary stones — tular raśnal
nabu define "*deiwos"                 # a Proto-Italic reconstruction, with its attested reflexes
```


## Terminal setup

- **Old Italic (osc/xum):** the inscription text is stored in Latin
  transliteration (the language tags, e.g. `osc-Ital-x-oscetr`, name the
  alphabet). The U+10300 block itself appears only in the sabellic-loans
  etymon headwords (𐌓𐌖𐌚𐌓𐌉𐌉𐌔) — install `font-noto-sans-old-italic` to
  read those.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
