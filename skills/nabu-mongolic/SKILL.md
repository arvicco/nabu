---
name: nabu-mongolic
description: "Methodological guidance for the mongolic desk of a Nabu library (Mongolist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: mongolic
  origin: generated
  sources: "altaica-shm wiktionary-recon"
---

# The Mongolist — the `mongolic` desk

The Mongolist — the Secret History's empire in its own words, hanzi transcription beside romanization.

The Mongolic-Tungusic lane, opening on Street's romanized Secret History via Monumenta Altaica (use granted by the site's maintainer, 2026-09-27) — the kaikki Manchu extract, the zh.wikisource hanzi transmission text and the Manchu corpus asks joining as they land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `altaica-shm` | Street's Text of the Secret History of the Mongols (Monumenta Altaica) | attribution |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `altaica-shm` — The Secret History of the Mongols in John C. Street's romanized Middle Mongol text (version 24, 2013), as hosted by Monumenta Altaica (altaica.ru). It is one document of about 3,500 lines, numbered by Street's own four-digit scheme (1010–9492), with the section (§) markers kept. Street's ASCII stand-ins for special letters (6 for the velar nasal, and so on) are served exactly as he wrote them, and his key travels in the metadata. The Monumenta Altaica maintainer granted use by email in 2026, and "Copyright John C. Street 1985-2013" is carried verbatim.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.

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
