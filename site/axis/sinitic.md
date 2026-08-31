---
title: "Sinitic — The Sinologist"
permalink: /axis/sinitic/
description: >-
  The Sinologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Sinologist — the classical Chinese written world and its phonological deep past.

Literary and classical Chinese with its reconstruction instruments: Kanripo and CBETA, TLS, Baxter-Sagart and the Qieyun-system database, Unihan, the Heian hanzi dictionaries, the UD lzh treebanks, SuttaCentral's Agamas, the kaikki zh extract riding wiktionary-recon — and, since P78-5, the Đại Việt classical shelf (the sinographic cosmopolis reaching Vietnam, as sillok reaches Korea).

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these seventeen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 31 August 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 76 docs / 325,533 passages |
| `wiktionary-recon` | dictionary | attribution | wired · manual | 30,261 entries |
| `suttacentral` | texts | open | wired · manual | 12,348 docs / 697,687 passages |
| `baxter-sagart` | dictionary | attribution | wired · manual | 9,918 entries |
| `tshet-uinh` | dictionary | open | wired · manual | 42,563 entries |
| `classical-modern` | texts | attribution | wired · manual | 14,608 docs / 1,944,934 passages |
| `menggu-ziyun` | dictionary | attribution | wired · manual | 9,446 entries |
| `zhongyuan` | dictionary | open | wired · manual | 5,877 entries |
| `qieyun-restored` | dictionary | attribution | wired · manual | 11,158 entries |
| `unihan` | dictionary | open | wired · manual | 102,998 entries |
| `hdic` | dictionary | attribution | wired · manual | 96,414 entries |
| `babelstone-ids` | dictionary | open | wired · manual | 97,680 entries |
| `cbeta` | texts | nc | wired · manual | 3,679 docs / 8,749,319 passages |
| `kanripo` | texts | attribution | wired · manual | 5,122 docs / 4,571,394 passages |
| `kr-gaiji` | feature module | attribution | wired · manual | nothing held yet |
| `tls` | dictionary | attribution | wired · manual | 23,179 entries |
| `viet-wikisource` | texts | attribution | wired · manual | 32 docs / 7,674 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 31 August 2026)</span>: `zho` 216,001 · `lzh` 80,220 · `ltc` 58,680 · `jpn` 32,607 · `och` 28,138 · `cmn` 7,304 · `pli` 7,288 · `sga` 6,566 · `gem-pro` 5,717 · `gmw-pro` 5,551 … and 29 more (`nabu axis sinitic` lists all).

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

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable sinitic               # first time: put this desk's shelves in this box's profile
nabu sync sinitic                 # fetch/refresh the desk's enabled members
nabu list --axis sinitic          # the shelf census, this desk only
nabu axis sinitic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis sinitic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu char 棄                           # the character card — strokes, radical, IDS, OC/MC, TLS senses
nabu search --char-component 木 --strokes 8-12  # component containment AND a total-stroke range
nabu search --radical 75 --axis sinitic  # the KangXi-radical filter on Han passages
nabu define 道 --long                  # TLS at the sense grain, with classical attestation
nabu show urn:nabu:kanripo:KR1h0004:001:1a --display reading  # gaiji &KR…; refs resolved to the real glyph or a placeholder
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Scan 仁義 usage across the Chinese canon.”** → `nabu_concord 仁義 (lang: lzh)` — KWIC rows in corpus order from CBETA's historiographical treatises — left context, keyword, right context in the pristine text.

## Terminal setup

- **Han (lzh, kanripo):** nabu measures CJK cells (`Nabu::Display.width`),
  so KWIC columns line up; `--display reading` resolves `&KR\d+;` gaiji.
- Install `font-noto-sans-cjk-sc`, `-tc` and `-jp` for the common
  ideographs, and **Jigmo** (covers every encoded Han) for the Extension-B+
  tail the kanripo shelf reaches. Keep iTerm2's "treat ambiguous-width as
  double-width" **off** to match nabu's narrow measurement.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
