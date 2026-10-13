---
title: "Slavic — The Slavicist"
permalink: /axis/slavic/
description: >-
  The Slavicist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Slavicist — Cyril and Methodius to the damaskini, canon to vernacular.

Old Church Slavonic and its daughters: the OCS/Old Russian treebanks, the gospel and monument corpora, Freising, the Slovenian historical lane with PriLit's earliest narrative prose (1643–1866), Balkan damaskini, and the Church Slavonic dictionary shelves.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these 33 answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 13 October 2026)</span> |
|---|---|---|---|---|
| `archiv-slav-phil` | texts | open | wired · manual | 33 docs / 22,348 passages |
| `bg-wikisource` | texts | attribution | wired · manual | 26 docs / 220 passages |
| `ccmh` | texts | attribution | wired · manual | 19 docs / 28,786 passages |
| `cs-wikisource` | texts | attribution | wired · manual | 330 docs / 4,748 passages |
| `damaskini` | texts | attribution | wired · manual | 46 docs / 12,072 passages |
| `elektire` | texts | open | wired · manual | 205 docs / 375,300 passages |
| `eltec-srp` | texts | attribution | wired · manual | 96 docs / 150,794 passages |
| `freising` | texts | research_private | wired · manual | 27 docs / 2,037 passages |
| `gams-zrcalo` | texts | attribution | wired · manual | 1 docs / 199 passages |
| `goo300k` | texts | attribution | wired · manual | 89 docs / 8,397 passages |
| `hr-wikisource` | texts | attribution | wired · manual | 1,390 docs / 132,052 passages |
| `imp` | texts | attribution | wired · manual | 658 docs / 404,897 passages |
| `kdsp` | texts | attribution | wired · manual | 262 docs / 290,394 passages |
| `korba` | texts | attribution | not yet wired | nothing held yet |
| `litopys` | texts | open | wired · manual | 41 docs / 964 passages / 923 entries |
| `mdz-protestant` | texts | open | wired · manual | 6 docs / 1,518 passages |
| `mk-wikisource` | texts | attribution | wired · manual | 836 docs / 31,114 passages |
| `pl-wikisource` | texts | attribution | wired · manual | 1,228 docs / 15,823 passages / 5,711 entries |
| `prague-bible-1488` | texts | attribution | wired · manual | 31 docs / 2,939 passages |
| `prilit` | texts | attribution | wired · manual | 43 docs / 8,526 passages |
| `proiel` | treebank | nc | wired · frozen | 12 docs / 51,321 passages |
| `ru-wikisource` | texts | attribution | wired · manual | 12 docs / 429 passages |
| `scripta-bulgarica` | texts | nc | wired · manual | 124 docs / 4,491 passages |
| `sl-lexica` | dictionary | attribution | wired · manual | 139,405 entries |
| `sl-wikisource` | texts | attribution | wired · manual | 1,539 docs / 145,035 passages |
| `slavistics-pd` | texts | open | wired · manual | 21 docs / 5,833 passages |
| `slouniki-nasovic` | dictionary | open | wired · manual | 35,159 entries |
| `sr-wikisource` | texts | attribution | wired · manual | 4,607 docs / 581,423 passages |
| `torot` | treebank | nc | wired · manual | 40 docs / 33,085 passages |
| `ud` | treebank | nc | wired · manual | 79 docs / 326,193 passages |
| `uk-wikisource` | texts | attribution | wired · manual | 7 docs / 541 passages |
| `vuk-danicic` | texts | open | wired · manual | 66 docs / 31,102 passages |
| `wiktionary-cu` | dictionary | attribution | wired · manual | 4,615 entries |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 13 October 2026)</span>: `sl` 142,013 · `be` 35,159 · `pol` 6,942 · `chu` 4,660 · `srp` 4,636 · `hrv` 1,730 · `orv` 1,026 · `mkd` 836 · `ces` 331 · `bul` 154 … and 26 more (`nabu axis slavic` lists all).

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

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable slavic               # first time: put this desk's shelves in this box's profile
nabu sync slavic                 # fetch/refresh the desk's enabled members
nabu list --axis slavic          # the shelf census, this desk only
nabu axis slavic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis slavic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu align "MARK 2.3" --collate       # the CCMH gospel apparatus beside the Cyrillic Marianus column
nabu etym богъ --lang chu             # the reflex chain back through Proto-Slavic
nabu define *bogъ                     # the reconstruction shelf, with its descendant reflexes
nabu search въста --axis slavic       # cross-script fold — Cyrillic finds the Latin-diplomatic vъsta
nabu list sl-lexica --entries --prefix bh  # headword-prefix browse into the Slovenian shelf
```


## Ask your model

With the [MCP server]({{ '/tools/#ask-your-model' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Show me MARK 2.3 in every witness — Greek against all four OCS codices.”** → `nabu_align "MARK 2.3" (work: nt)` — Fourteen witness columns in one reply: PROIEL Greek, Vulgate, Gothic, Armenian, Codex Marianus beside the CCMH Assemanianus / Marianus / Savvina / Zographensis diplomatic transcriptions, the West-Saxon Gospels, Sahidic Coptic, SBLGNT, WEB. `collate: true` turns the columns into a witness apparatus.

## Terminal setup

- **Cyrillic OCS (chu):** nabu strips the titla (titlo, pokrytie,
  superscript letters) and keeps the points; `--display translit` romanizes
  via `Nabu::Cyrl` (ѣ to ě, щ to št, оу to u). **Noto Sans Mono** covers the
  combining range in the terminal's non-ASCII slot.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [29 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
