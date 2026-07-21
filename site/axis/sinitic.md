---
title: "Sinitic — The Sinologist"
permalink: /axis/sinitic/
description: >-
  The Sinologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Sinologist — the classical Chinese written world and its phonological deep past.

Literary and classical Chinese with its reconstruction instruments: Kanripo and CBETA, TLS, Baxter-Sagart and the Qieyun-system database, Unihan, the Heian hanzi dictionaries, the UD lzh treebanks, SuttaCentral's Agamas, and the kaikki zh extract riding wiktionary-recon.

## The shelves

A source wears every desk it serves — these twelve answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 29 docs / 107,664 passages |
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `suttacentral` | texts | open | enabled · manual | 12,348 docs / 697,650 passages |
| `baxter-sagart` | dictionary | attribution | enabled · manual | 9,918 entries |
| `tshet-uinh` | dictionary | open | enabled · manual | 25,336 entries |
| `unihan` | dictionary | open | enabled · manual | 102,998 entries |
| `hdic` | dictionary | attribution | enabled · manual | 96,414 entries |
| `babelstone-ids` | dictionary | open | enabled · manual | 97,680 entries |
| `cbeta` | texts | nc | enabled · manual | 3,679 docs / 8,749,319 passages |
| `kanripo` | texts | attribution | enabled · manual | 5,028 docs / 4,436,181 passages |
| `kr-gaiji` | texts | attribution | not enabled | nothing held yet |
| `tls` | dictionary | attribution | enabled · manual | 23,179 entries |

## The desk's instruments

- **Literary and classical Chinese with its phonology:** Kanripo (the
  largest single shelf) and CBETA, the UD lzh treebanks, SuttaCentral's
  Āgamas, and the kaikki zh extract on `wiktionary-recon`.
- **The reconstruction instruments:** Baxter-Sagart Old Chinese
  (`baxter-sagart`), the Qieyun-system Middle Chinese database
  (`tshet-uinh`), Unihan, the Heian hanzi dictionaries (`hdic`, held),
  BabelStone IDS decomposition, and TLS at the sense grain.
- **The character desk:** `nabu char` joins every shelf onto one glyph, and
  `search --radical/--strokes/--char-component` filters the Han corpus.

## Working the sinitic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis sinitic          # the shelf census, this desk only
nabu axis sinitic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis sinitic   # a query scoped to this desk's shelves
nabu sync sinitic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu char 棄                           # the character card — strokes, radical, IDS, OC/MC, TLS senses
nabu search --char-component 木 --strokes 8-12  # component containment AND a total-stroke range
nabu search --radical 75 --axis sinitic  # the KangXi-radical filter on Han passages
nabu define 道 --long                  # TLS at the sense grain, with classical attestation
nabu show urn:nabu:kanripo:KR1h0004:001:1a --display reading  # gaiji &KR…; refs resolved to the real glyph or a placeholder
```


## Terminal setup

- **Han (lzh, kanripo):** nabu measures CJK cells (`Nabu::Display.width`),
  so KWIC columns line up; `--display reading` resolves `&KR\d+;` gaiji.
- Install `font-noto-sans-cjk-sc`, `-tc` and `-jp` for the common
  ideographs, and **Jigmo** (covers every encoded Han) for the Extension-B+
  tail the kanripo shelf reaches. Keep iTerm2's "treat ambiguous-width as
  double-width" **off** to match nabu's narrow measurement.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
