---
name: nabu-celtic
description: "Methodological guidance for the celtic desk of a Nabu library (Celticist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: celtic
  origin: generated
  sources: "corph gpc lexlep lexlep-words ogham riig stgall-priscian ud wiktionary-recon"
---

# The Celticist — the `celtic` desk

The Celticist — from Lepontic stones to the Old Irish glossators.

Continental Celtic epigraphy (RIIG, Lexicon Leponticum and its word shelf), ogham Primitive Irish, CorPH's Early Irish, the St Gall Priscian glosses in Latin and Old Irish, the UD Old Irish treebanks, the kaikki attested-Celtic extracts riding wiktionary-recon, and the GPC open subset as the Welsh dictionary shelf.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `corph` | CorPH — Corpus PalaeoHibernicum (ChronHib, Maynooth) | attribution |
| `gpc` | GPC — Geiriadur Prifysgol Cymru (open subset) | attribution |
| `lexlep` | Lexicon Leponticum (LexLep) — Cisalpine Celtic inscriptions (Univ. Vienna) | nc |
| `lexlep-words` | Lexicon Leponticum — Dictionary of Attested Forms (Univ. Vienna) | nc |
| `ogham` | OG(H)AM — Ogham in 3D v2.0 (DIAS / Maynooth) | nc |
| `riig` | RIIG — Recueil informatisé des inscriptions gauloises (Ausonius/ANR) | attribution |
| `stgall-priscian` | St Gall Priscian Glosses (St Gallen, Stiftsbibliothek 904) — digital edition v2.1 | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `corph` — CorPH — Corpus PalaeoHibernicum (ERC project Chronologicon Hibernicum, Maynooth) — 78 deeply annotated Early Irish texts of the seventh to tenth centuries: the Annals of Ulster, the Vita Columbae, the poems of Blathmac, the Milan, St Gall and Würzburg gloss corpora, the Book of Armagh, law tracts, poetry and computus. 17,944 sentences and 136,559 gold-lemmatized tokens, about four-fifths Early Irish and an eighth Latin, with per-lemma eDIL headword keys and cited etymologies. MIT license.
- `gpc` — Geiriadur Prifysgol Cymru, the historical dictionary of Welsh from the Centre for Advanced Welsh and Celtic Studies, in its open-access subset of about 89,000 entries. Each entry gives the headword and its variants, part of speech, plural forms and the opening of the English first sense, and ends with its permanent link to GPC Online, where the full dictionary lives. The full GPC remains under its own copyright as a living dictionary. The subset was supplied by the GPC editor under CC BY 4.0 (by email, 2026), on condition that the GPC website itself is never scraped and users are pointed to GPC Online.
- `lexlep` — The Lexicon Leponticum (lexlep.univie.ac.at, University of Vienna; ed. Stifter, Salomon, Braun et al.) — the digital edition of Cisalpine Celtic epigraphy: 494 inscriptions in Lepontic and Cisalpine Gaulish, given in scholarly transliteration and joined to catalogs of the inscribed objects (typology, material, dating) and find sites (coordinates), with concordances to the Morandi and Solinas print editions. Made available for scientific use under noncommercial Creative Commons terms.
- `lexlep-words` — The dictionary of attested forms from the Lexicon Leponticum (University of Vienna; ed. Stifter, Salomon, Braun et al.) — a 628-word etymological lexicon of Lepontic and Cisalpine Gaulish, with grammatical analysis, morphemic breakdown, and etymological commentary per entry. Made available for scientific use under noncommercial Creative Commons terms.
- `ogham` — Every known ogham inscription up to the mid-19th century — the ~500 stones of the OG(H)AM digital corpus in real Ogham codepoints with transliteration layers.
- `riig` — The Gaulish corpus of record — 428 inscriptions from the Recueil informatisé des inscriptions gauloises, Gallo-Greek and Gallo-Latin, with datings, findspots and French apparatus.
- `stgall-priscian` — The glosses of St Gallen, Stiftsbibliothek 904 — a copy of Priscian's Institutiones grammaticae, the great Latin grammar completed at Constantinople around 527, made by Irish scribes in 850–1, probably in Ireland, and carried to the Continent, where it reached St Gall after 888. Between its lines and in its margins stand over 9,400 glosses — more than a third of them in Old Irish, the rest in Latin — and thousands of construe marks, the symbols with which the glossators linked Priscian's words to guide a reader through his syntax. With the Würzburg and Milan glosses it is one of the three great witnesses to Old Irish, and its Latin commentary shows how ninth-century Irish scholars taught grammar. This is the digital edition by Rijcklof Hofman, Pádraic Moran and Bernhard Bauer (version 2.1, 2023): each gloss comes with the Priscian word and line it explains, its place on the manuscript page, its Thesaurus Palaeohibernicus reference and its type, and each Old Irish gloss with an English translation and a word-by-word analysis keyed to the Dictionary of the Irish Language. The unreleased layer of the Universal Dependencies Old Irish treebank of these glosses (DipSGG) was annotated automatically from this very database. MIT License (Pádraic Moran).
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Find macc in the Old Irish glosses.* — `nabu_search macc (lang: sga)`: Hits from the Milan and Bern Servius glosses (CorPH) with exact gloss-corpus citations — the diacritic fold means plain ASCII queries reach the edited text.

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
