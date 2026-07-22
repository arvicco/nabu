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

A source wears every desk it serves — these five answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `ccl` | dictionary | attribution | enabled · manual | 11,284 entries |
| `coptic-scriptorium` | texts | nc | enabled · manual | 482 docs / 74,169 passages |
| `tla-hf` | texts | attribution | enabled · manual | 4 docs / 33,978 passages |
| `aes` | texts | attribution | enabled · manual | 26,011 docs / 202,426 passages |
| `aed` | dictionary | attribution | enabled · manual | 35,052 entries |

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

The generic axis surfaces — every desk answers to these:

```
nabu list --axis egyptian          # the shelf census, this desk only
nabu axis egyptian                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis egyptian   # a query scoped to this desk's shelves
nabu sync egyptian                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search ⲛⲟⲩⲧⲉ --lang cop --loans grc  # Coptic passages that carry a Greek loanword
nabu list coptic-scriptorium --loans grc  # the most loan-saturated Coptic documents
nabu align "MARK 2.3"                 # the Sahidic and Bohairic columns of the verse
nabu define ⲛⲟⲩⲧⲉ                     # the Coptic lexicon, following the egy-cop crosswalk
```


## Terminal setup

- **Coptic:** nabu strips nothing; install `font-noto-sans-coptic` (Coptic
  is LTR, so no bidi toggle).
- **Hieroglyphic TLA text:** display.md names no hieroglyph font — read it
  through the TLA transcription rather than expecting glyph rendering.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
