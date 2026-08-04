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

All 109 sources below are synced and live as of 4 August 2026, listed
alphabetically by source id. The same sources grouped by research desk —
each desk's member shelves, license mix and sync status on one page —
appear on the [research axes]({{ '/axis/' | relative_url }}).

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `aed` | [Ägyptische Wortliste](https://github.com/simondschweitzer/aed-tei) (TLA/BBAW) | 35,052 Egyptian dictionary entries keyed by the corpus's own lemma ids (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `aes` | [Ancient Egyptian Sentences](https://github.com/simondschweitzer/aes) (TLA/BBAW snapshot) | 13,026 Egyptian texts / 101,793 gold-lemmatized sentences — Pyramid Texts to Sinuhe to medical papyri — with aligned German (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `aozora` | [Aozora Bunko 青空文庫](https://www.aozora.gr.jp/) | The Japanese public-domain library: 16,004 works, ruby-annotated — in-copyright works excluded before discovery (synchronized 21 July 2026) | Public domain (取り扱い規準 grant) |
| `aspr` | [Oxford Text Archive](https://ota.bodleian.ox.ac.uk/) record 3009 (Hidley / Macrae-Gibson e-text of Krapp &amp; Dobbie) | The complete Anglo-Saxon Poetic Records | CC BY-SA 3.0 |
| `babelstone-ids` | [BabelStone IDS](https://www.babelstone.co.uk/CJK/IDS.TXT) (Andrew West) | Ideographic Description Sequences for 97,680 CJK characters | Public-domain dedication |
| `baxter-sagart` | [Baxter-Sagart Old Chinese](https://github.com/yawnoc/baxter-sagart-old-chinese) | The Baxter &amp; Sagart 2014 Old Chinese reconstruction | CC BY 4.0 (the authors' grant) |
| `betamasaheft-works` | [Beta maṣāḥəft](https://betamasaheft.eu/) (Hiob-Ludolf-Zentrum, Univ. Hamburg) | The Gəʿəz text shelf: 3,796 text-bearing records at verse grain — the Ethiopic Bible, 1 Enoch and Jubilees (complete only in Gəʿəz), the Kebra Nagast, royal chronicles (synchronized 26 July 2026) | CC BY-SA 4.0 (per-document in-file grants) |
| `bfm` | [Base de français médiéval](https://bfm.ens-lyon.fr/) (ENS de Lyon / IHRIM, via NAKALA) | BFM2022: Old and Middle French from the 842 Serments de Strasbourg through the 15th century, TEI with lemmas (silver): 6.4M words (synchronized 25 July 2026) | Licence Ouverte / Etalab (8 files' critical apparatus, CC BY-NC-SA, is excluded at parse) |
| `bhsa` | [ETCBC BHSA](https://github.com/ETCBC/bhsa) | The Hebrew Bible with full clause/phrase syntax, ketiv-qere and per-lexeme glosses — 426,590 words (synchronized 18 July 2026) | CC BY-NC 4.0 |
| `bosworth-toller` | [Bosworth-Toller Anglo-Saxon Dictionary](https://bosworthtoller.com/) via [LINDAT/CLARIAH-CZ](https://lindat.mff.cuni.cz/repository/handle/11234/1-3532) | 62,815 Old English dictionary entries | CC BY 4.0 |
| `cantigas` | [Cantigas Medievais Galego-Portuguesas](https://cantigas.fcsh.unl.pt/) (Projeto Littera, NOVA FCSH) | The complete secular Galician-Portuguese lyric — 1,682 cantigas at verse grain with authorship, genre and the corpus-wide cancioneiro concordance (synchronized 2 August 2026; republished as the `roa-opt/cantigas` dataset in nabu-data) | Written any-use grant with attribution |
| `cbeta` | [CBETA](https://www.cbeta.org/) (cbeta-org/xml-p5) | The Chinese Buddhist canon: Taishō + Xuzangjing in TEI P5 (synchronized 20 July 2026) | CC BY-NC-SA 4.0 |
| `ccl` | [Comprehensive Coptic Lexicon](https://refubium.fu-berlin.de/handle/fub188/27813) (BBAW/DDGLC) | 11,284 Coptic dictionary entries + the ORAEC egy↔cop crosswalk as etymology edges (synchronized 18 July 2026) | CC BY-SA 4.0 (in-file); crosswalk CC0 |
| `ccmh` | Corpus Cyrillo-Methodianum Helsingiense via [Kielipankki](https://www.kielipankki.fi/) (Language Bank of Finland) | Four OCS gospel codices, Suprasliensis, the Vitae | CC BY 4.0 |
| `cdli` | [CDLI](https://cdli.mpiwg-berlin.mpg.de/) (Cuneiform Digital Library Initiative) | The universal cuneiform catalog: 353,156 artifacts — 135,201 transliterations plus catalog records for the whole artifact space, proto-cuneiform to Achaemenid, with periods, proveniences and collections as browsable axes (2023 snapshot, synchronized 19 July 2026) | Bespoke open grant (attribution; images excluded) |
| `ceipom` | [CEIPoM](https://doi.org/10.5281/zenodo.4759134) (Pitts) | 3,871 pre-Roman-Italy texts — Oscan, Messapic, Venetic, Umbrian, South Picene, Faliscan, archaic Latin — lemmatized, dated, geolocated; incl. the Fibula Praenestina and the complete Iguvine Tables (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `cldf-spine` | [Concepticon](https://concepticon.clld.org/) + [Glottolog](https://glottolog.org/) | The thin CLDF reference spine: concept ids and languoid ids the WOLD/CLICS rows resolve through (a feature module — no documents of its own) | CC BY 4.0 |
| `clics` | [CLICS³](https://clics.clld.org/) | The cross-linguistic colexification network: 2,919 concepts / 4,228 weighted edges over ~3,156 varieties (synchronized 26 July 2026) | CC BY 4.0 |
| `coptic-scriptorium` | [Coptic Scriptorium](https://copticscriptorium.org/) | Sahidic and Bohairic Coptic corpora with gold annotation, 482 documents | CC BY per document (source class `nc`, most-restrictive-wins) |
| `corph` | [CorPH — Corpus PalaeoHibernicum](https://chronhib.maynoothuniversity.ie/) (ERC ChronHib, Maynooth) | 76 Early Irish documents, 7th–10th c., gold-lemmatized — the library's first Old Irish (synchronized 17 July 2026) | MIT |
| `croala` | [CroALa — Croatiae auctores Latini](https://croala.ffzg.unizg.hr/) (Jovanović, Zagreb) | Croatian Latin from 976 CE through the neo-Latin centuries — charters, orations, carmina: 570 documents / 309,180 passages, the classical desk's medieval-Latin edge (synchronized 24 July 2026) | CC BY 4.0 |
| `cuc` | [Copenhagen Ugaritic Corpus](https://github.com/DT-UCPH/cuc) (CACCHT) | 279 Ugaritic tablets / 27,770 words — most of the KTU corpus, independently re-encoded, with per-sign cuneiform and damage flags (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `damaskini` | [CLARIN.SI](https://www.clarin.si/) (hdl [11356/1441](http://hdl.handle.net/11356/1441)) | Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1: 23 gold-annotated witnesses, 15th–19th c., with English translations (synchronized 17 July 2026) | CC BY-SA 4.0 |
| `dcs` | [Digital Corpus of Sanskrit](https://github.com/OliverHellwig/sanskrit) (Hellwig) | 15,741 gold-lemmatized Sanskrit chapters across 270 texts, ~5.46M analyzed words (synchronized 18 July 2026) | CC BY 4.0 |
| `derge-kangyur` | [Digital Derge Kangyur](https://github.com/Esukhia/derge-kangyur) (Esukhia, on the UVA-SOAS eKangyur) | The Tibetan Buddhist canon's first half: 1,200 Toh-numbered texts / 461,304 woodblock lines, exact-representation of the Degé blocks (synchronized 28 July 2026) | Public Domain (the repo's own declaration) |
| `derge-tengyur` | [Digital Derge Tengyur](https://github.com/Esukhia/derge-tengyur) (Esukhia) | The canon's second half — the treatises: 3,362 texts / 897,142 lines (synchronized 28 July 2026) | Public Domain (the repo's own declaration) |
| `derom` | [DÉRom](http://www.atilf.fr/DERom) (ATILF/Ortolang — Buchi &amp; Schweickard, eds.) | The Dictionnaire Étymologique Roman: 513 open etymon articles yielding 233 Proto-Romance reference entries with per-language reflexes, feeding `etym` under the `roa:pro` lect (synchronized 2 August 2026) | CC BY-NC-SA 4.0 |
| `digiliblt` | [digilibLT](https://digiliblt.uniupo.it/) (Vercelli/UniUPO, via CIRCSE) | 373 late-antique secular Latin prose texts, 2nd–7th c. — the classical→medieval transition band, UDPipe-lemmatized (the silver tier, labelled as such): 370 documents / 457,560 passages (synchronized 25 July 2026) | CC BY-SA 4.0 (in-repo grant) |
| `dillmann` | [Dillmann, Lexicon linguae aethiopicae](https://dillmann.betamasaheft.eu/) (TraCES digitization) | The Gəʿəz dictionary: 13,727 entries, Ethiopic headwords with Dillmann's 1865 Latin definitions (synchronized 26 July 2026) | CC BY-NC-SA 4.0 |
| `diorisis` | [Diorisis Ancient Greek Corpus](https://doi.org/10.6084/m9.figshare.6187256) (Vatri &amp; McGillivray) | 764 lemmatized second editions of the Greek canon, ~10.2M words — the library's first silver-tier source, labeled as such (synchronized 18 July 2026) | CC BY-SA 3.0 US (in-file) |
| `dss` | [ETCBC dss](https://github.com/ETCBC/dss) (Abegg/Bowley/Cook) | The Dead Sea Scrolls: 1,001 scrolls, 500,995 words, biblical and non-biblical, with text-critical flags intact (synchronized 18 July 2026) | CC BY-NC 4.0 (Abegg's grant) |
| `e84000` | [84000 — Translating the Words of the Buddha](https://84000.co/) (data-tei) | English translations of 388 Kangyur texts at Reading-Room citation grain, folio-anchored so `--parallel` pairs them with the Tibetan (synchronized 28 July 2026) | CC BY-NC-ND 3.0 |
| `ebl` | [electronic Babylonian Library](https://www.ebl.lmu.de/) Fragmentarium (LMU Munich) | 23,288 tablet fragments from the museum drawers — ~326k lines with inline English translations, 79.9% cross-linked to their CDLI records (2023 snapshot, synchronized 19 July 2026) | Held at CC BY-NC-SA 4.0 (the data paper's grant) pending clarification of the deposit's CC BY field |
| `edh` | [Epigraphic Database Heidelberg](https://edh.ub.uni-heidelberg.de/) | 81,881 Latin inscriptions (upstream archived 2021 — a preservation snapshot) | CC BY-SA 4.0 |
| `edl` | [LiLa / CIRCSE](https://lila-erc.eu/) | De Vaan, *Etymological Dictionary of Latin* (linked-data skeleton): 2,860 etymons (synchronized 14 July 2026) | CC BY-NC-SA 4.0 |
| `edr` | [Epigraphic Database Roma](http://www.edr-edr.it/) (Sapienza; Zenodo release v12) | The inscriptions of Italy — EDH's geographic complement: 115,590 EpiDoc records / 596,064 passages, Latin and Greek (synchronized 26 July 2026) | CC BY 4.0 (the project leadership's Zenodo deposit grant) |
| `edrdg`, `kradfile` | [EDRDG](https://www.edrdg.org/) (Breen) | JMdict and KANJIDIC2, plus the KRADFILE kanji→component index | CC BY-SA 4.0 |
| `elephantine` | [Texts and Scripts from Elephantine Island](https://elephantine.smb.museum/) (Staatliche Museen zu Berlin, ERC ELEPHANTINE) | The island's 4,000-year multilingual archive: 15,539 documents / 69,350 passages — the Judean garrison's Imperial Aramaic (892 texts, Hebrew script), Greek, Demotic and Hieratic in transliteration, Coptic, Arabic — with English translation siblings and daf-free page.line citations (synchronized 27 July 2026) | CC BY-SA 3.0 (per-document in-file grants; the site's stricter blanket notice recorded — owner ruling D47-d) |
| `eng-web` | [eBible.org](https://ebible.org/) via open-bibles | World English Bible | Public domain |
| `etcsl` | [ETCSL](https://etcsl.orinst.ox.ac.uk/) (Oxford, via the OTA/LLDS record) | The Electronic Text Corpus of Sumerian Literature: 394 hand-lemmatized composites + 381 English prose translations (synchronized 19 July 2026) | CC BY-NC-SA 3.0 |
| `first1k-greek` | [First1KGreek, Open Greek &amp; Latin](https://opengreekandlatin.github.io/First1KGreek/) | Post-classical Greek prose, incl. Swete's Septuagint | CC BY-SA |
| `freising` | [Brižinski spomeniki e-edition](https://nl.ijs.si/e-zrc/bs/) (ZRC SAZU / IJS) | The Freising Manuscripts, three transcription layers + translations | CC BY-ND 2.5 SI → `research_private` |
| `glaux` | [GLAUx](https://github.com/alekkeersmaekers/glaux) (Keersmaekers, Leuven) | ~20M tokens of Ancient Greek, 8th c. BCE – 4th c. CE, automatically annotated for lemma/morphology/syntax — the analysis-side complement to the held editions and the library's silver lemma tier, labeled as such on every hit: 1,421 works / 968,578 passages (synchronized 24 July 2026) | CC BY-SA (72 restrictively licensed texts carried as `nc`) |
| `goo300k`, `imp` | [CLARIN.SI](https://www.clarin.si/) (Erjavec, JSI; hdl [11356/1025](http://hdl.handle.net/11356/1025), [11356/1031](http://hdl.handle.net/11356/1031)) | Gold and silver-annotated historical Slovenian, 1584–1899 | CC BY 4.0 / CC BY-SA 4.0 |
| `gretil` | [GRETIL](https://gretil.sub.uni-goettingen.de/), Göttingen | 780 Sanskrit (and related) TEI editions | CC BY-NC-SA 4.0 |
| `hdic` | [HDIC](https://github.com/shikeda/HDIC) | The Heian-period hanzi dictionaries: Yuanben/Songben Yupian, Tenrei Banshō Meigi, Shinsen Jikyō | CC BY-SA 4.0 |
| `hebrew-lexicon` | [OpenScriptures HebrewLexicon](https://github.com/openscriptures/HebrewLexicon) | Two dictionaries: 9,299 augmented-Strong entries (every OSHB lemma resolves) + the 11,845-entry BDB outline with print-page anchors (synchronized 18 July 2026) | CC BY 4.0 |
| `helipad` | [HeliPaD](https://zenodo.org/records/4395040) (Walkden) | The Old Saxon *Heliand*, syntactically parsed with gold form-lemma pairs (synchronized 22 July 2026) | CC BY 4.0 |
| `iecor` | [IE-CoR](https://iecor.clld.org/) (lexibank/iecor via Zenodo) | The Indo-European cognacy database: 4,981 expert-curated cognate sets with loan events (synchronized 14 July 2026) | CC BY 4.0 |
| `iip` | [Inscriptions of Israel/Palestine](https://github.com/Brown-University-Library/iip-texts) (Brown) | 5,499 inscriptions, Hebrew/Aramaic/Greek/Latin, ~500 BCE–640 CE (synchronized 18 July 2026) | CC BY-NC 4.0 |
| `isicily` | [I.Sicily](https://github.com/ISicily/ISicily) (Prag, Oxford / ERC Crossreads) | 5,074 inscriptions of ancient Sicily across all its languages — incl. Sicel, Elymian, Sicilian Punic and Mamertine Oscan in their only machine-readable form (synchronized 18 July 2026) | CC BY 4.0 |
| `iswoc` | [ISWOC treebank](https://github.com/iswoc/iswoc-treebank), Oslo | Old English prose and the West-Saxon Gospels, gold-annotated | CC BY-NC-SA |
| `itant` | [Corpus ItAnt](https://github.com/DigItAnt/Corpus_ItAnt) (CNR-ILC/UniFI) | 501 Oscan + 9 Lepontic critical editions with English/Italian translations (synchronized 18 July 2026) | CC BY-NC-SA 4.0 |
| `kanripo` | [Kanseki Repository 漢籍リポジトリ](https://github.com/kanripo) (Wittern, Kyoto) | The classical Chinese library — KR1 classics through KR5 Daoist canon; with CBETA it makes Literary Chinese the corpus's largest language (synchronized 20 July 2026) | CC BY-SA 4.0 (org-level grant) |
| `larth-etp` | [Larth / Etruscan Texts Project glossary](https://github.com/GianlucaVico/Larth-Etruscan-NLP) | The ETP scholarly Etruscan glossary, 1,122 entries (synchronized 18 July 2026) | CC BY 4.0 |
| `lexica` | [PerseusDL lexica](https://github.com/PerseusDL/lexica) | Liddell-Scott-Jones; Lewis &amp; Short | CC BY-SA 4.0 |
| `lexlep`, `lexlep-words` | [Lexicon Leponticum](https://lexlep.univie.ac.at/) (Vienna) | 494 Cisalpine Celtic inscriptions + the 627-word Lepontic lexicon with morphemic analyses (synchronized 18 July 2026) | Conflicting statements (terms CC BY-SA 3.0 vs footer NC) — held at `nc` pending clarification |
| `liv` | [LiLa / CIRCSE LIV-LOD](https://lila-erc.eu/) | *Lexikon der indogermanischen Verben* linked-data edition: 305 PIE verbal etymons (synchronized 14 July 2026) | CC BY-SA 4.0 (with publisher permission) |
| `menotec` | [Menotec, via CLARINO INESS](https://clarino.uib.no/iness) (Bergen/Oslo) | Seven Old Norwegian treebanks and the Poetic Edda of Codex Regius, gold PROIEL-scheme annotation (synchronized 22 July 2026) | CC BY-NC-SA 4.0 |
| `mvp` | [Mahāvyutpatti](https://glossaries.dila.edu.tw/glossaries/MVP) (DILA TEI edition) | The 9th-century imperial Sanskrit–Tibetan–Chinese glossary: 9,379 entries beside Monier-Williams (synchronized 28 July 2026) | Public Domain (DILA's stated belief) |
| `mw` | [Cologne Digital Sanskrit Lexicon](https://www.sanskrit-lexicon.uni-koeln.de/) | Monier-Williams Sanskrit-English Dictionary (1899), 193,890 entries | CC BY-NC-SA 3.0 |
| `ogham` | [Ogham in 3D](https://ogham.celt.dias.ie/) v2.0 (DIAS / Maynooth) | ~500 ogham stones in real Ogham codepoints with transliteration layers (synchronized 17 July 2026) | Conflicting statements (site CC BY-NC-SA vs in-file CC BY 4.0) — held at the restrictive `nc` reading pending clarification |
| `old-tibetan` | [Old Tibetan Corpus](https://github.com/tibetan-nlp/old-tibetan-corpus) | The Old Tibetan Annals and Chronicle, annotated, the Annals paired with Dotson's English translation (synchronized 28 July 2026) | MIT |
| `oncoj`, `oncoj-lexicon` | [ONCOJ](https://oncoj.ninjal.ac.jp/) (Oxford-NINJAL) | The Corpus of Old Japanese — gold-morphology Man'yōshū-era verse — and its lexicon (synchronized 20 July 2026) | CC BY 4.0 (annotation; the texts are ancient) |
| `open-etruscan` | [OpenEtruscan](https://doi.org/10.5281/zenodo.20075836) | 6,248 Etruscan inscriptions with English siblings (synchronized 18 July 2026) | CC BY 4.0 |
| `openiti` | [OpenITI — Open Islamicate Texts Initiative](https://openiti.org/) (2025.1.9 Zenodo release) | The Islamicate library at corpus scale: 9,079 primary text versions of premodern Arabic and Persian — hadith, falsafa, history, poetry — 34.6M passages parsed from OpenITI mARkdown (synchronized 23 July 2026) | CC BY-NC-SA 4.0 (the Zenodo record's grant) |
| `openmgh` | [openMGH](https://www.mgh.de/en/digital-mgh/openmgh) (Monumenta Germaniae Historica + Bayerische Staatsbibliothek) | The critical-edition backbone of medieval Latin as TEI: the complete openMGH offering, 153 volumes — the SS rerum Germanicarum series (Einhard, the Frankish annals, Widukind, Adam of Bremen) joined by the Auctores antiquissimi, SS rerum Merovingicarum, Diplomata and further series (second wave synchronized 3 August 2026) | CC BY 4.0 (texts themselves free of copyright) |
| `oracc` | [ORACC](https://oracc.museum.upenn.edu/), 102 projects incl. the State Archives of Assyria, the Achaemenid royal trilinguals, the four ePSD2 corpora, and the P46 CC0 pack — eCUT (Urartian), the Amarna letters, the ATAE/TCMA Assyrian archives | 118,366 cuneiform tablets with gold lemmatization (synchronized 26 July 2026) | CC0 (per project); translation prose CC BY-SA |
| `oshb` | [Open Scriptures Hebrew Bible](https://github.com/openscriptures/morphhb) | The Westminster Leningrad Codex — 39 books, 23,213 verses with full morphology and ketiv/qere, byte-verbatim Masoretic text (synchronized 18 July 2026) | Text public domain; morphology CC BY 4.0 |
| `otdo` | [Old Tibetan Documents Online](https://otdo.aa-ken.jp/) (ILCAA, Tokyo) | 413 critical editions of Old Tibetan: the Dunhuang scrolls, the imperial pillar inscriptions, five Old Zhangzhung texts (synchronized 28 July 2026) | CC BY 4.0 |
| `papyri-ddbdp` | [papyri.info](https://papyri.info/) — Duke Databank of Documentary Papyri | 61,414 documentary papyri | CC BY |
| `perseus-greek`, `perseus-latin` | [Perseus Digital Library](https://www.perseus.tufts.edu/) (PerseusDL canonical-greekLit / canonical-latinLit) | The classical Greek and Latin canons with English translations | CC BY-SA |
| `peshitta` | [ETCBC peshitta](https://github.com/ETCBC/peshitta) | The Peshitta Old Testament incl. deuterocanon — 65 books / 31,341 verses; the Syriac leg of the verse-alignment hub (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `proiel` | [PROIEL treebank](https://proiel.github.io/) | Parallel NT (Greek, Latin, Gothic, Armenian, OCS) + classical prose, gold-annotated | CC BY-NC-SA |
| `rem` | [Referenzkorpus Mittelhochdeutsch](https://zenodo.org/records/13982324) (Bochum/Bonn) | 360 gold-annotated Middle High German texts, 1050–1350, diplomatic layer preserved (synchronized 22 July 2026) | CC BY-SA 4.0 |
| `ren` | [Referenzkorpus Mittelniederdeutsch/Niederrheinisch](https://www.fdr.uni-hamburg.de/record/9195) (Univ. Hamburg) | 235 Middle Low German / Low Rhenish texts, 1200–1650: 1.49M gold-annotated + 838K transcribed tokens, the Hanseatic rung (synchronized 26 July 2026) | CC BY 4.0 (the deposit's stated license) |
| `riig` | [RIIG — Recueil informatisé des inscriptions gauloises](https://riig.huma-num.fr/) (ANR, Ausonius/Bordeaux) | 428 Gaulish inscriptions, Gallo-Greek and Gallo-Latin, with French translations (synchronized 17 July 2026) | CC BY 4.0 (in-file grant) |
| `rsti` | [Ras Shamra Tablet Inventory](https://ochre.uchicago.edu/) (University of Chicago, OCHRE/CORPUS) | 5,075 inscribed-object inventory cards from Ugarit with the RS↔KTU/CTA concordances the field cites, and published editions at line grain (synchronized under a written grant, 1 August 2026) | CC BY-NC-SA 4.0 grant |
| `rundata` | [Samnordisk runtextdatabas / Rundata](https://www.runforum.nordiska.uu.se/srd/) (Uppsala, via rundata.info) | ~6,800 Scandinavian runic inscriptions in up to five text lanes: transliteration, Old-West-Norse and runic-Swedish normalisations, English and Swedish translations (synchronized 22 July 2026) | ODbL 1.0 + DbCL 1.0 — *based on the Scandinavian Runic-text Database* |
| `sabellic-loans` | en.wiktionary curation | 85 Latin lemmas with Oscan/Umbrian/Sabine etyma, loan-flagged (curated 18 July 2026) | CC BY-SA + GFDL |
| `sarit` | [SARIT](https://sarit.indology.info/) | 78 scholarly TEI editions incl. a complete Southern-Recension Mahābhārata, Devanagari + IAST (synchronized 18 July 2026) | CC BY-SA (per file) |
| `sblgnt` | [SBL Greek New Testament](https://sblgnt.com/) (SBL / Logos) | Critical edition of the Greek NT | CC BY 4.0 |
| `sdbh` | [UBS Semantic Dictionary of Biblical Hebrew](https://github.com/ubsicap/ubs-open-license) | 7,932 entries with semantic domains and 260,813 verse-level scripture references (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `sefaria` | [Sefaria](https://www.sefaria.org/) (Sefaria-Export, named versions only) | The Targum shelf plus the Rabbinic library — Mishnah (three complete Hebrew editions incl. the Kaufmann MS), the Wikisource Bavli, Guggenheimer's Yerushalmi, Tosefta, Minor Tractates, the Davidson/Steinsaltz nc lane: with daf-grain Talmud citations, joined by the classical midrash (the ten Rabbah collections and the Midrash Halakhah shelf, synchronized 1 August 2026) | Per version (PD / CC0 / CC BY / CC BY-SA; NC versions carried as `nc`) |
| `sl-lexica` | [ZRC SAZU](https://www.zrc-sazu.si/) via [CLARIN.SI](https://www.clarin.si/) | Pleteršnik's *Slovensko-nemški slovar* (1894–95), the Janez Svetokriški lexicon, and the 16th-century Slovenian word inventory — 139,405 entries (synchronized 17 July 2026) | CC BY 4.0 |
| `soas-tibetan` | [SOAS gold POS corpus](https://doi.org/10.5281/zenodo.574878) (Hill & Garrett) | Four classical texts with hand-corrected segmentation and POS — 991 lines / 318K tokens (synchronized 28 July 2026) | CC BY 4.0 |
| `starling` | [StarLing / Tower of Babel](https://starlingdb.org/) (G. Starostin et al.) | Six etymological databases, 28,707 entries: Pokorny's IEW, Nikolayev's PIE database, Vasmer's dictionary of Russian (Trubachev ed.), Common Germanic, Baltic, and the Kartvelian base (Klimov lineage, synchronized 26 July 2026) | Written grant ("free for anybody to use … as long as the source is properly acknowledged"), per-base compiler credit carried on every surface |
| `suttacentral` | [SuttaCentral](https://suttacentral.net/) bilara-data | The Pali Tipiṭaka (Mahāsaṅgīti) + the Patna Dhammapada, with segment-aligned English (synchronized 18 July 2026) | CC0 (per publication) |
| `syriac-corpus` | [Digital Syriac Corpus](https://syriaccorpus.org/) (Srophé) | 632 classical Syriac TEI documents — a millennium of literature (synchronized 19 July 2026) | CC BY 4.0 (per file) |
| `tibetan-verbs` | [Tibetan Verbs Database](https://github.com/tibetan-nlp/tibetan-verbs-database) | 2,491 verb tense-stem tuples (synchronized 28 July 2026) | CC0 |
| `tir` | [Thesaurus Inscriptionum Raeticarum](https://tir.univie.ac.at/) (Vienna) | 389 Raetic inscriptions — the corpus of record (synchronized 18 July 2026) | Same conflicting statements — held at `nc` |
| `tla-hf` | [Thesaurus Linguae Aegyptiae](https://huggingface.co/thesaurus-linguae-aegyptiae) official datasets | 13,383 Demotic + 3,606 Late Egyptian sentences with German — the only bulk demotic anywhere (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `tlhdig` | [TLHdig](https://www.hethiter.net/) (Thesaurus Linguarum Hethaeorum digitalis, Hethitologie-Portal Mainz) | The Hittite corpus: 23,486 tablet manuscripts in 663 CTH compositions — >98% of published Hittite fragments, with cuneiform, transliteration and candidate morphology (synchronized 19 July 2026) | CC BY 4.0 |
| `tls` | [Thesaurus Linguae Sericae](https://hxwd.org/) (tls-kr/tls-data) | Concept and word nets over classical Chinese with sense-level attributions into the classics (synchronized 20 July 2026) | CC BY-SA 4.0 |
| `torot` | [TOROT](https://torottreebank.github.io/) — Tromsø OCS and Old Russian Treebank | OCS and Old East Slavic, gold-annotated | CC BY-NC-SA |
| `traces` | [TraCES](https://www.traces.uni-hamburg.de/) (ERC 338756, Hamburg) | 75,440 morphologically analyzed Gəʿəz tokens, lemma-linked into Dillmann's entries — Matthew, Kebra Nagast, chronicles, Aksumite royal inscriptions (synchronized 26 July 2026) | CC BY-NC-ND 4.0 (ZFDM record 707) |
| `tshet-uinh` | [tshet-uinh-data](https://github.com/nk2028/tshet-uinh-data) (nk2028) | The 廣韻 Guangyun critical edition — Qieyun-system Middle Chinese phonology (synchronized 19 July 2026) | CC0 1.0 |
| `ud` | [Universal Dependencies](https://universaldependencies.org/) (twelve ancient treebanks) | Latin (Aquinas, Perseus), Ancient Greek (Perseus), Vedic Sanskrit, Gothic, Greek, Old East Slavic (birchbark, RNC, Ruthenian), Old Irish glosses (St Gall Priscian, Würzburg), Hittite (HitTB — since 19 July 2026) | CC BY-SA / CC BY-NC-SA per treebank |
| `unihan` | [Unihan](https://www.unicode.org/reports/tr38/) — the Unicode Han Database | 65,092 Han codepoint records: radicals, strokes, variants, readings (synchronized 20 July 2026) | Unicode License V3 |
| `vulgate` | [open-bibles](https://github.com/seven1m/open-bibles) / [eBible.org](https://ebible.org/) (Tweedale text) | The complete Clementine Vulgate, 73 books | Public domain |
| `wiktionary-bo` | Wiktionary Tibetan (kaikki extract) | 3,651 entries with reflex edges (synchronized 28 July 2026) | Wiktionary dual license (CC BY-SA) |
| `wiktionary-cu`, `wiktionary-recon` | [kaikki.org](https://kaikki.org/) (Wiktextract) from [Wiktionary](https://www.wiktionary.org/) | OCS lexicon; seven reconstruction dictionaries (PIE, Proto-Slavic, Proto-Germanic, Proto-West Germanic, Proto-Balto-Slavic, Proto-Italic, Proto-Indo-Iranian) with descendant trees; Old Irish, Middle Irish, and Middle Welsh extracts (since 17 July 2026) | CC BY-SA + GFDL |
| `wold` | [WOLD — World Loanword Database](https://wold.clld.org/) (MPI-EVA / Lexibank) | 41 vocabularies / 64,289 lexemes with loanword status and donor languages — the loanword-flow layer of the comparativist desk (synchronized 26 July 2026) | CC BY 4.0 |

## Feature modules

Thirteen further registry rows are **feature modules**, not corpora:
machinery that fetches reference data but mints no documents of its own.

| Module | What it provides | License |
|---|---|---|
| `actib` | The segmented-Tibetan anchor layer, republished through nabu-data | CC BY 4.0 |
| `bridging` | The OSHB ↔ BHSA verse crosswalk | MIT |
| `cldf-spine` | The shared Cross-Linguistic Data Formats reference tables ([Concepticon](https://concepticon.clld.org/) + [Glottolog](https://glottolog.org/)) that WOLD/CLICS rows resolve through | CC BY 4.0 |
| `hypotactic` | Greek metrical scansion — meter, pattern and caesura annotated onto held verse | CC BY 4.0 |
| `kitab` | [KITAB](https://kitab-project.org/) text-reuse alignments over the OpenITI library | CC BY-NC-SA 4.0 |
| `kr-gaiji` | The Kanripo gaiji (rare-glyph) map | CC BY-SA 4.0 (the kanripo org grant) |
| `lila` | The [LiLa](https://lila-erc.eu/) Latin lemma bank behind `nabu define`'s variant-spelling fallback | CC BY-SA 4.0 |
| `nabu-data` | The library's own [published datasets](https://github.com/arvicco/nabu-data), consumed back as a source — e.g. the Sanskrit form→lemma table behind `nabu define`'s inflected-form expansion; the reproducibility loop closed in public | CC BY 4.0 |
| `nabu-lects` | The [lect registry](https://arvicco.github.io/nabu-lects) sister project — the stage ladders, stage-aware search and reconstruction honesty on the [Languages]({{ '/languages/' | relative_url }}) page | CC BY 4.0 |
| `osl` | The Oracc Sign List behind `nabu signs` | CC0 |
| `pedecerto` | Latin metrical scansion ([Pedecerto](https://www.pedecerto.eu/), digital metrical analyses) | CC BY-NC-ND 4.0 |
| `pleiades` | The [Pleiades](https://pleiades.stoa.org/) ancient-world gazetteer behind `nabu place` and the findspot line | CC BY 3.0 |
| `trismegistos` | The [Trismegistos](https://www.trismegistos.org/) TexRelations concordance crosswalk resolving `tm:` reference edges across epigraphic corpora | CC BY-SA 4.0 |

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
editors; the ETCSL project at Oxford with the Oxford Text Archive; the
Kanseki Repository (Christian Wittern) and CBETA; the Thesaurus Linguae
Sericae editors; the Unicode Consortium's Unihan database; the nk2028
group's Qieyun-system edition; William Baxter and Laurent Sagart; the
HDIC project; the Electronic Dictionary Research and Development Group
(James Breen); Andrew West's BabelStone; the Oxford-NINJAL Corpus of Old
Japanese; the volunteer transcribers of Aozora Bunko; the Menotec project
and the CLARINO INESS infrastructure at Bergen; George Walkden's HeliPaD;
the Referenzkorpus Mittelhochdeutsch teams at Bochum and Bonn; and
Uppsala University's Samnordisk runtextdatabas — this library is *based
on the Scandinavian Runic-text Database*, as its Open Database License
asks to be said. Users of
this software are bound by, and should credit, these upstream projects
under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance TITUS, whose
scholarly-use terms grant no redistribution, and the Rahlfs Septuagint
under CATSS conditions).
