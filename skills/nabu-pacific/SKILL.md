---
name: nabu-pacific
description: "Methodological guidance for the pacific desk of a Nabu library (Pacific philologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: pacific
  origin: generated
  sources: "ceipp-rongorongo ebible-pacific niupepa"
---

# The Pacific philologist — the `pacific` desk

The Pacific philologist — the Polynesian languages in their first prints, the Māori press to the mission Bibles.

The languages of the Pacific in their own historical texts, opening on the Niupepa collection: the Māori-language newspapers of 1842–1932 at the page grain, with the island print shelves joining as their packets land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `ceipp-rongorongo` | CEIPP rongorongo corpus — the Barthel-code transliteration of the Easter Island inscriptions (kohaumotu.org) | nc |
| `ebible-pacific` | eBible.org Pacific Bibles — Hawaiian 1868, Chamorro (ABS 1908), Pohnpeian (old alphabet) | open |
| `niupepa` | Niupepa — Māori Newspapers 1842–1932 (New Zealand Digital Library, University of Waikato) | research_private |
<!-- nabu:skill-sources:end -->

## What the shelves hold

_No source descriptions were available when this skill was scaffolded._

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
