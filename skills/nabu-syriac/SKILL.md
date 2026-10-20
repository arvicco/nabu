---
name: nabu-syriac
description: "Methodological guidance for the syriac desk of a Nabu library (Syriacist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: syriac
  origin: generated
  sources: "peshitta syriac-corpus"
---

# The Syriacist — the `syriac` desk

The Syriacist — the Peshitta and the estrangela bookshelf.

The Syriac language desk: the ETCBC Peshitta and the Digital Syriac Corpus, riding beside the biblical hat by design.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `peshitta` | Peshitta OT incl. deuterocanon (ETCBC, Text-Fabric tf/0.2) | nc |
| `syriac-corpus` | Digital Syriac Corpus (srophe, 632 TEI documents) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `peshitta` — The Peshitta Old Testament — the Syriac OT in 65 books including the deuterocanon: the electronic text of the Leiden Vetus Testamentum Syriace / Codex Ambrosianus, without the separately copyrighted apparatus. 426,835 words in 1,269 chapters and 31,341 verses, following the Masoretic versification; parallel manuscript recensions of ten books are kept as distinct witnesses. From the ETCBC (Amsterdam); CC BY-NC.
- `syriac-corpus` — The Digital Syriac Corpus (syriaccorpus.org; BYU, Oxford, Vanderbilt, Texas A&M) — 632 TEI editions of classical Syriac literature: Aphrahat's Demonstrations, the verse of Ephrem and Jacob of Serugh (over 100,000 poetry lines), the Peshitta New Testament letters, and hagiography, with author and work identifiers linked to syriaca.org. The Syriac base texts are public domain; the TEI editions CC BY 4.0.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *ܡܠܟܘܬܐ in the Syriac corpus?* — `nabu_search ܡܠܟܘܬܐ (lang: syc)`: The Peshitta Mark ("a kingdom divided against itself…") beside homiletic prose from the Digital Syriac Corpus — vocalized and unvocalized spellings fold together.

## Working cautions

- **Data license is not code license.** This guidance text is MIT; every passage
  carries its own `license_class` (`open`, `attribution`, `nc`, `odbl`, and — excluded
  by default — `research_private` / `restricted`). `nc` forbids commercial reuse of the
  quoted text; `attribution` and `odbl` require naming the source edition (`odbl`
  also binds derived databases to share-alike). A `credit` key, when present, must
  travel with any quotation.
- **An empty result is not absence of evidence.** Call `nabu_status` before concluding
  a text, word or form is unattested: the shelf may be unsynced on this box, the
  language may be indexed at another grain, or the class may be excluded by default.
- **Search is folded, `nabu_show` is pristine.** Matching runs over a folded form
  (case, diacritics, and per-language rules); quote only the pristine text
  `nabu_show` returns, never a search snippet or a folded phrase.
- **Lemma tiers differ in evidential weight.** `gold` lemmas are verified annotation
  and the only tier that counts as attestation; `silver` lemmas are upstream-automatic
  and always labeled; `equivalence` rows are glosses, never attestation. A lemma
  search reaches only the lemmatized minority of the corpus.
- **Dates are typed.** A document's primary dated row has a class — `artifact` (the
  object's own dating), `composition` (an attributed author-era date), `edition` (a
  print year, never the text's date), or `silver` (a tool estimate, never an upstream
  claim). Years are signed, with no year 0. Use `date_basis` to keep the classes
  apart.

## Reproducibility

Record, per claim: the passage or document `urn`, the `source` slug, its
`license_class` (and `credit` when served), the exact tool call and arguments, and the
date of the `nabu_status` snapshot the catalog answered from. Upstream editions are
revised; the urn plus the catalog date is the citation, the snippet is not.
