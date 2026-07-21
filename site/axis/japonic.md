---
title: "Japonic — The Japanologist"
permalink: /axis/japonic/
description: >-
  The Japanologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Japanologist — Old Japanese song to the Sino-Japanese dictionary tradition.

The Japanese lane: the ONCOJ corpus and lexicon, EDRDG's dictionaries, HDIC and Unihan shared with the Sinologist, and the kaikki ojp extract riding wiktionary-recon.

## The shelves

A source wears every desk it serves — these eight answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 21 July 2026)</span> |
|---|---|---|---|---|
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `unihan` | dictionary | open | enabled · manual | 102,998 entries |
| `edrdg` | dictionary | attribution | enabled · manual | 231,106 entries |
| `hdic` | dictionary | attribution | enabled · manual | 96,414 entries |
| `kradfile` | dictionary | attribution | not enabled | 6,355 entries |
| `oncoj` | annotated corpus | attribution | enabled · frozen | 4,991 docs / 33,192 passages |
| `oncoj-lexicon` | dictionary | attribution | enabled · frozen | 5,869 entries |
| `aozora` | texts | open | not enabled | not synced yet |

## The desk's instruments

- **The Japanese lane:** the ONCOJ Old Japanese corpus and its lexicon,
  EDRDG's dictionaries (JMdict / KANJIDIC family — these feed `nabu char`'s
  kun/on readings and the Jōyō/JLPT/frequency lines), HDIC and Unihan
  shared with the Sinologist, KRADFILE's radical-component index, and the
  kaikki ojp extract on `wiktionary-recon`.

## Working the japonic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis japonic          # the shelf census, this desk only
nabu axis japonic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis japonic   # a query scoped to this desk's shelves
nabu sync japonic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu char 天                           # the character card, with KANJIDIC2 readings and desk codes
nabu search --char-component 木 --strokes 8-12  # KRADFILE component containment on the Han corpus
nabu search --radical 75 --axis japonic  # the KangXi-radical filter
nabu show ONCOJ-URN                   # Old Japanese — romanization and original layers per ONCOJ's design
```


## Terminal setup

- **Kana / kanji (ojp):** ONCOJ carries romanization and original layers by
  its own design (man'yōgana rides the annotations, not the romanized KWIC).
  Install the Noto CJK casks plus **Jigmo**, and keep iTerm2's
  ambiguous-width toggle **off**. nabu models CJK cell width, so aligned
  columns stay aligned.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
