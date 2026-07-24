---
title: "Slavic — The Slavicist"
permalink: /axis/slavic/
description: >-
  The Slavicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Slavicist — Cyril and Methodius to the damaskini, canon to vernacular.

Old Church Slavonic and its daughters: the OCS/Old Russian treebanks, the gospel and monument corpora, Freising, the Slovenian historical lane, Balkan damaskini, and the Church Slavonic dictionary shelves.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these ten answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 24 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 64 docs / 285,143 passages |
| `proiel` | treebank | nc | enabled · frozen | 12 docs / 51,321 passages |
| `torot` | treebank | nc | enabled · manual | 40 docs / 33,085 passages |
| `ccmh` | texts | attribution | enabled · manual | 19 docs / 28,786 passages |
| `goo300k` | texts | attribution | enabled · manual | 89 docs / 8,397 passages |
| `imp` | texts | attribution | enabled · manual | 658 docs / 404,897 passages |
| `damaskini` | texts | attribution | enabled · manual | 46 docs / 12,072 passages |
| `wiktionary-cu` | dictionary | attribution | enabled · manual | 4,615 entries |
| `freising` | texts | research_private | enabled · manual | 27 docs / 2,037 passages |
| `sl-lexica` | dictionary | attribution | enabled · manual | 139,405 entries |

## The desk's instruments

- **Gold-lemma languages:** chu (Old Church Slavonic) and orv (Old Russian)
  — PROIEL (Codex Marianus), TOROT (Zographensis), the four CCMH gospel
  codices, plus the Slovenian historical lane (goo300k, IMP, 1584-1899).
- **Dictionaries:** the Wiktionary OCS shelf (`wiktionary-cu`) and the
  Slovenian historical shelf (`sl-lexica`, Pleteršnik and the 16th-c.
  inventory).
- **Alignment work:** `nt`. The `chu` witnesses are PROIEL's Marianus plus
  the four CCMH codices — so `align --collate` builds a real apparatus.

## Working the slavic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis slavic          # the shelf census, this desk only
nabu axis slavic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis slavic   # a query scoped to this desk's shelves
nabu sync slavic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu align "MARK 2.3" --collate       # the CCMH gospel apparatus beside the Cyrillic Marianus column
nabu etym богъ --lang chu             # the reflex chain back through Proto-Slavic
nabu define *bogъ                     # the reconstruction shelf, with its descendant reflexes
nabu search въста --axis slavic       # cross-script fold — Cyrillic finds the Latin-diplomatic vъsta
nabu list sl-lexica --entries --prefix bh  # headword-prefix browse into the Slovenian shelf
```


## Terminal setup

- **Cyrillic OCS (chu):** nabu strips the titla (titlo, pokrytie,
  superscript letters) and keeps the points; `--display translit` romanizes
  via `Nabu::Cyrl` (ѣ to ě, щ to št, оу to u). **Noto Sans Mono** covers the
  combining range in the terminal's non-ASCII slot.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
