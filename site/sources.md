---
title: Sources & Licensing
permalink: /sources/
description: >-
  Every corpus and dictionary in the Nabu library, with upstream attribution
  and license terms, and the project's licensing philosophy.
---

Nabu is an aggregation of other people's scholarship. Every text in the
library exists because an upstream project digitized, edited, annotated,
and published it under terms that permit this kind of use; those projects
are credited here, and their license terms travel with every passage. The
maintained inventory, including sources evaluated but not (or not yet)
ingested, is
[docs/02-sources.md](https://github.com/arvicco/nabu/blob/main/docs/02-sources.md)
in the repository.

## The licensing model

Every document carries a license class, recorded as data at ingestion and
displayed on every surface — search hits, exports, alignment rows, and MCP
responses alike:

- **`open`** — public domain or CC0. No restrictions.
- **`attribution`** — CC BY or CC BY-SA class: redistributable with credit.
  Together with `open`, this covers roughly 99% of documents.
- **`nc`** — CC BY-NC-SA class (GRETIL, most treebanks): licensed for
  non-commercial use. Appropriate for private research, including
  AI-assisted reading; never redistributed by the tooling.
- **`research_private`** — sources whose terms (for instance CC BY-ND, or
  scholarly-use grants without a redistribution clause) do not fit the
  classes above. Held for personal research only, and excluded from the
  MCP surface by default: an AI client must opt in per call to see them.
  The Freising Manuscripts edition (CC BY-ND 2.5 SI) is the first source
  behind this gate.

Two further habits belong to this model. First, licenses are read from
upstream metadata wherever it is machine-readable (ORACC's per-project
license field, for example), never hardcoded, and per-document overrides
record cases where one collection carries differently licensed layers.
Second, texts an upstream later deletes are retained and remain searchable —
honestly labelled as retired upstream — under the license they were fetched
with.

This posture is deliberately conservative: the library is personal research
infrastructure, not a redistribution service, so it can hold non-commercial
and no-derivatives material lawfully while keeping the boundary explicit in
the data. Should any part of the collection ever face outward, the license
classes are the gate that decides what may pass.

## Corpus sources

All 34 sources below are synced and live as of 17 July 2026.

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `perseus-greek`, `perseus-latin` | [Perseus Digital Library](https://www.perseus.tufts.edu/) (PerseusDL canonical-greekLit / canonical-latinLit) | The classical Greek and Latin canons with English translations | CC BY-SA |
| `first1k-greek` | [First1KGreek, Open Greek &amp; Latin](https://opengreekandlatin.github.io/First1KGreek/) | Post-classical Greek prose, incl. Swete's Septuagint | CC BY-SA |
| `papyri-ddbdp` | [papyri.info](https://papyri.info/) — Duke Databank of Documentary Papyri | 61,414 documentary papyri | CC BY |
| `oracc` | [ORACC](https://oracc.museum.upenn.edu/), 33 projects incl. the State Archives of Assyria | Cuneiform transliterations with gold lemmatization | CC0 (per project); translation prose CC BY-SA |
| `gretil` | [GRETIL](https://gretil.sub.uni-goettingen.de/), Göttingen | 780 Sanskrit (and related) TEI editions | CC BY-NC-SA 4.0 |
| `proiel` | [PROIEL treebank](https://proiel.github.io/) | Parallel NT (Greek, Latin, Gothic, Armenian, OCS) + classical prose, gold-annotated | CC BY-NC-SA |
| `torot` | [TOROT](https://torottreebank.github.io/) — Tromsø OCS and Old Russian Treebank | OCS and Old East Slavic, gold-annotated | CC BY-NC-SA |
| `iswoc` | [ISWOC treebank](https://github.com/iswoc/iswoc-treebank), Oslo | Old English prose and the West-Saxon Gospels, gold-annotated | CC BY-NC-SA |
| `ud` | [Universal Dependencies](https://universaldependencies.org/) (nine ancient treebanks) | Latin (Aquinas), Vedic Sanskrit, Gothic, Greek, Old East Slavic (birchbark, RNC, Ruthenian), Old Irish glosses (St Gall Priscian, Würzburg — since 17 July 2026) | CC BY-SA / CC BY-NC-SA per treebank |
| `lexica` | [PerseusDL lexica](https://github.com/PerseusDL/lexica) | Liddell-Scott-Jones; Lewis &amp; Short | CC BY-SA 4.0 |
| `vulgate` | [open-bibles](https://github.com/seven1m/open-bibles) / [eBible.org](https://ebible.org/) (Tweedale text) | The complete Clementine Vulgate, 73 books | Public domain |
| `sblgnt` | [SBL Greek New Testament](https://sblgnt.com/) (SBL / Logos) | Critical edition of the Greek NT | CC BY 4.0 |
| `eng-web` | [eBible.org](https://ebible.org/) via open-bibles | World English Bible | Public domain |
| `aspr` | [Oxford Text Archive](https://ota.bodleian.ox.ac.uk/) record 3009 (Hidley / Macrae-Gibson e-text of Krapp &amp; Dobbie) | The complete Anglo-Saxon Poetic Records | CC BY-SA 3.0 |
| `bosworth-toller` | [Bosworth-Toller Anglo-Saxon Dictionary](https://bosworthtoller.com/) via [LINDAT/CLARIAH-CZ](https://lindat.mff.cuni.cz/repository/handle/11234/1-3532) | 62,815 Old English dictionary entries | CC BY 4.0 |
| `ccmh` | Corpus Cyrillo-Methodianum Helsingiense via [Kielipankki](https://www.kielipankki.fi/) (Language Bank of Finland) | Four OCS gospel codices, Suprasliensis, the Vitae | CC BY 4.0 |
| `goo300k`, `imp` | [CLARIN.SI](https://www.clarin.si/) (Erjavec, JSI; hdl [11356/1025](http://hdl.handle.net/11356/1025), [11356/1031](http://hdl.handle.net/11356/1031)) | Gold and silver-annotated historical Slovenian, 1584–1899 | CC BY 4.0 / CC BY-SA 4.0 |
| `freising` | [Brižinski spomeniki e-edition](https://nl.ijs.si/e-zrc/bs/) (ZRC SAZU / IJS) | The Freising Manuscripts, three transcription layers + translations | CC BY-ND 2.5 SI → `research_private` |
| `wiktionary-cu`, `wiktionary-recon` | [kaikki.org](https://kaikki.org/) (Wiktextract) from [Wiktionary](https://www.wiktionary.org/) | OCS lexicon; seven reconstruction dictionaries (PIE, Proto-Slavic, Proto-Germanic, Proto-West Germanic, Proto-Balto-Slavic, Proto-Italic, Proto-Indo-Iranian) with descendant trees; Old Irish, Middle Irish, and Middle Welsh extracts (since 17 July 2026) | CC BY-SA + GFDL |
| `coptic-scriptorium` | [Coptic Scriptorium](https://copticscriptorium.org/) | Sahidic and Bohairic Coptic corpora with gold annotation, 482 documents | CC BY per document (source class `nc`, most-restrictive-wins) |
| `mw` | [Cologne Digital Sanskrit Lexicon](https://www.sanskrit-lexicon.uni-koeln.de/) | Monier-Williams Sanskrit-English Dictionary (1899), 193,890 entries | CC BY-NC-SA 3.0 |
| `edh` | [Epigraphic Database Heidelberg](https://edh.ub.uni-heidelberg.de/) | 81,881 Latin inscriptions (upstream archived 2021 — a preservation snapshot) | CC BY-SA 4.0 |
| `iecor` | [IE-CoR](https://iecor.clld.org/) (lexibank/iecor via Zenodo) | The Indo-European cognacy database: 4,981 expert-curated cognate sets with loan events (synchronized 14 July 2026) | CC BY 4.0 |
| `liv` | [LiLa / CIRCSE LIV-LOD](https://lila-erc.eu/) | *Lexikon der indogermanischen Verben* linked-data edition: 305 PIE verbal etymons (synchronized 14 July 2026) | CC BY-SA 4.0 (with publisher permission) |
| `edl` | [LiLa / CIRCSE](https://lila-erc.eu/) | De Vaan, *Etymological Dictionary of Latin* (linked-data skeleton): 2,860 etymons (synchronized 14 July 2026) | CC BY-NC-SA 4.0 |
| `starling` | [StarLing / Tower of Babel](https://starlingdb.org/) (G. Starostin et al.) | Five etymological databases, 27,397 entries: Pokorny's IEW, Nikolayev's PIE database, Vasmer's dictionary of Russian (Trubachev ed.), Common Germanic, Baltic (synchronized 17 July 2026) | Written grant ("free for anybody to use … as long as the source is properly acknowledged"), per-base compiler credit carried on every surface |
| `sl-lexica` | [ZRC SAZU](https://www.zrc-sazu.si/) via [CLARIN.SI](https://www.clarin.si/) | Pleteršnik's *Slovensko-nemški slovar* (1894–95), the Janez Svetokriški lexicon, and the 16th-century Slovenian word inventory — 139,405 entries (synchronized 17 July 2026) | CC BY 4.0 |
| `damaskini` | [CLARIN.SI](https://www.clarin.si/) (hdl [11356/1441](http://hdl.handle.net/11356/1441)) | Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1: 23 gold-annotated witnesses, 15th–19th c., with English translations (synchronized 17 July 2026) | CC BY-SA 4.0 |
| `corph` | [CorPH — Corpus PalaeoHibernicum](https://chronhib.maynoothuniversity.ie/) (ERC ChronHib, Maynooth) | 76 Early Irish documents, 7th–10th c., gold-lemmatized — the library's first Old Irish (synchronized 17 July 2026) | MIT |
| `riig` | [RIIG — Recueil informatisé des inscriptions gauloises](https://riig.huma-num.fr/) (ANR, Ausonius/Bordeaux) | 428 Gaulish inscriptions, Gallo-Greek and Gallo-Latin, with French translations (synchronized 17 July 2026) | CC BY 4.0 (in-file grant) |
| `ogham` | [Ogham in 3D](https://ogham.celt.dias.ie/) v2.0 (DIAS / Maynooth) | ~500 ogham stones in real Ogham codepoints with transliteration layers (synchronized 17 July 2026) | Conflicting statements (site CC BY-NC-SA vs in-file CC BY 4.0) — held at the restrictive `nc` reading pending clarification |

## The local shelves

Four further registered sources hold no upstream at all — they are the
library's shelves for authored and acquired material, synchronized by
re-scanning local files rather than fetching. The language-dossier shelf
(`local-language`) carries the library's own per-language curation, 199
Markdown dossiers as of 17 July 2026. The local-library shelf
(`local-library`) files the owner's PDFs, scans, and offprints through
the `nabu ingest` command (which also accepts http(s) URLs, downloading
first and recording the address in the manifest); everything on it
defaults to the `research_private` class — catalogued and searchable
locally, never served or redistributed — and it holds its first 20
documents as of 17 July 2026. The source-dossier shelf (`local-source`)
carries a curated description of every registered source, 37 dossiers
served on the `nabu list` census. The notes shelf (`local-notes`)
records the owner's annotations on any citable URN through `nabu note`;
it awaits its first entry. Licenses on
these shelves belong to whatever the owner files there; the class system
above is the gate that keeps restricted personal material private.

## Acknowledgements

This library would be empty without the sustained, mostly under-funded work
of the projects above: the Perseus Digital Library and Open Greek &amp;
Latin; the Duke Databank and papyri.info; the ORACC consortium and its
constituent projects; the PROIEL, TOROT, and ISWOC treebank teams in Oslo
and Tromsø; the Universal Dependencies community; GRETIL at Göttingen; the
Corpus Cyrillo-Methodianum Helsingiense and Kielipankki; CLARIN.SI and
LINDAT/CLARIAH-CZ; the Bosworth-Toller digitization at Charles University;
the eZISS edition of the Freising Manuscripts; the Society of Biblical
Literature and Logos; eBible.org and the open-bibles collection; the Oxford
Text Archive; the Wiktionary community and the Wiktextract project; the
Cologne Digital Sanskrit Lexicon; Coptic Scriptorium; the Epigraphic
Database Heidelberg; the IE-CoR project; the LiLa (Linking Latin) /
CIRCSE group, whose linked-data editions carry LIV and de Vaan; George
Starostin and the StarLing / Tower of Babel project, with the compilers
of its constituent databases; ZRC SAZU, whose dictionaries carry the
Slovenian lexicographic tradition; the ChronHib project at Maynooth
(CorPH); the RIIG project at Ausonius / Bordeaux; and the Ogham in 3D
project at DIAS. Users of
this software are bound by, and should credit, these upstream projects
under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance TITUS, whose
scholarly-use terms grant no redistribution, and the Rahlfs Septuagint
under CATSS conditions).
