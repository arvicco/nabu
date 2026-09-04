---
title: "Tibetan — The Tibetologist"
permalink: /axis/tibetan/
description: >-
  The Tibetologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Tibetologist — the Land of Snows from Dunhuang documents to the complete Derge canon.

The Tibetan desk opens with the canon whole: the Public-Domain Digital Derge Kangyur and Tengyur (Esukhia's exact-representation of the woodblocks, Toh numbers as the crosswalk key), 84000's English translation layer, OTDO's Old Tibetan documents, and the gold-annotation lane (SOAS POS, the Annals and Chronicle); the lexicon shelves join as their packets land.

The desk opens with the complete canon: the **Digital Derge Kangyur**
(103 volumes, Toh 1–1108) and **Tengyur** (213 volumes, Toh 1109–4569)
— Esukhia's Public-Domain exact-representation of the Derge woodblocks,
carved mistakes and archaic spellings preserved, every passage cited by
folio and line. Tohoku numbers are the documents' names
(`urn:nabu:derge-kangyur:toh846`), the crosswalk key shared with 84000,
rKTs and the catalog literature.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these twelve answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 4 September 2026)</span> |
|---|---|---|---|---|
| `e84000` | texts | nc | wired · manual | 388 docs / 124,223 passages |
| `otdo` | texts | attribution | wired · manual | 413 docs / 13,593 passages |
| `soas-tibetan` | texts | attribution | wired · manual | 4 docs / 991 passages |
| `old-tibetan` | texts | attribution | wired · manual | 3 docs / 2,669 passages |
| `derge-kangyur` | texts | open | wired · manual | 1,198 docs / 458,972 passages |
| `actib` | feature module | attribution | wired · manual | nothing held yet |
| `derge-tengyur` | texts | open | wired · manual | 3,362 docs / 897,142 passages |
| `mvp` | dictionary | open | wired · manual | 9,379 entries |
| `tibetan-verbs` | dictionary | open | wired · manual | 2,491 entries |
| `monlam-lexicon` | dictionary | attribution | wired · manual | 449,829 entries |
| `wiktionary-bo` | dictionary | attribution | wired · manual | 3,651 entries |
| `nabu-data` | feature module | attribution | wired · manual | nothing held yet |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 4 September 2026)</span>: `bod` 455,971 · `san` 9,379 · `xct` 4,564 · `otb` 410 · `en` 388 · `xzh` 5 · `eng` 1.

## The desk's instruments

- **The Toh crosswalk:** every text is its Tohoku number (`toh1`,
  `toh1-1` subindexes, `toh846a` Tohoku-gap texts) — the join key for
  translations, catalogs and parallel corpora as they land.
- **Exact-representation reading:** the woodblocks' own readings stay
  in the text; the proofreaders' `(error,correction)` suggestions,
  archaic/modern pairs and error candidates ride each passage's
  apparatus annotations.
- Syllables, not words: tsheg-delimited text is stored verbatim — word
  segmentation is enrichment-land, not parse.

## Working the tibetan desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable tibetan               # first time: put this desk's shelves in this box's profile
nabu sync tibetan                 # fetch/refresh the desk's enabled members
nabu list --axis tibetan          # the shelf census, this desk only
nabu axis tibetan                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis tibetan   # a query scoped to this desk's shelves
```

## Terminal setup

- **Tibetan script (xct):** dbu-can needs stacked-consonant rendering —
  install `font-noto-serif-tibetan` (or Noto Sans Tibetan) and let the
  terminal take its non-ASCII slot from it. Text is stored decomposed
  (NFD ≡ NFC for Tibetan); no special handling needed beyond the font.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-five research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
