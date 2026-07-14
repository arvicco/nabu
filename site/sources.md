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

All 25 sources below are synced and live as of 14 July 2026.

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `perseus-greek`, `perseus-latin` | [Perseus Digital Library](https://www.perseus.tufts.edu/) (PerseusDL canonical-greekLit / canonical-latinLit) | The classical Greek and Latin canons with English translations | CC BY-SA |
| `first1k-greek` | [First1KGreek, Open Greek &amp; Latin](https://opengreekandlatin.github.io/First1KGreek/) | Post-classical Greek prose, incl. Swete's Septuagint | CC BY-SA |
| `papyri-ddbdp` | [papyri.info](https://papyri.info/) — Duke Databank of Documentary Papyri | 61,389 documentary papyri | CC BY |
| `oracc` | [ORACC](https://oracc.museum.upenn.edu/), 33 projects incl. the State Archives of Assyria | Cuneiform transliterations with gold lemmatization | CC0 (per project); translation prose CC BY-SA |
| `gretil` | [GRETIL](https://gretil.sub.uni-goettingen.de/), Göttingen | 780 Sanskrit (and related) TEI editions | CC BY-NC-SA 4.0 |
| `proiel` | [PROIEL treebank](https://proiel.github.io/) | Parallel NT (Greek, Latin, Gothic, Armenian, OCS) + classical prose, gold-annotated | CC BY-NC-SA |
| `torot` | [TOROT](https://torottreebank.github.io/) — Tromsø OCS and Old Russian Treebank | OCS and Old East Slavic, gold-annotated | CC BY-NC-SA |
| `iswoc` | [ISWOC treebank](https://github.com/iswoc/iswoc-treebank), Oslo | Old English prose and the West-Saxon Gospels, gold-annotated | CC BY-NC-SA |
| `ud` | [Universal Dependencies](https://universaldependencies.org/) (seven ancient treebanks) | Latin (Aquinas), Vedic Sanskrit, Gothic, Greek, Old East Slavic (birchbark, RNC, Ruthenian) | CC BY-SA / CC BY-NC-SA per treebank |
| `lexica` | [PerseusDL lexica](https://github.com/PerseusDL/lexica) | Liddell-Scott-Jones; Lewis &amp; Short | CC BY-SA 4.0 |
| `vulgate` | [open-bibles](https://github.com/seven1m/open-bibles) / [eBible.org](https://ebible.org/) (Tweedale text) | The complete Clementine Vulgate, 73 books | Public domain |
| `sblgnt` | [SBL Greek New Testament](https://sblgnt.com/) (SBL / Logos) | Critical edition of the Greek NT | CC BY 4.0 |
| `eng-web` | [eBible.org](https://ebible.org/) via open-bibles | World English Bible | Public domain |
| `aspr` | [Oxford Text Archive](https://ota.bodleian.ox.ac.uk/) record 3009 (Hidley / Macrae-Gibson e-text of Krapp &amp; Dobbie) | The complete Anglo-Saxon Poetic Records | CC BY-SA 3.0 |
| `bosworth-toller` | [Bosworth-Toller Anglo-Saxon Dictionary](https://bosworthtoller.com/) via [LINDAT/CLARIAH-CZ](https://lindat.mff.cuni.cz/repository/handle/11234/1-3532) | 62,815 Old English dictionary entries | CC BY 4.0 |
| `ccmh` | Corpus Cyrillo-Methodianum Helsingiense via [Kielipankki](https://www.kielipankki.fi/) (Language Bank of Finland) | Four OCS gospel codices, Suprasliensis, the Vitae | CC BY 4.0 |
| `goo300k`, `imp` | [CLARIN.SI](https://www.clarin.si/) (Erjavec, JSI; hdl [11356/1025](http://hdl.handle.net/11356/1025), [11356/1031](http://hdl.handle.net/11356/1031)) | Gold and silver-annotated historical Slovenian, 1584–1899 | CC BY 4.0 / CC BY-SA 4.0 |
| `freising` | [Brižinski spomeniki e-edition](https://nl.ijs.si/e-zrc/bs/) (ZRC SAZU / IJS) | The Freising Manuscripts, three transcription layers + translations | CC BY-ND 2.5 SI → `research_private` |
| `wiktionary-cu`, `wiktionary-recon` | [kaikki.org](https://kaikki.org/) (Wiktextract) from [Wiktionary](https://www.wiktionary.org/) | OCS lexicon; seven reconstruction dictionaries (PIE, Proto-Slavic, Proto-Germanic, Proto-West Germanic, Proto-Balto-Slavic, Proto-Italic, Proto-Indo-Iranian) with descendant trees | CC BY-SA + GFDL |
| `coptic-scriptorium` | [Coptic Scriptorium](https://copticscriptorium.org/) | Sahidic and Bohairic Coptic corpora with gold annotation, 482 documents | CC BY per document (source class `nc`, most-restrictive-wins) |
| `mw` | [Cologne Digital Sanskrit Lexicon](https://www.sanskrit-lexicon.uni-koeln.de/) | Monier-Williams Sanskrit-English Dictionary (1899), 193,890 entries | CC BY-NC-SA 3.0 |
| `edh` | [Epigraphic Database Heidelberg](https://edh.ub.uni-heidelberg.de/) | 81,856 Latin inscriptions (upstream archived 2021 — a preservation snapshot) | CC BY-SA 4.0 |

## Registered, awaiting first synchronization

Adapters for three further sources are built and tested as of 14 July 2026;
they hold no live rows and enter the live counts once their first
synchronization is run and verified:

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `iecor` | [IE-CoR](https://iecor.clld.org/) (lexibank/iecor via Zenodo) | The Indo-European cognacy database: 4,981 expert-curated cognate sets with loan events | CC BY 4.0 |
| `liv` | [LiLa / CIRCSE LIV-LOD](https://lila-erc.eu/) | *Lexikon der indogermanischen Verben* linked-data edition: 305 PIE verbal etymons | CC BY-SA 4.0 (with publisher permission) |
| `edl` | [LiLa / CIRCSE](https://lila-erc.eu/) | De Vaan, *Etymological Dictionary of Latin* (linked-data skeleton): 2,860 etymons | CC BY-NC-SA 4.0 |

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
Cologne Digital Sanskrit Lexicon; Coptic Scriptorium; and the Epigraphic
Database Heidelberg. Users of this software are bound by, and should credit,
these upstream projects under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance TITUS, whose
scholarly-use terms grant no redistribution, and the Rahlfs Septuagint
under CATSS conditions).
