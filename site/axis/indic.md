---
title: "Indic — The Indologist"
permalink: /axis/indic/
description: >-
  The Indologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Indologist — Veda to sastra, the Sanskrit library and its instruments.

The Sanskrit, Prakrit and Pali lane: GRETIL and SARIT, the DCS treebank, Monier-Williams, the Vedic UD treebank, and SuttaCentral's canon.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these 29 answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 October 2026)</span> |
|---|---|---|---|---|
| `dacon` | texts | attribution | wired · manual | 4 docs / 977 passages |
| `dcs` | treebank | attribution | wired · auto | 15,900 docs / 769,373 passages / 300,763 entries |
| `dharma-deccan` | texts | attribution | wired · auto | 1,695 docs / 27,983 passages |
| `dharma-mdt` | texts | attribution | wired · auto | 734 docs |
| `dharma-tamil` | texts | attribution | wired · auto | 1,267 docs / 17,993 passages |
| `gretil` | texts | nc | wired · manual | 780 docs / 713,718 passages |
| `gretil-legacy` | texts | nc | wired · manual | 22 docs / 83,383 passages |
| `gu-wikisource` | texts | attribution | wired · manual | 207 docs / 1,462 passages |
| `kannada-texts` | texts | attribution | wired · auto | 16 docs / 16,151 passages |
| `madurai` | texts | attribution | wired · manual | 755 docs / 1,214,683 passages |
| `mw` | dictionary | nc | wired · manual | 193,890 entries |
| `nabu-data` | feature module | attribution | wired · manual | nothing held yet |
| `prakrit-texts` | texts | attribution | wired · auto | 22 docs / 27,124 passages |
| `sarit` | texts | attribution | wired · manual | 78 docs / 345,601 passages |
| `shabados` | texts | open | wired · auto | 127 docs / 141,264 passages |
| `siddham` | texts | attribution | wired · manual | 427 docs / 6,334 passages |
| `sii-clean` | texts | attribution | wired · auto | 18,495 docs / 314,915 passages |
| `suttacentral` | texts | open | wired · auto | 12,393 docs / 699,345 passages |
| `tamilex` | texts | nc | wired · auto | 7,830 docs / 14,972 passages |
| `te-wikisource` | texts | attribution | wired · manual | 453 docs / 208,794 passages |
| `ud` | treebank | nc | wired · manual | 83 docs / 329,980 passages |
| `vedaweb` | texts | attribution | wired · manual | 1,028 docs / 10,552 passages |
| `wiktionary-dv` | dictionary | attribution | wired · manual | 2,047 entries |
| `wiktionary-kn` | dictionary | attribution | wired · manual | 2,741 entries |
| `wiktionary-ml` | dictionary | attribution | wired · manual | 11,505 entries |
| `wiktionary-pra` | dictionary | attribution | wired · manual | 2,712 entries |
| `wiktionary-si` | dictionary | attribution | wired · manual | 1,281 entries |
| `wiktionary-ta` | dictionary | attribution | wired · manual | 13,855 entries |
| `wiktionary-te` | dictionary | attribution | wired · manual | 23,325 entries |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 22 October 2026)</span>: `san` 511,638 · `tel` 23,875 · `tam-Latn` 18,527 · `tam` 14,610 · `mal` 11,505 · `pli` 7,288 · `tel-Latn` 5,103 · `eng` 4,790 · `kan-Latn` 3,844 · `kan` 2,741 … and 54 more (`nabu axis indic` lists all).

## The desk's instruments

- **The Sanskrit, Prakrit and Pali lane:** GRETIL (780 editions — epic,
  purāṇa, kāvya, śāstra, the Ṛgveda with Vedic accents), SARIT, the DCS
  treebank (IAST), the Vedic UD treebank, and SuttaCentral's canon.
- **Dictionary:** Monier-Williams (`mw`) — 193,890 entries, SLP1
  transcoded to IAST; its citations resolve into GRETIL at verse grain and
  its Greek/Latin/Gothic cognate notes feed `nabu etym`.

## Working the indic desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable indic               # first time: put this desk's shelves in this box's profile
nabu sync indic                 # fetch/refresh the desk's enabled members
nabu list --axis indic          # the shelf census, this desk only
nabu axis indic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis indic   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu define amsa                      # Monier-Williams, with GRETIL-resolved citations
nabu search धर्मन् --lang san         # the cross-script fold — Devanagari finds the IAST dharman
nabu show urn:nabu:gretil:sa_rAmAyaNa --display translit  # the Rāmāyaṇa in IAST (Devanagari shelves render to IAST; IAST passes through)
nabu search --lemma deva --lang san --morph case=loc --axis indic  # DCS gold morphology — deva, locative attestations only
nabu vocab urn:nabu:dcs:143:1067      # distinctive vocabulary of a Rāmāyaṇa book (DCS gold lemmas)
```


## Ask your model

With the [MCP server]({{ '/tools/#ask-your-model' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“dharma across the Sanskrit corpus, by lemma.”** → `nabu_search (lemma: dharma, lang: san)` — DCS hits with inflected surface forms (dharmeṇa, dharmaś) and the lexicon gloss beside each — upaniṣads first, ranked by relevance.

## Terminal setup

- **Devanagari (san):** nabu strips Vedic accents when present (IAST is left
  untouched); `--display translit` renders to IAST via `Nabu::Deva`. A
  conjunct-capable Devanagari fallback is needed — the macOS system default
  suffices. IAST diacritics (ā, ṁ, ṭ) render uniformly under **Noto Sans
  Mono** in the non-ASCII slot.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [30 research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
