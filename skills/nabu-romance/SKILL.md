---
name: nabu-romance
description: "Methodological guidance for the romance desk of a Nabu library (Romanist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: romance
  origin: generated
  sources: "aranese bdcamoes bfm bim-sahcoba cantigas corpus-corporum croala ctilc cv-sardinian derom digiliblt disco lo-congres openmgh osta salom ud"
---

# The Romanist — the `romance` desk

The Romanist — the Latin-to-vernacular continuum, charter Latin to Roland to the troubadours.

The Latin-to-vernacular continuum: CroALa's medieval and neo-Latin opens the desk; late-antique prose, the MGH critical editions, and the Old French treebanks and texts join as their shelves land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `aranese` | ES-OC Parallel Corpus — Spanish–Aranese (BSC projecte-aina, WMT24) | attribution |
| `bdcamoes` | BDCamões — Corpus of Portuguese Literary Documents, Part I (PORTULAN CLARIN) | attribution |
| `bfm` | Base de français médiéval — BFM2022 (ENS de Lyon / IHRIM) | attribution |
| `bim-sahcoba` | BIM/SAHCOBA — Syntactically Annotated Historical Corpus in Basque (HiTZ, University of the Basque Country) | attribution |
| `cantigas` | Cantigas Medievais Galego-Portuguesas (Projeto Littera) | attribution |
| `corpus-corporum` | Corpus Córporum — Patrologia Latina (mlat.uzh.ch, Univ. of Zurich) | nc |
| `croala` | Croatiae auctores Latini — CroALa (Jovanović, ed.) | attribution |
| `ctilc` | CTILC public-domain works slice — Corpus Textual Informatitzat de la Llengua Catalana (IEC) | attribution |
| `cv-sardinian` | Common Voice Sardinian sentence text (the sc sentence collector) | open |
| `derom` | DÉRom — Dictionnaire Étymologique Roman (ATILF/Ortolang) | nc |
| `digiliblt` | digilibLT — Biblioteca digitale di testi latini tardoantichi (CIRCSE CoNLL-U) | attribution |
| `disco` | DISCO — Diachronic Spanish Sonnet Corpus (Ruiz Fabo et al., v5.0) | attribution |
| `lo-congres` | Lo Congrès Occitan news corpus (six dialects, French-aligned) | attribution |
| `openmgh` | openMGH — Monumenta Germaniae Historica editions (MGH / BSB, digital MGH) | attribution |
| `osta` | OSTA — Old Spanish Textual Archive (Hispanic Seminary of Medieval Studies) | nc |
| `salom` | Şalom Ladino articles text corpus (Col·lectivaT / Sephardic Center of Istanbul) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `aranese` — A Spanish-Aranese parallel corpus of ~420,000 aligned sentence pairs (projecte-aina): Aranese, the Val d'Aran variety of Gascon Occitan co-official in Catalonia, beside its Spanish source sentences. Largely machine-generated with Apertium (upstream's own statement — held as synthetic parallel data, never as attested usage). CC BY-SA 4.0.
- `bdcamoes` — BDCamões Part I: 127 Portuguese literary works (~3.1M words) from the Digital Library of Camões IP — drama from Gil Vicente (1517) through Garrett, novels of Camilo and Herculano, essays and poetry into the early 20th century, each work dated. CC-BY on Part I; Part II remains under restrictive terms and is not held.
- `bfm` — The Base de français médiéval (ENS de Lyon / IHRIM), corpus BFM2022 — 219 complete TEI texts totaling about 6.45 million words of medieval French, from the Strasbourg Oaths (842) to the end of the fifteenth century: the Old French text mass, roughly half verse and half prose, with direct speech marked and morphosyntactic and lemma annotation. The reading texts are public domain; the digital editions ride France's open Licence Ouverte (Etalab), attribution required.
- `cantigas` — Cantigas Medievais Galego-Portuguesas (Projeto Littera, Instituto de Estudos Medievais, FCSH/NOVA Lisbon; coordinated by Graça Videira Lopes and Manuel Pedro Ferreira) — the complete secular lyric in Old Galician-Portuguese: about 1,680 cantigas de amigo, de amor and de escárnio e maldizer, plus lais, tenções, pastorelas and sirventeses, from the three medieval songbooks (Cancioneiro da Ajuda, da Biblioteca Nacional, da Vaticana) in the Littera critical edition, with authors, manuscript sigla and rubrics. Free for any use with full attribution to the project.
- `corpus-corporum` — Migne's Patrologia Latina as held by Corpus Corporum, the Zurich Latin meta-repository: 5,277 patristic and medieval Latin works by 1,528 authors spanning 105-1847 CE — the church fathers (Augustine, Jerome, Gregory the Great), monastic rules, chronicles, sermons, hagiography, and the editorial prefaces of the 221-volume 1844-1864 series. Digitized from the non-critical 16th-18th-century editions Migne reprinted (OCR, upstream's own caveat); Migne column references ride each passage. The Zurich transcription layer is non-commercial; most underlying texts are public domain.
- `croala` — 309,180 passages; eyeballed via urn:nabu:croala:albert-i-inscr:d1.p1 + random passages — the string-place crash found and fixed in that verification). Sparse GitFetch of github.com/nevenjovanovic/croatiae-auctores-latini-textus scoped to the cone [txts, LICENSE.md, README.md]: a blobless no-checkout clone (the DCS/GLAUx recipe), skipping the schemas/ scripts/ oXygen cruft. One file ~6 MB — why the parser streams.
- `ctilc` — The public-domain slice of the Corpus Textual Informatitzat de la Llengua Catalana (IEC): 967 Catalan works — 348 literary (poetry, drama, novel; the Renaixença era onward) and 619 non-literary (essays, press, science) — mostly 19th-early-20th-century printed books whose authors entered the public domain, with genre, dialect variant (central, baleàric, valencià…) and publication year on every work. Mandatory IEC citation; digitization offered under an (unnamed) Creative Commons wrapper.
- `cv-sardinian` — The Common Voice Sardinian sentence collection: 5,237 modern Sardinian sentences gathered by Mozilla's volunteer community as prompts for speech recording — everyday prose in current orthography. Text layer only (CC0); the audio side is not held.
- `derom` — The Dictionnaire Étymologique Roman (DÉRom, dir. Éva Buchi and Wolfgang Schweickard; ATILF, CNRS/Université de Lorraine and Universität des Saarlandes) — the reference comparative-method reconstruction of Proto-Romance. Each article reconstructs one etymon (*/ˈlakt-e/ "milk", */kaˈβall-u/ "horse") strictly from the Romance evidence itself, with per-language reflex sections spanning the whole family — Romanian, Dalmatian, Italian, Sardinian, Friulian, Romansh, French, Occitan, Catalan, Spanish, Asturian, Galician, Portuguese and their historical stages — each reflex cited against the standard etymological literature. The etymons feed the library's etymology surfaces as Proto-Romance (the roa:pro lect), beside the Wiktionary-derived and expert-curated witnesses. Published openly through the Ortolang repository under CC BY-NC-SA 4.0.
- `digiliblt` — digilibLT — the Biblioteca digitale di testi latini tardoantichi (Università del Piemonte Orientale, Vercelli): 373 late-antique secular Latin prose texts of the 2nd–7th centuries AD — Ammianus, the grammarians, the agrimensores, the jurists — the transition band between classical and medieval Latin. This edition of the corpus is machine-lemmatized and part-of-speech tagged, with links into the LiLa Latin lemma bank on every token. CC BY-SA 4.0, crediting digilibLT and CIRCSE/LiLa.
- `disco` — The Diachronic Spanish Sonnet Corpus (Ruiz Fabo, Bermúdez Sabel, Calvo Tello & Martínez Cantón): 4,530 sonnets by 1,216 authors from Spain and Latin America, 15th through 20th century — the sonnet tradition from the Golden Age masters to the modernistas, one TEI file per author. Each sonnet carries its stanza architecture and per-line metrical, rhyme and enjambment annotation (machine-derived, labelled as such), and each author a short prosopography — birth and death centuries, birthplace, source edition. CC BY 4.0.
- `lo-congres` — Lo Congrès permanent de la lenga occitana's classroom sentence corpus: 5,152 French-Occitan sentence pairs across six written dialect norms (auvernhat, gascon, lengadocian, lemosin, provençau, vivaroaupenc) — the same French sentence rendered in each dialect, a compact matrix of modern written Occitan variation. CC BY 4.0.
- `openmgh` — The Monumenta Germaniae Historica critical editions in TEI — the foundational scholarly editions of medieval Europe's historiography. The SS rer. Germ. series carries the classic narrative sources of the Frankish and German Middle Ages (Einhard's Life of Charlemagne, the royal annals, Widukind, Thietmar of Merseburg, Otto of Freising); the second wave adds the late-antique Auctores antiquissimi (Jordanes, Cassiodorus), the Merovingian historians and saints' lives (SS rer. Merov., around Gregory of Tours' world), imperial charters (Diplomata), Middle High German verse chronicles (Deutsche Chroniken), the investiture-contest polemics (Libelli de lite), and the Quellen zur Geistesgeschichte. Mostly Latin with a German lane; page-anchored citations against the printed editions. CC BY 4.0 from the digital MGH.
- `osta` — The Old Spanish Textual Archive (Hispanic Seminary of Medieval Studies; Gago Jover & Pueyo Mena): 663 semi-paleographic transcriptions of medieval Spanish manuscripts and incunabula — the foundational machine-readable record of Old Spanish. Bibles, chronicles, legal codes, scientific treatises and literary prose, each transcribed codex-by-codex in the Seminary's curly-brace convention with folio and column milestones kept; a lemmatized token stream accompanies part of the collection, and the Seminary's own bibliographic tables carry per-work authors, datings and the PhiloBiblon crosswalk. Mostly Castilian, with Leonese, Navarro-Aragonese, Galician-Portuguese and Latin layers. CC BY-NC-SA 4.0.
- `salom` — Judeo-Spanish (Ladino) press prose: 10,685 sentences from Şalom, the Istanbul Sephardic community's newspaper — 2022 articles in Latin-script Ladino, the living written register of the language. CC BY 4.0 (Col·lectivaT).
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Who sang of Ragusa in Latin?* — `nabu_search ragusa (lang: lat)`: Croatian Latin verse from the CroALa shelf (live-verified 2026-07-25): Filelfo's 1470 Ragusaeis (AFFECTUS RAGVSA TVAE CLARISSIMA LAVDI) and Palmotić's carmina — the medieval-Latin edge of the continuum, positionally cited (d1.d2.l198) for nabu_show.

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
