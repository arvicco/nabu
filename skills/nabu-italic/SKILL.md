---
name: nabu-italic
description: "Methodological guidance for the italic desk of a Nabu library (Italicist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: italic
  origin: generated
  sources: "burman-concordance ceipom etruscan-loans isicily itant larth-etp lexicon-itant lexlep lexlep-words open-etruscan sabellic-loans tir wiktionary-recon"
---

# The Italicist — the `italic` desk

The Italicist — the languages of pre-Roman Italy, Oscan to Etruscan to Raetic.

The Sabellic, Etruscan, Venetic and Raetic epigraphic shelves (CEIPoM, ItAnt, the Etruscan editions, TIR), Lepontic at the Celtic border, I.Sicily's island mix, and the Sabellic-to-Latin loan lane.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `burman-concordance` | Burman — Digital Concordance of Etruscan, Faliscan and Early Latin Inscriptions | open |
| `ceipom` | CEIPoM — Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium BCE (Pitts, KU Leuven; Zenodo v1.3) | attribution |
| `etruscan-loans` | Etruscan → Latin loans — en.wiktionary curation | attribution |
| `isicily` | I.Sicily — the inscriptions of ancient Sicily (Prag, Oxford / ERC Crossreads) | attribution |
| `itant` | Corpus ItAnt — Languages and Cultures of Ancient Italy (PRIN 2017, CNR-ILC/UniFI) | nc |
| `larth-etp` | Larth ETP glossary — Etruscan vocabulary with POS and translations | attribution |
| `lexicon-itant` | Lexicon ItAnt — the languages of ancient Italy (DigItAnt, CNR-ILC/UniFI; OntoLex-Lemon) | nc |
| `lexlep` | Lexicon Leponticum (LexLep) — Cisalpine Celtic inscriptions (Univ. Vienna) | nc |
| `lexlep-words` | Lexicon Leponticum — Dictionary of Attested Forms (Univ. Vienna) | nc |
| `open-etruscan` | OpenEtruscan — Etruscan Machine Learning Corpus (Zenodo 20075836) | attribution |
| `sabellic-loans` | Sabellic → Latin loans — en.wiktionary curation (Oscan/Umbrian/Sabine) | attribution |
| `tir` | Thesaurus Inscriptionum Raeticarum (TIR) — Raetic corpus of record (Univ. Vienna) | nc |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `burman-concordance` — A Digital Concordance of Etruscan, Faliscan and Early Latin Inscriptions from Etruria (Annie Cecilia Burman, Uppsala): 14,986 inscription records crosswalking fourteen citation systems — Trismegistos, CIE, Rix's Etruskische Texte, Meiser's ET2, TLE, Bakkum and the CIL volumes — one row per inscription of Etruria. A concordance instrument rather than a text corpus: it carries the identifiers scholars cite by, not the readings, and lets any edition of a stone be traced to every other. Public domain (CC0).
- `ceipom` — The Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium BCE (CEIPoM), by Reuben Pitts (KU Leuven) — 3,875 pre-Roman Italic inscriptions in 5,303 sentences with 37,041 dependency-annotated tokens: Latin (including Faliscan), Oscan, Messapic, Venetic, Umbrian — the Iguvine Tables complete — Old Sabellic and a handful of Greek texts, the Fibula Praenestina and the Duenos inscription among them, with per-text scripts, dates, findspot coordinates and 3,630 Trismegistos ids. A single scholar's dissertation corpus: lemmas, dependencies and Classical Latin equivalences are the editor's own curation. CC BY-SA 4.0, published on Zenodo (doi:10.5281/zenodo.6475427).
- `isicily` — I.Sicily (Jonathon Prag, Oxford / ERC Crossreads): 5,120 EpiDoc records covering the inscriptions of ancient Sicily in all its languages — Greek and Latin foremost, plus the island's fragmentary Elymian, Sicel, Sicilian Punic, and Oscan material, for which this corpus is the only machine-readable home — with dating, coordinates, and concordances to the major epigraphic databases, and English and Italian translations for part of the corpus. CC BY 4.0.
- `itant` — Corpus ItAnt — Languages and Cultures of Ancient Italy (CNR-ILC and the University of Florence): EpiDoc editions of 501 Oscan and 9 Lepontic inscriptions, word-tokenized with onomastic tagging, interpuncts, and ligature and writing-direction markup; diplomatic renderings accompany the Lepontic texts, Italian and English translations cover much of the corpus, and every record carries dating, findspot, and a Trismegistos concordance. CC BY-NC-SA 4.0.
- `larth-etp` — An Etruscan glossary from the Larth Etruscan-NLP project (Vico & Spanakis 2023), in the scholarly lineage of Wallace's Etruscan Texts Project: 1,122 vocabulary rows with English translations (952 certain, 59 flagged uncertain), grammatical categories, and part-of-speech tags — one of the two machine-readable Etruscan dictionaries in existence. CC BY 4.0.
- `lexlep` — The Lexicon Leponticum (lexlep.univie.ac.at, University of Vienna; ed. Stifter, Salomon, Braun et al.) — the digital edition of Cisalpine Celtic epigraphy: 494 inscriptions in Lepontic and Cisalpine Gaulish, given in scholarly transliteration and joined to catalogs of the inscribed objects (typology, material, dating) and find sites (coordinates), with concordances to the Morandi and Solinas print editions. Made available for scientific use under noncommercial Creative Commons terms.
- `lexlep-words` — The dictionary of attested forms from the Lexicon Leponticum (University of Vienna; ed. Stifter, Salomon, Braun et al.) — a 628-word etymological lexicon of Lepontic and Cisalpine Gaulish, with grammatical analysis, morphemic breakdown, and etymological commentary per entry. Made available for scientific use under noncommercial Creative Commons terms.
- `open-etruscan` — OpenEtruscan — the Etruscan Machine Learning Corpus (OpenEtruscan Project / Edoardo Panichi): 6,567 Etruscan inscriptions, the only bulk machine-readable Etruscan corpus, drawing on the Larth corpus (Vico & Spanakis 2023) and extractions from CIE Vol. I. Each inscription carries the carved glyph stream and a scholarly transliteration, with English translations for 1,800 and date ranges for 307. CC BY 4.0.
- `sabellic-loans` — A curated set of 85 Latin lemmas with Sabellic sources — Oscan 48 (rufus, tofus, prope, Pompeii…), Umbrian 11 (omentum, Iguvium…), and Sabine 26 (hirpus, strena, Quirites, Nero…) — distinguishing explicit borrowings from derived forms, with the Old Italic script etyma kept verbatim. Compiled from English Wiktionary's borrowing and derivation data; CC BY-SA and GFDL (the Wiktionary dual license).
- `tir` — The Thesaurus Inscriptionum Raeticarum (University of Vienna; ed. Schumacher, Salomon, Kluge, Bajc, Braun) — the corpus of record for Raetic, a Tyrsenian language attested in Iron Age northern Italy and western Austria: 389 inscriptions, from rock-wall petrographs to votives in the Sanzeno and Magrè alphabets, with linked object and site records, in an actively edited online edition; many short inscriptions remain of honestly undetermined language. CC BY-SA 3.0 / GFDL, licensed for scientific use.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Etruscan inscriptions naming Larth?* — `nabu_search larth (lang: ett)`: CIE 1772 with both faces of the stone transcribed — the Tyrsenian shelves answer alongside the Sabellic ones on this desk.

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
