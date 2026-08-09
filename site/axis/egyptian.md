---
title: "Egyptian — The Egyptologist"
permalink: /axis/egyptian/
description: >-
  The Egyptologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Egyptologist — hieroglyphs to Coptic, one language across four millennia of script.

The Egyptian-Coptic continuum: the TLA corpora and word list (tla-hf, aes, aed), the Coptic lexicon with its egy-cop crosswalk, and Coptic Scriptorium.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these seven answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 9 August 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 73 docs / 322,114 passages |
| `ccl` | dictionary | attribution | wired · manual | 11,284 entries |
| `coptic-scriptorium` | texts | nc | wired · manual | 482 docs / 74,169 passages |
| `tla-hf` | texts | attribution | wired · manual | 4 docs / 33,978 passages |
| `aes` | texts | attribution | wired · manual | 26,011 docs / 202,426 passages |
| `aed` | dictionary | attribution | wired · manual | 35,052 entries |
| `elephantine` | papyri & ostraca | attribution | wired · manual | 15,539 docs / 69,350 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 9 August 2026)</span>: `egy` 51,130 · `ger` 12,985 · `cop` 12,222 · `eng` 4,861 · `grc` 3,311 · `egy-Egyd` 1,424 · `arc` 1,189 · `ara` 962 · `und` 168 · `phn` 94 … and 19 more (`nabu axis egyptian` lists all).

## The desk's instruments

- **The hieroglyph-to-Coptic continuum:** the TLA corpora and word list
  (`tla-hf`, `aes`, `aed`), the Coptic lexicon with its egy-cop crosswalk
  (`ccl`), and Coptic Scriptorium (the complete Sahidic and Bohairic NT,
  gold-lemmatized).
- **The contact facet:** Coptic Scriptorium is the `--loans` shelf, with
  131K+ Greek loan tokens tagged — `search --loans grc` and
  `list coptic-scriptorium --loans` read them.
- **Alignment work:** Coptic Scriptorium supplies the two Coptic columns of
  the `nt` work.

## Working the egyptian desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable egyptian               # first time: put this desk's shelves in this box's profile
nabu sync egyptian                 # fetch/refresh the desk's enabled members
nabu list --axis egyptian          # the shelf census, this desk only
nabu axis egyptian                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis egyptian   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu search ⲛⲟⲩⲧⲉ --lang cop --loans grc  # Coptic passages that carry a Greek loanword
nabu list coptic-scriptorium --loans grc  # the most loan-saturated Coptic documents
nabu align "MARK 2.3"                 # the Sahidic and Bohairic columns of the verse
nabu define ⲛⲟⲩⲧⲉ                     # the Coptic lexicon, following the egy-cop crosswalk
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Search the Egyptian sentences for nfr.”** → `nabu_search nfr (lang: egy)` — AES hits in Egyptological transliteration (tomb inscriptions, offering lists) — ꜣ and ꜥ fold to a, so an ASCII query reaches them.

## Terminal setup

- **Coptic:** nabu strips nothing; install `font-noto-sans-coptic` (Coptic
  is LTR, so no bidi toggle).
- **Hieroglyphic TLA text:** display.md names no hieroglyph font — read it
  through the TLA transcription rather than expecting glyph rendering.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
