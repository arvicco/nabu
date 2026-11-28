---
title: "Arabic — The Arabist"
permalink: /axis/arabic/
description: >-
  The Arabist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Arabist — the Islamicate library whole, Quran and hadith to falsafa and adab.

The OpenITI lane: premodern Arabic and Persian literature at corpus scale — Quran and hadith, history and biography, law and falsafa, the dīwāns and adab — with the Persian shelf (Ḥāfiẓ, Ibn Sīnā) riding the same Arabic-script fold that makes ara/fas cross-searchable — and DiCCAS, disaster accounts excerpted from ten classical sources with catastrophe terminology tagged — and the KITAB text-reuse instrument: upstream-computed reuse edges joining the held OpenITI books pairwise on the intertext desk.

The premodern Islamicate library is LIVE: OpenITI's ~9,079 primary
texts (~1.12 B words, the 2026 release zip md5-pinned into canonical)
made **Classical Arabic the largest language on the shelves — 33.3
million passages** — with the Persian lane (`fas`) riding the same
corpus. Holdings below are read live.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these fifteen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 November 2026)</span> |
|---|---|---|---|---|
| `althurayya` | feature module | attribution | wired · manual | nothing held yet |
| `corpus-coranicum` | texts | attribution | wired · manual | 114 docs / 6,236 passages |
| `corpus-coranicum-manuscripts` | texts | attribution | wired · manual | 193 docs / 32,182 passages |
| `corpus-coranicum-variants` | texts | attribution | wired · manual | 753 docs / 22,658 passages |
| `diccas` | texts | nc | wired · manual | 10 docs / 879 passages |
| `kitab` | feature module | nc | wired · manual | nothing held yet |
| `kitab-reuse` | feature module | nc | wired · manual | nothing held yet |
| `lane-lexicon` | dictionary | attribution | wired · manual | 48,795 entries |
| `makhzan` | texts | nc | wired · manual | 30 docs / 3,762 passages |
| `ociana` | inscriptions | research_private | wired · frozen | 36,794 docs / 36,794 passages |
| `openiti` | texts | nc | wired · manual | 9,079 docs / 34,631,499 passages |
| `ottoman-ocr` | texts | nc | wired · manual | 59 docs / 7,470 passages |
| `pgp-geniza` | texts | nc | wired · manual | 9,848 docs / 303,860 passages |
| `quranic-corpus` | texts | research_private | wired · manual | 114 docs / 6,236 passages |
| `wiktionary-ar` | dictionary | attribution | wired · manual | 36,974 entries |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 28 November 2026)</span>: `ara` 95,806 · `xna` 36,758 · `jrb` 4,068 · `heb` 2,178 · `en` 1,396 · `und` 898 · `ara-Latn` 867 · `fas` 351 · `arc` 283 · `ota` 102 … and 10 more (`nabu axis arabic` lists all).

## The desk's instruments

- **Lemmas and morphology on the Qurʾān; OpenITI is unannotated.** The
  two Qurʾān shelves are annotated word by word — `corpus-coranicum`
  (the Cairo 1924 text with Rafael Talmon's concordance: lemma, root,
  part of speech and inflection per word) and `quranic-corpus` (the
  Quranic Arabic Corpus morphology, per segment) — so `--lemma` and
  `--morph` reach them (`--morph stem=x,conjugation=impf`: the verb
  forms I–XII, the Semitic conjugations, mood, voice, case). OpenITI
  carries no morphology or lemma layer; on the Islamicate shelf the
  instruments are **full-text search** and the **timeline**.
- **The ara/fas Arabic-script fold:** one search skeleton across
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

The generic desk surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable arabic               # first time: put this desk's shelves in this box's profile
nabu sync arabic                 # fetch/refresh the desk's enabled members
nabu list --axis arabic          # the shelf census, this desk only
nabu axis arabic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis arabic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu show urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1  # Ḥāfiẓ's Muntasab — Persian verse in the %~% hemistich notation
nabu search الله --lang ara           # Allāh across the Arabic hadith, dīwān and falsafa shelves
nabu search دانی --lang fas           # the cross-keyboard ی/ي fold — an Arabic-yeh query (U+064A) still finds Ḥāfiẓ's farsi-yeh دانی (U+06CC)
nabu search --from 1300 --to 1400 --axis arabic  # term-less browse of the 14th-c.-CE shelf on the AH death-year timeline (live-verified 23 July 2026)
```


## Ask your model

With the [MCP server]({{ '/tools/#ask-your-model' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Who reused this passage of Ibn Sīnā's Šifāʾ?”** → `nabu_links urn:nabu:openiti:0428IbnSina.ShifaAfcalWaInficalat.ALCorpus00001-ara2:1.223.4` — kind="reuse" edges from the KITAB pairwise data: the passage reappears in Faḫr al-Dīn al-Rāzī's Mulaḫḫaṣ (two centuries later) with character/word offsets riding the edge detail — upstream- computed alignments, distinct from nabu's own intertext detection.

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
- **Nothing to strip, and no `--display translit`.** A census of the held corpus
  found consonantal standard-block text only (no tashkeel), so `default`,
  `plain` and `full` render the same bytes (isolates aside); and Arabic
  romanization is deliberately not built — the standards conflict and
  unpointed text lacks the vowels a romanization needs, so ara/fas pass
  through the translit mode unchanged (docs/display.md §1d).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [31 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
