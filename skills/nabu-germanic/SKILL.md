---
name: nabu-germanic
description: "Methodological guidance for the germanic desk of a Nabu library (Germanicist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: germanic
  origin: generated
  sources: "aspr bosworth-toller cme corpus-gysseling corpus-oudnederlands dta eebo-tcp fornsvenska helipad iswoc menota menotec perseus-anglit proiel ref rem ren rundata ud"
---

# The Germanicist — the `germanic` desk

The Germanicist — Gothic and Old English to the Norse sagas and the runestones, the word-hoard of all three branches.

Gothic on the proiel/ud treebanks beside the West and North Germanic branches: Old English verse (ASPR) and prose (ISWOC) with Bosworth-Toller, Old Icelandic (IcePaHC via ud), Old Norwegian and the Poetic Edda (Menotec), the Medieval Nordic manuscript archive (Menota), the Corpus of Middle English (CME), early-modern English at scale (EEBO-TCP), Beowulf again in Klaeber's edition with its aligned English (perseus-anglit), the Old Saxon Heliand (HeliPaD), Middle High German manuscripts (ReM), Middle Low German and Low Rhenish (ReN), the German print era whole (DTA, 1473–1969), and the runic inscriptions (Rundata, dual-tagged epigraphy).

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `aspr` | ASPR — The Anglo-Saxon Poetic Records (Krapp & Dobbie; OTA 3009) | attribution |
| `bosworth-toller` | Bosworth-Toller — An Anglo-Saxon Dictionary (LINDAT dump) | attribution |
| `cme` | Corpus of Middle English Prose and Verse (Middle English Compendium, Univ. of Michigan) | open |
| `corpus-gysseling` | Corpus Gysseling — 13th-c. Early Middle Dutch, lemma+POS (INT/IvdNT) | research_private |
| `corpus-oudnederlands` | Corpus Oudnederlands — Old Dutch word material 475–1200 (INT/IvdNT) | research_private |
| `dta` | Deutsches Textarchiv (BBAW) | attribution |
| `eebo-tcp` | EEBO-TCP — Early English Books Online, Text Creation Partnership (Phases I–II) | open |
| `fornsvenska` | Fornsvenska textbanken — Old Swedish laws, prose and verse (Språkbanken Text) | attribution |
| `helipad` | HeliPaD — the Heliand Parsed Database (Walkden; Zenodo 4395040, v0.9) | attribution |
| `iswoc` | ISWOC Treebank — Old English texts | nc |
| `menota` | Menota — the Medieval Nordic Text Archive (clarino.uib.no) | attribution |
| `menotec` | Menotec — Old Norwegian treebanks + the Poetic Edda (Codex Regius), PROIEL scheme | nc |
| `perseus-anglit` | Perseus Digital Library — canonical Old English literature (Beowulf) | attribution |
| `proiel` | PROIEL Treebank | nc |
| `ref` | ReF — Referenzkorpus Frühneuhochdeutsch (1350–1650), v1.0.2 | attribution |
| `rem` | ReM — Referenzkorpus Mittelhochdeutsch (1050–1350), v2.1 | attribution |
| `ren` | ReN — Referenzkorpus Mittelniederdeutsch/Niederrheinisch (1200–1650), v1.1 | attribution |
| `rundata` | Rundata — Scandinavian Runic-text Database (SRDB, via rundata.info) | odbl |
| `ud` | Universal Dependencies — ancient treebanks | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `aspr` — The Anglo-Saxon Poetic Records — the complete corpus of Old English poetry, Beowulf included, with canonical line numbering.
- `bosworth-toller` — Bosworth-Toller's Anglo-Saxon Dictionary — 62,815 entries, the reference lexicon for Old English.
- `cme` — The Corpus of Middle English Prose and Verse (University of Michigan Library, the Middle English Compendium): 297 Middle English texts, the quotation base behind the Middle English Dictionary — Chaucer's Canterbury Tales and Troilus, Sir Gawain and the Green Knight, the York and Towneley mystery cycles, Piers Plowman in its versions, Ayenbite of Inwyt, alongside wills, gild records, and medical treatises. Re-normalized May 2026 to the common TCP schema by the MED editors; released with no restrictions on use or reuse.
- `corpus-gysseling` — The Corpus Gysseling of the Instituut voor de Nederlandse Taal: the 13th-century Early Middle Dutch originals (charters and literary manuscripts) that sourced the Vroegmiddelnederlands Woordenboek. It holds about 2,200 documents read line by line as the manuscripts are lineated, with abbreviations written out and gold-standard lemma and part-of-speech tagging. Each document is dated from the corpus's own dating and placed through its atlas place and region codes. The institute's terms are non-commercial with no redistribution grant, so the corpus is held for local research only and never redistributed.
- `corpus-oudnederlands` — The Corpus Oudnederlands of the Instituut voor de Nederlandse Taal (version 1.0, 2026): all surviving Old Dutch word material from 475 to 1200, in 90 TEI works ranging from runic inscriptions to glosses and fuller texts. Each work is cited attestation by attestation, with gold-standard lemma and part-of-speech tagging; foreign words are kept as form only. Works are dated and placed from the corpus's own headers. The institute's terms are non-commercial with no redistribution grant, so the corpus is held for local research only and never redistributed.
- `dta` — The Deutsches Textarchiv of the Berlin-Brandenburg Academy (BBAW), the reference corpus of German print: about 5,480 works from 1473 to 1969. Its core is a balanced set of some 1,480 works from 1600 to 1899 across literature, practical writing and science, widened by supplementary texts including newspapers and funeral sermons. Texts are read page by page and kept as printed, with original spellings, errors and abbreviations intact; the editors' normalization layers are not taken in. Each work is dated by its print year, and the pre-1650 Early New High German tail is marked as such. CC BY-SA 4.0.
- `eebo-tcp` — Early English Books Online, Text Creation Partnership: everything printed in England, Scotland, Ireland, Wales and British America 1473-1700 that the TCP's keyers hand-transcribed from the EEBO page images — 25,368 texts in wave 1 (Phase I; Phase II brings the corpus to 60,326). Milton, Raleigh, Bacon, Donne and Dryden beside the anonymous mass that carries the period: sermons, broadsides, petitions, civil-war tracts, almanacs, plague bills. Hand-keyed double-entry transcription (not OCR), each file carrying its imprint year and an explicit CC0 public-domain dedication.
- `fornsvenska` — Fornsvenska textbanken (Språkbanken Text, University of Gothenburg): the Old Swedish text bank — the medieval law codes beginning with Äldre Västgötalagen, older and younger religious prose, profane prose, the rhymed chronicles and the Eufemiavisorna, and the town and court records (tänkeböcker), covering Old Swedish from the 13th century to the early 16th. Sentence-segmented editions with per-text datings carried from the source descriptions. CC BY 4.0.
- `helipad` — HeliPaD — the Heliand Parsed Database (George Walkden): the Old Saxon Heliand, the 9th-century gospel harmony (manuscript C, Cotton Caligula A. VII), syntactically parsed — 5,968 verse lines and about 46,000 words in Penn-style constituency trees, with lemma and morphology on every word and the poem's metre and codicology (verse lines, caesurae, fitts, folios) marked within the trees. CC BY 4.0.
- `iswoc` — The ISWOC treebank — gold dependency annotation over Old English, Old French and Latin prose; its West-Saxon Mark serves the alignment hub.
- `menota` — The Medieval Nordic Text Archive (Menota): 91 medieval Nordic manuscripts, c. 1200-1700, transcribed at up to three levels per word (facsimile, diplomatic, normalized) by the Menota network of Nordic archives and universities under the University of Bergen/CLARINO — Laxdæla saga, the Codex Wormianus with its runic material, Konungs skuggsjá (the King's Mirror), the Old Norwegian homily book, the Landslǫg law manuscripts, Elis saga, and the diplomas. Old Icelandic, Old Norwegian, Old Swedish, Old Danish, and mixed Norse; MUFI character conventions; each manuscript dated by its catalogue origDate. The whole archive is CC BY-SA 4.0.
- `menotec` — The Menotec treebanks (Odd Einar Haugen et al., Universities of Bergen and Oslo) — seven Old Norwegian dependency treebanks plus the Poetic Edda of Codex Regius, 20,308 sentences with gold morphological and syntactic annotation in the PROIEL scheme: the Old Norwegian Homily Book, the King's Mirror, the Landslov, Óláfs saga, Pamphilus, and Strengleikar beside the Edda. CC BY-NC-SA 4.0, served through the CLARINO INESS portal.
- `perseus-anglit` — The Perseus Digital Library's canonical-angLit repository, which holds a single work: Beowulf in Frederick Klaeber's 1922 edition, with an aligned English translation that can be read side by side with the Old English. It sits beside the other Beowulf witness on the shelf as a separate edition, never merged with it. CC BY-SA 3.0 US.
- `proiel` — Gold dependency treebanks of the earliest Indo-European Bible translations — Greek NT, Vulgate, Gothic, Classical Armenian and Old Church Slavonic, morphologically analyzed to the token.
- `ref` — The Reference Corpus of Early New High German (Referenzkorpus Frühneuhochdeutsch): 190 texts / 3.1M tokens of diplomatically transcribed German from 1350-1650 — sermons, chronicles, legal and medical prose, private letters — each with morphological annotation and manuscript layout (page/column/line), the third rung of the Bochum reference-corpus ladder after Middle High German (ReM) and Middle Low German (ReN). CC BY-SA 4.0 (Bochum/Halle/Potsdam).
- `rem` — ReM — the Referenzkorpus Mittelhochdeutsch (Klein, Wegera, Dipper, Wich-Reif et al.): roughly 400 texts and some two million word forms of manually annotated Middle High German, 1050–1350 — the reference corpus of pre-print High German. The diplomatic manuscript transcription (long ſ, scribal marks) is kept intact alongside normalized forms and lemmas, cited by manuscript folio and line. CC BY-SA 4.0.
- `ren` — The Reference Corpus of Middle Low German / Lower Rhenish (Referenzkorpus Mittelniederdeutsch/Niederrheinisch, 1200–1650), v1.1 from the Hamburg/Münster project (DOI 10.25592/uhhfdm.9195) — charters, town statutes, chronicles, and devotional prose from manuscripts, prints, and inscriptions. 161 texts carry gold part-of-speech, morphology, and lemma annotation (about 1.49 million tokens); a further 74 are transcribed only (about 838,000 tokens). Middle Low German with a Lower Rhenish lane; citations follow the manuscript page, column, and line. CC BY 4.0.
- `rundata` — Rundata — the Scandinavian Runic-text Database (Samnordisk runtextdatabas, Uppsala): about 6,800 runic inscriptions from Sweden, Denmark, Norway, and the wider Norse diaspora, Proto-Norse through the medieval period. Each inscription offers up to five text lanes — the scholarly Latin transliteration, Old West Norse and runic Swedish normalizations, and English and Swedish translations — alongside dating, find-spot coordinates, carver, material, and bibliography. ODbL 1.0 with the Database Contents License; based on the Scandinavian Runic-text Database.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Where does Gothic guþ come from, and who are its cousins?* — `nabu_etym guþ (lang: got)`: Proto-Germanic *gudą with 64 cognates (nine attested in this library, counts shown: Gothic 𐌲𐌿𐌸 ×914, Old Norse guð ×1,337, Middle High German got ×6,995 …) and the PIE ancestors *ǵʰutós "libated" / *gʷʰew- "to venerate" above it.

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
