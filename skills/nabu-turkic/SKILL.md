---
name: nabu-turkic
description: "Methodological guidance for the turkic desk of a Nabu library (Turkologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: turkic
  origin: generated
  sources: "atmo ud westoldturkic wiktionary-recon"
---

# The Turkologist — the `turkic` desk

The Turkologist — the runiform steppe to the Chagatai chancery, one literary continuum.

The Turkic historical lane, opening on ATMO's Jarring-collection Turki manuscripts (line-by-line TEI, Perso-Arabic with transliteration) and the kaikki Old Turkic / Old Uyghur / Chagatai extracts — the Wilkens Old Uyghur dictionary and the runiform inscriptions joining as their packets and asks land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `atmo` | ATMO — Annotated Turki Manuscripts from the Jarring Collection Online | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `westoldturkic` | West Old Turkic — Turkic loanwords in Hungarian (Róna-Tas & Berta 2011, CLDF) | attribution |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `atmo` — Annotated Turki Manuscripts from the Jarring Collection Online (ATMO), by Arienne Dwyer, C. M. Sperberg-McQueen and colleagues (Kansas/Indiana with Lund University Library). It offers line-by-line TEI transcripts of 18th–20th-century Eastern Turki manuscripts from Lund's Jarring collection; fifteen are published so far. Each line gives the Perso-Arabic text with a full Latin transliteration, and endorsements and marginalia are marked by zone rather than dropped. The language, the "Turki" of the manuscripts, is held at the coarse level of late Chagatai. CC BY-SA 4.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `westoldturkic` — West Old Turkic: Turkic Loanwords in Hungarian by András Róna-Tas and Árpád Berta (2011), as the CLDF dataset extracted by LoanpyDataHub (Zenodo, version 2.0). It is a dictionary of 480 reconstructed etyma of West Old Turkic, the r-Turkic (Bolgar-type) branch that Hungarian borrowed from. Each etymon is traced down its Hungarian descent (Early and Late Ancient, Old and modern Hungarian), with the borrowing step marked, the phonemic segments given and the Hungarian first-attestation year recorded. CC BY 4.0.
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
