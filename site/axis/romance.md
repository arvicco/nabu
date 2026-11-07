---
title: "Romance — The Romanist"
permalink: /axis/romance/
description: >-
  The Romanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Romanist — the Latin-to-vernacular continuum, charter Latin to Roland to the troubadours.

The Latin-to-vernacular continuum: CroALa's medieval and neo-Latin opens the desk; late-antique prose, the MGH critical editions, and the Old French treebanks and texts join as their shelves land.

The continuum is on the shelves end to end: **digilibLT**'s late-antique
secular prose (2nd–7th c.), **CroALa**'s Croatian Latin (a 976 CE charter
through the neo-Latin centuries, dual-tagged with `classical`), the
**openMGH** critical editions (the *SS rerum Germanicarum* first wave —
Einhard, Widukind, Adam of Bremen), **BFM**'s Old and Middle French from
the 842 *Serments de Strasbourg* onward, and the **UD Romance treebanks**
(Tuscan charters, Dante's Latin, Old French, Old Romanian) carrying the
gold annotation — four gold-lemma languages: `fro`, `frm`, `ro`, `ota`.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these 35 answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 7 November 2026)</span> |
|---|---|---|---|---|
| `analecta-hymnica` | texts | open | wired · manual | 55 docs / 17,211 passages |
| `aranese` | texts | attribution | wired · manual | 2 docs / 839,816 passages |
| `bdcamoes` | texts | attribution | wired · manual | 127 docs / 69,812 passages |
| `bfm` | texts | attribution | wired · manual | 219 docs / 333,819 passages |
| `bim-sahcoba` | texts | attribution | wired · manual | 15 docs / 19,361 passages |
| `cantigas` | texts | attribution | wired · manual | 1,682 docs / 34,162 passages |
| `cantus` | texts | nc | wired · manual | 156,519 docs / 156,519 passages |
| `corpus-corporum` | texts | nc | wired · manual | 5,248 docs / 896,770 passages |
| `croala` | texts | attribution | wired · manual | 570 docs / 309,180 passages |
| `ctilc` | texts | attribution | wired · manual | 967 docs / 256,685 passages |
| `cv-sardinian` | texts | open | wired · manual | 1 docs / 5,237 passages |
| `derom` | dictionary | nc | wired · manual | 233 entries |
| `digiliblt` | texts | attribution | wired · manual | 372 docs / 459,451 passages |
| `disco` | texts | attribution | wired · manual | 1,215 docs / 4,527 passages |
| `divinum-officium` | texts | open | wired · manual | 4,003 docs / 26,381 passages |
| `gregobase` | texts | open | wired · manual | 18,422 docs / 20,810 passages |
| `littre` | dictionary | attribution | wired · manual | 78,483 entries |
| `lo-congres` | texts | attribution | wired · manual | 12 docs / 10,304 passages |
| `mazarinades` | texts | attribution | wired · manual | 3,067 docs / 40,883 passages |
| `meloniromance` | cognacy dataset | attribution | wired · manual | 5,419 entries |
| `memis` | inscriptions | attribution | wired · manual | 51 docs / 473 passages |
| `noscemus` | texts | attribution | wired · frozen | 1,038 docs / 555,797 passages |
| `openmgh` | texts | attribution | wired · manual | 153 docs / 36,143 passages |
| `osta` | texts | nc | wired · manual | 740 docs / 5,177 passages |
| `salom` | texts | attribution | wired · manual | 1 docs / 10,685 passages |
| `socinian-letters` | texts | attribution | wired · manual | 1,869 docs / 18,067 passages |
| `theatre-classique` | texts | nc | wired · manual | 1,939 docs / 1,601,085 passages |
| `typikon-bible` | texts | attribution | wired · manual | 229 docs / 105,698 passages |
| `ud` | treebank | nc | wired · manual | 83 docs / 329,980 passages |
| `wiktionary-ca` | dictionary | attribution | wired · manual | 198,685 entries |
| `wiktionary-frm` | dictionary | attribution | wired · manual | 4,956 entries |
| `wiktionary-fro` | dictionary | attribution | wired · manual | 9,280 entries |
| `wiktionary-oc` | dictionary | attribution | wired · manual | 7,521 entries |
| `wiktionary-osp` | dictionary | attribution | wired · manual | 1,501 entries |
| `wiktionary-pro` | dictionary | attribution | wired · manual | 695 entries |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 7 November 2026)</span>: `cat` 199,652 · `lat` 192,472 · `fra` 83,680 · `fro` 9,502 · `oci` 7,530 · `frm` 4,959 · `osp` 2,185 · `roa-opt` 1,682 · `spa` 1,217 · `eng` 722 … and 24 more (`nabu axis romance` lists all).

**Carried in by multilingual packs** (`ud` — whole-source members whose other languages ride along, as of 7 November 2026): `orv` 9 · `ota` 5 · `lzh` 4 · `cop` 3 · `egy` 3 … and 15 more (`nabu axis romance` lists all).

## The desk's instruments

No desk-specific instruments curated yet — the generic surfaces above apply.

## Working the romance desk

The generic desk surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable romance               # first time: put this desk's shelves in this box's profile
nabu sync romance                 # fetch/refresh the desk's enabled members
nabu list --axis romance          # the shelf census, this desk only
nabu axis romance                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis romance   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search chevalier --lang fro      # Old French across BFM — Erec's chevalier at the head of the hits
nabu search ragusa --source croala    # Filelfo's 1470 Ragusaeis and Palmotić's carmina — Dubrovnik in Latin verse
nabu search --lemma miles --lang lat --axis romance  # lemma search on the desk's Latin — digilibLT answers at an honest [silver] tag; --gold-only narrows to the treebanks
```


## Ask your model

With the [MCP server]({{ '/tools/#ask-your-model' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Who sang of Ragusa in Latin?”** → `nabu_search ragusa (lang: lat)` — Croatian Latin verse from the CroALa shelf (live-verified 2026-07-25): Filelfo's 1470 Ragusaeis (AFFECTUS RAGVSA TVAE CLARISSIMA LAVDI) and Palmotić's carmina — the medieval-Latin edge of the continuum, positionally cited (d1.d2.l198) for nabu_show.

---

One of the [30 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
