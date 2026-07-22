---
title: "Biblical — The Biblical scholar"
permalink: /axis/biblical/
description: >-
  The Biblical scholar's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Biblical scholar — one text across Hebrew, Greek, Latin, Syriac, Coptic and English witnesses.

The cross-language scripture hat: the Masoretic shelves and the Scrolls, the Greek NT, Vulgate and WEB, Peshitta and the Syriac corpus, Coptic Scriptorium, the Targums, and the OSHB-BHSA bridging module. The hebrew and syriac language desks coexist with this hat by design.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these thirteen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `vulgate` | texts | open | enabled · manual | 73 docs / 35,809 passages |
| `eng-web` | texts | open | enabled · manual | 84 docs / 37,624 passages |
| `sblgnt` | texts | attribution | enabled · manual | 27 docs / 7,939 passages |
| `coptic-scriptorium` | texts | nc | enabled · manual | 482 docs / 74,169 passages |
| `oshb` | texts | open | enabled · manual | 39 docs / 23,213 passages |
| `sdbh` | dictionary | attribution | enabled · manual | 7,932 entries |
| `sefaria` | texts | open | enabled · manual | 103 docs / 57,095 passages |
| `bhsa` | texts | nc | enabled · manual | 39 docs / 23,213 passages |
| `bridging` | crosswalk module | attribution | not enabled | nothing held yet |
| `dss` | texts | nc | enabled · manual | 1,001 docs / 52,895 passages |
| `hebrew-lexicon` | dictionary | attribution | enabled · manual | 21,144 entries |
| `peshitta` | texts | nc | enabled · manual | 65 docs / 31,341 passages |
| `syriac-corpus` | texts | attribution | enabled · manual | 632 docs / 134,726 passages |

## The desk's instruments

- **Every alignment work at once.** `nt`: SBLGNT (grc), the Vulgate (lat),
  WEB (eng), Coptic Scriptorium (Sahidic and Bohairic cop). `ot` and
  `psalms`: OSHB and BHSA (hbo Masoretic), the Sefaria Targum (arc), the
  Peshitta (syriac), the LXX and the Vulgate, WEB — `psalms` carries the
  LXX↔Masoretic renumbering.
- **Dictionaries:** the Hebrew lexicon (`hebrew-lexicon`) and the Semantic
  Dictionary of Biblical Hebrew (`sdbh`).
- **The contact facet:** Coptic Scriptorium is the `--loans` shelf —
  `search --loans grc` keeps only passages carrying Greek loanwords.

## Working the biblical desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis biblical          # the shelf census, this desk only
nabu axis biblical                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis biblical   # a query scoped to this desk's shelves
nabu sync biblical                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu align "MARK 2.3"                 # the New Testament verse across up to fifteen witnesses
nabu align "GEN 1.1"                  # Masoretic, LXX, Vulgate, WEB, Targum and Peshitta together
nabu align "PSA 22.1"                 # the Greek psalm number, remapped to the Masoretic witnesses
nabu search ⲛⲟⲩⲧⲉ --lang cop --loans grc  # Coptic passages that carry a Greek loanword
nabu cognates ot --langs hbo,syriac   # same-root verses, Hebrew against Syriac
nabu list coptic-scriptorium --loans  # the donor-language census of the loan tags
```


## Terminal setup

- **Hebrew and Aramaic (hbo/arc):** nabu strips cantillation, keeps the
  points and maqaf, and wraps runs in RTL isolates. The terminal must do
  the bidi: **iTerm2 ≥ 3.6.0** has an experimental RTL toggle (Settings →
  General → Experimental); **Terminal.app has no bidi at all**. Use **Ezra
  SIL** or **SBL Hebrew** in a dedicated iTerm2 profile (Ezra SIL at +4pt),
  or **Noto Sans Mono** in the non-ASCII slot at the ASCII size.
- **Syriac (Peshitta):** also RTL — the same iTerm2 toggle.
- **Coptic:** install `font-noto-sans-coptic`.
- On a bidi-less terminal, `--display translit` gives the most legible view
  (SBL-style LTR romanization via `Nabu::Hebr`).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
