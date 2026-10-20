---
name: nabu-americas
description: "Methodological guidance for the americas desk of a Nabu library (Americanist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: americas
  origin: generated
  sources: "guaman-poma ticha ud"
---

# The Americanist — the `americas` desk

The Americanist — the colonial record of the indigenous Americas, Zapotec testaments to the Andean chronicle.

The indigenous-Americas lane, colonial-era first: Ticha's Valley Zapotec TEI (Córdova's 1578 Arte, Agüero's 1666 Miscelaneo, the testaments and their period Spanish translations), the Royal Danish Library's Guaman Poma Nueva corónica (Spanish with Quechua and Aymara passages), and the UD Tupinambá and Old Guaraní treebanks of the Jesuit grammars and catechisms — the modern UD treebanks of American languages deliberately out.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `guaman-poma` | Guaman Poma, Nueva corónica y buen gobierno (Royal Danish Library digital edition) | open |
| `ticha` | Ticha — colonial Valley Zapotec texts in TEI (Haverford College) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `guaman-poma` — Felipe Guaman Poma de Ayala's El primer nueva corónica y buen gobierno (1615), the illustrated chronicle-letter to Philip III, from the autograph manuscript at the Royal Danish Library (GKS 2232 4º). It is held in the Library's digital edition (2001, revised 2004): the transcription of John V. Murra, Rolena Adorno and Jorge L. Urioste, corrected against the facsimile by Adorno and Ivan Boserup, with its critical notes. Each of the some 1,190 manuscript pages is one document, read paragraph by paragraph, with Guaman Poma's own page numbers, the captions of his nearly 400 drawings, the commentary and each page's list of Andean terms. The text is mostly Spanish, with Quechua, Aymara and Latin passages that the edition italicizes but does not tag by language. The Library marks it with the Public Domain Mark.
- `ticha` — Ticha's TEI transcriptions of colonial Valley Zapotec texts (Haverford College Digital Scholarship; Brook Danielle Lillehaugen et al.). It holds Juan de Córdova's Arte en lengua zapoteca (México 1578), Cristóbal de Agüero's Miscelaneo espiritual en el idioma zapoteco (México 1666), Levanto's Arte and Cathecismo de la lengua zaapoteca, and the 1744 San Sebastián Teitipac testament in Zapotec with its Spanish translation. Beside them are about 87 manuscripts from 1633 to 1832, most of them period Spanish translations, made by colonial interpreters, of Zapotec testaments and bills of sale. There are 93 documents read page by page, about 126,000 Zapotec and 143,000 Spanish words, each dated and placed by Ticha's own document ids. The original reading is served, with the project's modern Spanish regularization alongside. CC BY-SA 4.0 for the repository; the Ticha website itself is a separate publication and is not used.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.

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
