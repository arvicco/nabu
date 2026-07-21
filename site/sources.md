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

All 58 sources below are synced and live as of 19 July 2026. Grouped by the
owner's research desks rather than alphabetically — with each desk's member
shelves, license mix and sync status on one page — the same sources appear on
the [research axes]({{ '/axis/' | relative_url }}).

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `perseus-greek`, `perseus-latin` | [Perseus Digital Library](https://www.perseus.tufts.edu/) (PerseusDL canonical-greekLit / canonical-latinLit) | The classical Greek and Latin canons with English translations | CC BY-SA |
| `first1k-greek` | [First1KGreek, Open Greek &amp; Latin](https://opengreekandlatin.github.io/First1KGreek/) | Post-classical Greek prose, incl. Swete's Septuagint | CC BY-SA |
| `papyri-ddbdp` | [papyri.info](https://papyri.info/) — Duke Databank of Documentary Papyri | 61,414 documentary papyri | CC BY |
| `oracc` | [ORACC](https://oracc.museum.upenn.edu/), 38 projects incl. the State Archives of Assyria, the Achaemenid royal trilinguals (ario — Old Persian and Elamite) and the four ePSD2 corpora with the Ur III administrative mass | 104,722 cuneiform tablets with gold lemmatization (synchronized 19 July 2026) | CC0 (per project); translation prose CC BY-SA |
| `gretil` | [GRETIL](https://gretil.sub.uni-goettingen.de/), Göttingen | 780 Sanskrit (and related) TEI editions | CC BY-NC-SA 4.0 |
| `proiel` | [PROIEL treebank](https://proiel.github.io/) | Parallel NT (Greek, Latin, Gothic, Armenian, OCS) + classical prose, gold-annotated | CC BY-NC-SA |
| `torot` | [TOROT](https://torottreebank.github.io/) — Tromsø OCS and Old Russian Treebank | OCS and Old East Slavic, gold-annotated | CC BY-NC-SA |
| `iswoc` | [ISWOC treebank](https://github.com/iswoc/iswoc-treebank), Oslo | Old English prose and the West-Saxon Gospels, gold-annotated | CC BY-NC-SA |
| `ud` | [Universal Dependencies](https://universaldependencies.org/) (twelve ancient treebanks) | Latin (Aquinas, Perseus), Ancient Greek (Perseus), Vedic Sanskrit, Gothic, Greek, Old East Slavic (birchbark, RNC, Ruthenian), Old Irish glosses (St Gall Priscian, Würzburg), Hittite (HitTB — since 19 July 2026) | CC BY-SA / CC BY-NC-SA per treebank |
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

| `dcs` | [Digital Corpus of Sanskrit](https://github.com/OliverHellwig/sanskrit) (Hellwig) | 15,741 gold-lemmatized Sanskrit chapters across 270 texts, ~5.46M analyzed words (synchronized 18 July 2026) | CC BY 4.0 |
| `sarit` | [SARIT](https://sarit.indology.info/) | 78 scholarly TEI editions incl. a complete Southern-Recension Mahābhārata, Devanagari + IAST (synchronized 18 July 2026) | CC BY-SA (per file) |
| `suttacentral` | [SuttaCentral](https://suttacentral.net/) bilara-data | The Pali Tipiṭaka (Mahāsaṅgīti) + the Patna Dhammapada, with segment-aligned English (synchronized 18 July 2026) | CC0 (per publication) |
| `oshb` | [Open Scriptures Hebrew Bible](https://github.com/openscriptures/morphhb) | The Westminster Leningrad Codex — 39 books, 23,213 verses with full morphology and ketiv/qere, byte-verbatim Masoretic text (synchronized 18 July 2026) | Text public domain; morphology CC BY 4.0 |
| `diorisis` | [Diorisis Ancient Greek Corpus](https://doi.org/10.6084/m9.figshare.6187256) (Vatri &amp; McGillivray) | 764 lemmatized second editions of the Greek canon, ~10.2M words — the library's first silver-tier source, labeled as such (synchronized 18 July 2026) | CC BY-SA 3.0 US (in-file) |
| `aes` | [Ancient Egyptian Sentences](https://github.com/simondschweitzer/aes) (TLA/BBAW snapshot) | 13,026 Egyptian texts / 101,793 gold-lemmatized sentences — Pyramid Texts to Sinuhe to medical papyri — with aligned German (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `aed` | [Ägyptische Wortliste](https://github.com/simondschweitzer/aed-tei) (TLA/BBAW) | 35,052 Egyptian dictionary entries keyed by the corpus's own lemma ids (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `tla-hf` | [Thesaurus Linguae Aegyptiae](https://huggingface.co/thesaurus-linguae-aegyptiae) official datasets | 13,383 Demotic + 3,606 Late Egyptian sentences with German — the only bulk demotic anywhere (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `ccl` | [Comprehensive Coptic Lexicon](https://refubium.fu-berlin.de/handle/fub188/27813) (BBAW/DDGLC) | 11,284 Coptic dictionary entries + the ORAEC egy↔cop crosswalk as etymology edges (synchronized 18 July 2026) | CC BY-SA 4.0 (in-file); crosswalk CC0 |
| `open-etruscan` | [OpenEtruscan](https://doi.org/10.5281/zenodo.20075836) | 6,248 Etruscan inscriptions with English siblings (synchronized 18 July 2026) | CC BY 4.0 |
| `larth-etp` | [Larth / Etruscan Texts Project glossary](https://github.com/GianlucaVico/Larth-Etruscan-NLP) | The ETP scholarly Etruscan glossary, 1,122 entries (synchronized 18 July 2026) | CC BY 4.0 |
| `ceipom` | [CEIPoM](https://doi.org/10.5281/zenodo.4759134) (Pitts) | 3,871 pre-Roman-Italy texts — Oscan, Messapic, Venetic, Umbrian, South Picene, Faliscan, archaic Latin — lemmatized, dated, geolocated; incl. the Fibula Praenestina and the complete Iguvine Tables (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `itant` | [Corpus ItAnt](https://github.com/DigItAnt/Corpus_ItAnt) (CNR-ILC/UniFI) | 501 Oscan + 9 Lepontic critical editions with English/Italian translations (synchronized 18 July 2026) | CC BY-NC-SA 4.0 |
| `sabellic-loans` | en.wiktionary curation | 85 Latin lemmas with Oscan/Umbrian/Sabine etyma, loan-flagged (curated 18 July 2026) | CC BY-SA + GFDL |
| `lexlep`, `lexlep-words` | [Lexicon Leponticum](https://lexlep.univie.ac.at/) (Vienna) | 494 Cisalpine Celtic inscriptions + the 627-word Lepontic lexicon with morphemic analyses (synchronized 18 July 2026) | Conflicting statements (terms CC BY-SA 3.0 vs footer NC) — held at `nc` pending clarification |
| `tir` | [Thesaurus Inscriptionum Raeticarum](https://tir.univie.ac.at/) (Vienna) | 389 Raetic inscriptions — the corpus of record (synchronized 18 July 2026) | Same conflicting statements — held at `nc` |
| `isicily` | [I.Sicily](https://github.com/ISicily/ISicily) (Prag, Oxford / ERC Crossreads) | 5,074 inscriptions of ancient Sicily across all its languages — incl. Sicel, Elymian, Sicilian Punic and Mamertine Oscan in their only machine-readable form (synchronized 18 July 2026) | CC BY 4.0 |

| `tlhdig` | [TLHdig](https://www.hethiter.net/) (Thesaurus Linguarum Hethaeorum digitalis, Hethitologie-Portal Mainz) | The Hittite corpus: 23,486 tablet manuscripts in 663 CTH compositions — >98% of published Hittite fragments, with cuneiform, transliteration and candidate morphology (synchronized 19 July 2026) | CC BY 4.0 |
| `cdli` | [CDLI](https://cdli.mpiwg-berlin.mpg.de/) (Cuneiform Digital Library Initiative) | The universal cuneiform catalog: 353,156 artifacts — 135,201 transliterations plus catalog records for the whole artifact space, proto-cuneiform to Achaemenid, with periods, proveniences and collections as browsable axes (2023 snapshot, synchronized 19 July 2026) | Bespoke open grant (attribution; images excluded) |
| `ebl` | [electronic Babylonian Library](https://www.ebl.lmu.de/) Fragmentarium (LMU Munich) | 23,288 tablet fragments from the museum drawers — ~326k lines with inline English translations, 79.9% cross-linked to their CDLI records (2023 snapshot, synchronized 19 July 2026) | Held at CC BY-NC-SA 4.0 (the data paper's grant) pending clarification of the deposit's CC BY field |
| `cuc` | [Copenhagen Ugaritic Corpus](https://github.com/DT-UCPH/cuc) (CACCHT) | 279 Ugaritic tablets / 27,770 words — most of the KTU corpus, independently re-encoded, with per-sign cuneiform and damage flags (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `peshitta` | [ETCBC peshitta](https://github.com/ETCBC/peshitta) | The Peshitta Old Testament incl. deuterocanon — 65 books / 31,341 verses; the Syriac leg of the verse-alignment hub (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `syriac-corpus` | [Digital Syriac Corpus](https://syriaccorpus.org/) (Srophé) | 632 classical Syriac TEI documents — a millennium of literature (synchronized 19 July 2026) | CC BY 4.0 (per file) |
| `etcsl` | [ETCSL](https://etcsl.orinst.ox.ac.uk/) (Oxford, via the OTA/LLDS record) | The Electronic Text Corpus of Sumerian Literature: 394 hand-lemmatized composites + 381 English prose translations (synchronized 19 July 2026) | CC BY-NC-SA 3.0 |
| `hebrew-lexicon` | [OpenScriptures HebrewLexicon](https://github.com/openscriptures/HebrewLexicon) | Two dictionaries: 9,299 augmented-Strong entries (every OSHB lemma resolves) + the 11,845-entry BDB outline with print-page anchors (synchronized 18 July 2026) | CC BY 4.0 |
| `sdbh` | [UBS Semantic Dictionary of Biblical Hebrew](https://github.com/ubsicap/ubs-open-license) | 7,932 entries with semantic domains and 260,813 verse-level scripture references (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `sefaria` | [Sefaria](https://www.sefaria.org/) (Sefaria-Export, named versions only) | The Targum shelf: Onkelos, Jonathan on the Prophets, the Writings targums — 103 documents / 57,095 Aramaic verses, verse-aligned to the Tanakh (synchronized 18 July 2026) | Per version (PD / CC0 / CC BY / CC BY-SA; NC versions carried as `nc`) |
| `bhsa` | [ETCBC BHSA](https://github.com/ETCBC/bhsa) | The Hebrew Bible with full clause/phrase syntax, ketiv-qere and per-lexeme glosses — 426,590 words (synchronized 18 July 2026) | CC BY-NC 4.0 |
| `dss` | [ETCBC dss](https://github.com/ETCBC/dss) (Abegg/Bowley/Cook) | The Dead Sea Scrolls: 1,001 scrolls, 500,995 words, biblical and non-biblical, with text-critical flags intact (synchronized 18 July 2026) | CC BY-NC 4.0 (Abegg's grant) |
| `iip` | [Inscriptions of Israel/Palestine](https://github.com/Brown-University-Library/iip-texts) (Brown) | 5,499 inscriptions, Hebrew/Aramaic/Greek/Latin, ~500 BCE–640 CE (synchronized 18 July 2026) | CC BY-NC 4.0 |

## The local shelves

Four further registered sources hold no upstream at all — they are the
library's shelves for authored and acquired material, synchronized by
re-scanning local files rather than fetching. The language-dossier shelf
(`local-language`) carries the library's own per-language curation, one
Markdown dossier per language code. The local-library shelf
(`local-library`) files the owner's PDFs, scans, and offprints through
the `nabu ingest` command (which also accepts http(s) URLs, downloading
first and recording the address in the manifest); everything on it
defaults to the `research_private` class — catalogued and searchable
locally, never served or redistributed. The source-dossier shelf
(`local-source`) carries a curated description of every registered
source, served on the `nabu list` census. The notes shelf
(`local-notes`) records the owner's annotations on any citable URN
through `nabu note`. What these shelves hold is, by design, the owner's
private business — their contents and counts appear nowhere public.
Licenses on
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
(CorPH); the RIIG project at Ausonius / Bordeaux; the Ogham in 3D
project at DIAS; the Hethitologie-Portal Mainz and the TLHdig team; the
Cuneiform Digital Library Initiative; the electronic Babylonian Library
at LMU Munich; the ETCBC at the Vrije Universiteit Amsterdam, whose
text-fabric editions carry the BHSA, the Scrolls and the Peshitta; the
CACCHT project in Copenhagen; the Srophé / Digital Syriac Corpus
editors; and the ETCSL project at Oxford with the Oxford Text Archive. Users of
this software are bound by, and should credit, these upstream projects
under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance TITUS, whose
scholarly-use terms grant no redistribution, and the Rahlfs Septuagint
under CATSS conditions).
