---
title: "Japonic — The Japanologist"
permalink: /axis/japonic/
description: >-
  The Japanologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Japanologist — Old Japanese song to the Sino-Japanese dictionary tradition.

The Japanese lane: the ONCOJ corpus and lexicon, EDRDG's dictionaries, HDIC and Unihan shared with the Sinologist, and the kaikki ojp extract riding wiktionary-recon.

The desk spans two eras of Japanese. Old Japanese (ojp) is live now
through ONCOJ and its lexicon; the modern lane arrives with **Aozora
Bunko** (青空文庫, `enabled: false` pending the owner's first sync) — the
public-domain library at paragraph grain, ~17,488 works. Its scope is PD
text ONLY: discovery excludes the in-copyright works before any file is
touched. Ruby (振り仮名) readings ride as annotations over the base text,
never spliced into it; the 底本 colophon is carried as document metadata.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these eight answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 23 July 2026)</span> |
|---|---|---|---|---|
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `unihan` | dictionary | open | enabled · manual | 102,998 entries |
| `edrdg` | dictionary | attribution | enabled · manual | 231,129 entries |
| `hdic` | dictionary | attribution | enabled · manual | 96,414 entries |
| `kradfile` | dictionary | attribution | enabled · manual | 6,355 entries |
| `oncoj` | annotated corpus | attribution | enabled · frozen | 4,991 docs / 33,192 passages |
| `oncoj-lexicon` | dictionary | attribution | enabled · frozen | 5,869 entries |
| `aozora` | texts | open | enabled · manual | 17,121 docs / 2,983,332 passages |

## The desk's instruments

- **The Japanese lane:** the ONCOJ Old Japanese corpus and its lexicon,
  EDRDG's dictionaries (JMdict / KANJIDIC family — these feed `nabu char`'s
  kun/on readings and the Jōyō/JLPT/frequency lines), HDIC and Unihan
  shared with the Sinologist, KRADFILE's radical-component index, and the
  kaikki ojp extract on `wiktionary-recon`.
- **The kyūjitai↔shinjitai reform fold (P38-4 + P38-r1):** modern (`jpn`)
  search folds old-form, new-form and merged spellings onto one skeleton —
  matching modern reading habits, onto the SAME skeleton the Sinologist's
  Han fold uses, so Aozora and kanripo meet. Two lanes: the held Unihan
  kJinmeiyoKanji name-kanji pairs, PLUS a KANJIDIC2-jōyō lane (744 fold
  entries) that lands the high-frequency non-name pairs 學/学, 體/体, 醫/医,
  觀/観 and admits the famous merges (辨/瓣/辯 → 弁). `nabu search --exact`
  is the glyph-literal escape hatch when you need 弁 apart from 辨/瓣/辯.
  `nabu char` cross-references each authoritative jinmeiyō pair's
  kyūjitai/shinjitai (conventions §9).

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
nabu char 國                           # the reform cross-reference — a kyūjitai names its shinjitai 国
nabu search 学                         # folds to 學 (and 弁 finds 辨/瓣/辯) — modern reading habits across jpn/lzh
nabu search 弁 --exact                 # the glyph-literal escape hatch — only the stored 弁, not the merged olds
nabu search --char-component 木 --strokes 8-12  # KRADFILE component containment on the Han corpus
nabu search --radical 75 --axis japonic  # the KangXi-radical filter
nabu show urn:nabu:oncoj:MYS.1.1      # Man'yōshū 1.1 — romanization layer per ONCOJ's design
nabu search 吾輩は猫である --lang jpn        # Sōseki's opening line, top hit on the Aozora reading shelf
```


## Terminal setup

- **Kana / kanji (ojp):** ONCOJ carries romanization and original layers by
  its own design (man'yōgana rides the annotations, not the romanized KWIC).
  Install the Noto CJK casks plus **Jigmo**, and keep iTerm2's
  ambiguous-width toggle **off**. nabu models CJK cell width, so aligned
  columns stay aligned.
- **Gaiji (Aozora):** Aozora's not-yet-encoded characters
  resolve at parse — JIS X 0213 kuten and explicit `U+XXXX` notations map
  mechanically through `config/jis0213`; component-description-only
  notations stay verbatim loud sentinels. On the render side `--display
  reading` runs the four-rung gaiji ladder (faithful glyph → IDS
  composition → marked `⌈substitute⌉` → ⬚ box), and `--display diplomatic`
  keeps the refs byte-honest; the IDS rung, empty for kanripo, is live
  machinery here since Aozora's gaiji are largely IDS compositions
  (docs/display.md §1a).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
