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

A source wears every desk it serves — these six answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 36 docs / 238,032 passages |
| `gretil` | texts | nc | enabled · manual | 780 docs / 703,068 passages |
| `mw` | dictionary | nc | enabled · manual | 193,890 entries |
| `suttacentral` | texts | open | enabled · manual | 12,348 docs / 697,650 passages |
| `sarit` | texts | attribution | enabled · manual | 78 docs / 345,601 passages |
| `dcs` | treebank | attribution | enabled · manual | 15,741 docs / 753,093 passages |

## The desk's instruments

- **The Sanskrit, Prakrit and Pali lane:** GRETIL (780 editions — epic,
  purāṇa, kāvya, śāstra, the Ṛgveda with Vedic accents), SARIT, the DCS
  treebank (IAST), the Vedic UD treebank, and SuttaCentral's canon.
- **Dictionary:** Monier-Williams (`mw`) — 193,890 entries, SLP1
  transcoded to IAST; its citations resolve into GRETIL at verse grain and
  its Greek/Latin/Gothic cognate notes feed `nabu etym`.

## Working the indic desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis indic          # the shelf census, this desk only
nabu axis indic                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis indic   # a query scoped to this desk's shelves
nabu sync indic                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu define amsa                      # Monier-Williams, with GRETIL-resolved citations
nabu search धर्मन् --lang san         # the cross-script fold — Devanagari finds the IAST dharman
nabu show urn:nabu:gretil:sa_rAmAyaNa --display translit  # the Rāmāyaṇa in IAST (Devanagari shelves render to IAST; IAST passes through)
nabu search --lemma deva --lang san --morph case=loc --axis indic  # DCS gold morphology — deva, locative attestations only
nabu vocab urn:nabu:dcs:143:1067      # distinctive vocabulary of a Rāmāyaṇa book (DCS gold lemmas)
```


## Terminal setup

- **Devanagari (san):** nabu strips Vedic accents when present (IAST is left
  untouched); `--display translit` renders to IAST via `Nabu::Deva`. A
  conjunct-capable Devanagari fallback is needed — the macOS system default
  suffices. IAST diacritics (ā, ṁ, ṭ) render uniformly under **Noto Sans
  Mono** in the non-ASCII slot.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
