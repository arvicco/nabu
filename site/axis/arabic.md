---
title: "Arabic — The Arabist"
permalink: /axis/arabic/
description: >-
  The Arabist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Arabist — the Islamicate library whole, Quran and hadith to falsafa and adab.

The OpenITI lane: premodern Arabic and Persian literature at corpus scale — Quran and hadith, history and biography, law and falsafa, the dīwāns and adab — with the Persian shelf (Ḥāfiẓ, Ibn Sīnā) riding the same Arabic-script fold that makes ara/fas cross-searchable (P41-3).

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

The single shelf below answers this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `openiti` | texts | nc | not enabled | not synced yet |

The corpus is staged, not synced: OpenITI's ~9,106 primary texts / ~1.12 B words arrive with the owner's first `nabu sync openiti` (the fetch is a ~5.9 GB release zip plus its metadata index, md5-pinned before any tree mutation), after which the holdings above fill in live.

## The desk's instruments

- **No gold lemmas — OpenITI is unannotated.** The corpus carries no
  morphology or lemma layer, so `--lemma`, `vocab` and `formulas` do not
  apply to this desk; its instruments are **full-text search** across the
  whole Islamicate shelf and the **timeline**.
- **The ara/fas Arabic-script fold (P41-3):** one search skeleton across
  the ی/ي and ک/ك keyboard split, maqsura, taa marbuta, tashkeel, tatweel
  and ZWNJ — so a query typed on either keyboard reaches the stored form
  whichever keyboard wrote it. Search-side only; the stored bytes stay
  pristine (conventions §9), and `--lang ara` / `--lang fas` scope to one
  shelf.
- **The AH death-year timeline:** every OpenITI urn opens with the
  author's 4-digit hijrī death year, so the OpenitiDates extractor lands
  each text on the calendar as a CE terminus — round(AH × 0.970225 +
  621.57), the tabular conversion — and `--from/--to` and `--century`
  scope the shelf by when its authors died (Ḥāfiẓ d. AH 792 = 1390 CE).
  No gazetteer, so no `--place` on this desk.
- **License posture — `nc`** (CC BY-NC-SA 4.0, the Zenodo record's only
  grant): the shelf is **MCP-excluded**, so the AI server never serves
  OpenITI passages; the CLI reads them for local research.

## Working the arabic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis arabic          # the shelf census, this desk only
nabu axis arabic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis arabic   # a query scoped to this desk's shelves
nabu sync arabic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu show urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1  # Ḥāfiẓ's Muntasab — Persian verse in the %~% hemistich notation
nabu search الله --lang ara  # Allāh across the Arabic hadith, dīwān and falsafa shelves
nabu search دانی --lang fas  # the cross-keyboard ی/ي fold — an Arabic-yeh query (U+064A) still finds Ḥāfiẓ's farsi-yeh دانی (U+06CC)
nabu search --from 1300 --to 1400 --axis arabic  # the AH death-year timeline — Ḥāfiẓ (d. AH 792 = 1390 CE) lands in this window
```

## Terminal setup

- **Arabic and Persian (ara/fas) are RTL** and reuse the hbo/arc
  machinery: `isolates: true` wrapping, the same modes, the same honesty
  footer. The terminal owns the direction — the **iTerm2 ≥ 3.6.0 RTL
  toggle** (Settings → General → Experimental; Terminal.app has no bidi
  at all).
- **Shaping stays degraded even with bidi on.** Arabic is a connected
  script and a cell-grid terminal cannot fully join it, so what you get
  is right-to-left, legible, *unligatured* Arabic — fine for scanning
  search hits and citations, not for sustained reading (use `nabu export`
  and a real text view for that). Font: `font-noto-naskh-arabic` — naskh
  stays legible at terminal sizes; a dedicated iTerm2 reading profile with
  it boosted a few points is the workable setup (docs/display.md §2).
- **Nothing to strip, and no `--display translit`.** The P41-g census
  found consonantal standard-block text only (no tashkeel), so `default`,
  `plain` and `full` render the same bytes (isolates aside); and Arabic
  romanization is deliberately not built — the standards conflict and
  unpointed text lacks the vowels a romanization needs, so ara/fas pass
  through the translit mode unchanged (docs/display.md §1d).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
