---
title: Sources
permalink: /sources/
description: >-
  Every corpus and dictionary in the Nabu library, with upstream attribution
  and license terms, and the project's licensing philosophy.
---

{% assign census = site.data.census -%}
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
  Together with `open`, this covers roughly
  {{ census.redistributable_pct }}% of documents.
- **`odbl`** — open data under the Open Database License (ODbL 1.0 + DbCL
  1.0): attribution and share-alike duties that attach to the *database*
  — name it, link it, share derived databases alike. The Scandinavian
  runic corpus is its occupant.
- **`nc`** — CC BY-NC-SA class (GRETIL, most treebanks): licensed for
  non-commercial use. Appropriate for private research, including
  AI-assisted reading; never redistributed by the tooling.
- **`research_private`** — sources whose terms (for instance CC BY-ND, or
  scholarly-use grants without a redistribution clause) do not fit the
  classes above. Held for personal research only, and excluded from the
  MCP surface by default: an AI client must opt in per call to see them.
  The Freising Manuscripts edition (CC BY-ND 2.5 SI) was the first source
  behind this gate; scholarly-use grants (SEAL, the Luwian corpus) and the
  Dutch institute corpora without a redistribution clause have joined it.
- **`restricted`** — a document whose upstream licence statement is
  unfamiliar is never silently opened: it is held at this class, withheld
  from the MCP surface like `research_private`, until a human has read the
  statement.

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

All {{ census.live_sources }} sources below are synced and live as of {{ census.as_of }}, listed
alphabetically by source id; the counts in a contents line are those of the
source's first synchronization (dated where shown). The same sources grouped by research desk —
each desk's member shelves, license mix and sync status on one page —
appear on the [research axes]({{ '/axis/' | relative_url }}).

| Source | Upstream project | Contents | License |
|---|---|---|---|
| `achemenet` | [Achemenet Babylonian](https://zenodo.org/records/19067652) (Helsinki) | 2,774 linguistically annotated Achaemenid-period Babylonian texts, lemmatized at an honest silver tier (synchronized 17 August 2026) | CC BY 4.0 |
| `aclt` | [ACLT — Annotated Corpus of Luwian Texts](https://luwian.web-corpora.net/) (I. Yakubovich; corpus files prepared by T. Arkhangelskiy) | 266 Hieroglyphic Luwian inscriptions / 2,682 clauses, each with full morphology and a sign-by-sign transliteration (synchronized 30 September 2026) | Personal research grant (I. Yakubovich, by email, 2026-09-28) — held at `research_private`, never redistributed |
| `aed` | [Ägyptische Wortliste](https://github.com/simondschweitzer/aed-tei) (TLA/BBAW) | 35,052 Egyptian dictionary entries keyed by the corpus's own lemma ids (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `aes` | [Ancient Egyptian Sentences](https://github.com/simondschweitzer/aes) (TLA/BBAW snapshot) | 13,026 Egyptian texts / 101,793 gold-lemmatized sentences — Pyramid Texts to Sinuhe to medical papyri — with aligned German (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `altaica-shm` | [Monumenta Altaica](http://altaica.ru/e_SecretH.php) — John C. Street's text | The *Secret History of the Mongols* in Street's romanized text (v24, 2013): 3,523 lines at Street's own numbering (synchronized 28 September 2026) | Use granted by the Monumenta Altaica maintainer (by email, 2026-09-27); Street's copyright notice carried verbatim |
| `aozora` | [Aozora Bunko 青空文庫](https://www.aozora.gr.jp/) | The Japanese public-domain library: 16,004 works, ruby-annotated — in-copyright works excluded before discovery (synchronized 21 July 2026) | Public domain (取り扱い規準 grant) |
| `aranese` | [ES-OC Parallel Corpus](https://huggingface.co/datasets/projecte-aina/ES-OC_Parallel_Corpus) (BSC projecte-aina) | Spanish–Aranese Occitan parallel sentences — by the dataset card's own account mainly synthetic, and held as such (synchronized 19 August 2026) | CC BY-SA 4.0 |
| `archiv-slav-phil` | [*Archiv für slavische Philologie*](https://archive.org/details/archivfrslavis16berluoft), Bd. 1–35 (archive.org scans) | Jagić's journal, 1876–1914, in archive.org's uncorrected OCR — a reference shelf of the German Slavistics canon (synchronized 11 October 2026) | Public domain |
| `aspr` | [Oxford Text Archive](https://ota.bodleian.ox.ac.uk/) record 3009 (Hidley / Macrae-Gibson e-text of Krapp &amp; Dobbie) | The complete Anglo-Saxon Poetic Records | CC BY-SA 3.0 |
| `atmo` | [ATMO — Annotated Turki Manuscripts from the Jarring Collection Online](https://uyghur.linguistics.indiana.edu/manuscripts/index.xhtml) (Indiana University / Lund University Library) | Eastern Turki manuscripts of the 18th–20th centuries, line by line: Perso-Arabic text with a full Latin transliteration, marginalia marked (synchronized 28 September 2026) | CC BY-SA 4.0 |
| `babelstone-ids` | [BabelStone IDS](https://www.babelstone.co.uk/CJK/IDS.TXT) (Andrew West) | Ideographic Description Sequences for 97,680 CJK characters | Public-domain dedication |
| `ban-wikisource` | [Balinese Wikisource](https://ban.wikisource.org/) | The lontar shelf: 1,252 palm-leaf manuscripts / 21,491 page transcriptions, manuscript-direct in Balinese script (synchronized 12 October 2026) | Texts PD (manuscript tradition); transcription CC BY-SA 4.0 |
| `baxter-sagart` | [Baxter-Sagart Old Chinese](https://github.com/yawnoc/baxter-sagart-old-chinese) | The Baxter &amp; Sagart 2014 Old Chinese reconstruction | CC BY 4.0 (the authors' grant) |
| `bdcamoes` | [BDCamões, Part I](https://portulanclarin.net/) (PORTULAN CLARIN / Camões IP) | 127 Portuguese literary works / 69,812 passages (synchronized 19 August 2026) | CC BY (Part I only) |
| `betamasaheft-works` | [Beta maṣāḥəft](https://betamasaheft.eu/) (Hiob-Ludolf-Zentrum, Univ. Hamburg) | The Gəʿəz text shelf: 3,796 text-bearing records at verse grain — the Ethiopic Bible, 1 Enoch and Jubilees (complete only in Gəʿəz), the Kebra Nagast, royal chronicles (synchronized 26 July 2026) | CC BY-SA 4.0 (per-document in-file grants) |
| `bfm` | [Base de français médiéval](https://bfm.ens-lyon.fr/) (ENS de Lyon / IHRIM, via NAKALA) | BFM2022: Old and Middle French from the 842 Serments de Strasbourg through the 15th century, TEI with lemmas (silver): 6.4M words (synchronized 25 July 2026) | Licence Ouverte / Etalab (8 files' critical apparatus, CC BY-NC-SA, is excluded at parse) |
| `bg-wikisource` | [Bulgarian Wikisource](https://bg.wikisource.org/) | Medieval charters and Paisius's *Istoriya slavyanobolgarskaya* (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `bhsa` | [ETCBC BHSA](https://github.com/ETCBC/bhsa) | The Hebrew Bible with full clause/phrase syntax, ketiv-qere and per-lexeme glosses — 426,590 words (synchronized 18 July 2026) | CC BY-NC 4.0 |
| `bibyeonsa` | [비변사등록 Records of the Border Defense Command](https://www.data.go.kr/data/15053636/fileData.do) (National Institute of Korean History) | 273 volumes / 93,528 entries of the Joseon military council's register (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `bosworth-toller` | [Bosworth-Toller Anglo-Saxon Dictionary](https://bosworthtoller.com/) via [LINDAT/CLARIAH-CZ](https://lindat.mff.cuni.cz/repository/handle/11234/1-3532) | 62,815 Old English dictionary entries | CC BY 4.0 |
| `cantigas` | [Cantigas Medievais Galego-Portuguesas](https://cantigas.fcsh.unl.pt/) (Projeto Littera, NOVA FCSH) | The complete secular Galician-Portuguese lyric — 1,682 cantigas at verse grain with authorship, genre and the corpus-wide cancioneiro concordance (synchronized 2 August 2026; republished as the `roa-opt/cantigas` dataset in nabu-data) | Written any-use grant with attribution |
| `cbeta` | [CBETA](https://www.cbeta.org/) (cbeta-org/xml-p5) | The Chinese Buddhist canon: Taishō + Xuzangjing in TEI P5 (synchronized 20 July 2026) | CC BY-NC-SA 4.0 |
| `ccl` | [Comprehensive Coptic Lexicon](https://refubium.fu-berlin.de/handle/fub188/27813) (BBAW/DDGLC) | 11,284 Coptic dictionary entries + the ORAEC egy↔cop crosswalk as etymology edges (synchronized 18 July 2026) | CC BY-SA 4.0 (in-file); crosswalk CC0 |
| `ccmh` | Corpus Cyrillo-Methodianum Helsingiense via [Kielipankki](https://www.kielipankki.fi/) (Language Bank of Finland) | Four OCS gospel codices, Suprasliensis, the Vitae | CC BY 4.0 |
| `cdli` | [CDLI](https://cdli.mpiwg-berlin.mpg.de/) (Cuneiform Digital Library Initiative) | The universal cuneiform catalog: 353,156 artifacts — 135,201 transliterations plus catalog records for the whole artifact space, proto-cuneiform to Achaemenid, with periods, proveniences and collections as browsable axes (2023 snapshot, synchronized 19 July 2026) | Bespoke open grant (attribution; images excluded) |
| `ceipom` | [CEIPoM](https://doi.org/10.5281/zenodo.4759134) (Pitts) | 3,871 pre-Roman-Italy texts — Oscan, Messapic, Venetic, Umbrian, South Picene, Faliscan, archaic Latin — lemmatized, dated, geolocated; incl. the Fibula Praenestina and the complete Iguvine Tables (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `classical-modern` | [Classical-Modern](https://github.com/NiuTrans/Classical-Modern) (NiuTrans) | Classical↔Modern Chinese parallel corpus: 14,608 chapters / 1,944,934 sentence pairs; the modern translations are web-crawled, as the README says, with each chapter's crawl sources carried (synchronized 29 August 2026) | MIT |
| `clics` | [CLICS³](https://clics.clld.org/) | The cross-linguistic colexification network: 2,919 concepts / 4,228 weighted edges over ~3,156 varieties (synchronized 26 July 2026) | CC BY 4.0 |
| `cme` | [Corpus of Middle English Prose and Verse](http://www.medictionary.info) (Middle English Compendium, Univ. of Michigan) | 297 Middle English texts / 1,355,279 passages, Chaucer to the mystery plays (synchronized 23 August 2026) | Public domain (U-M Library statement); free-use grant from the Compendium's text manager (by email, 2026-08-20) |
| `coptic-scriptorium` | [Coptic Scriptorium](https://copticscriptorium.org/) | Sahidic and Bohairic Coptic corpora with gold annotation, 482 documents | CC BY per document (source class `nc`, most-restrictive-wins) |
| `corph` | [CorPH — Corpus PalaeoHibernicum](https://chronhib.maynoothuniversity.ie/) (ERC ChronHib, Maynooth) | 76 Early Irish documents, 7th–10th c., gold-lemmatized — the library's first Old Irish (synchronized 17 July 2026) | MIT |
| `corpus-corporum` | [Corpus Córporum](https://mlat.uzh.ch) (Univ. of Zurich) | Migne's Patrologia Latina and the wider Latin library: 5,248 texts / 896,770 passages (synchronized 19 August 2026) | CC BY-NC-SA (non-commercial; site terms) |
| `corpus-gysseling` | [Corpus Gysseling](https://taalmaterialen.ivdnt.org/download/tstc-corpus-gysseling/) (Instituut voor de Nederlandse Taal) | 13th-century Early Middle Dutch with lemma and part of speech: 2,226 documents / 207,793 passages (synchronized 27 August 2026) | Non-commercial, no redistribution grant — held at `research_private` |
| `corpus-oudnederlands` | [Corpus Oudnederlands](https://taalmaterialen.ivdnt.org/download/corpus-oudnederlands-download/) (Instituut voor de Nederlandse Taal) | The Old Dutch word material, 475–1200 (synchronized 27 August 2026) | Non-commercial, no redistribution grant — held at `research_private` |
| `croala` | [CroALa — Croatiae auctores Latini](https://croala.ffzg.unizg.hr/) (Jovanović, Zagreb) | Croatian Latin from 976 CE through the neo-Latin centuries — charters, orations, carmina: 570 documents / 309,180 passages, the classical desk's medieval-Latin edge (synchronized 24 July 2026) | CC BY 4.0 |
| `cs-wikisource` | [Czech Wikisource](https://cs.wikisource.org/) | Censused premodern works: Dalimil's chronicle, the Kralice Bible, Comenius, Harant (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `ctilc` | [CTILC](https://ctilc.iec.cat/) — Corpus Textual Informatitzat de la Llengua Catalana (Institut d'Estudis Catalans) | The public-domain works slice: 967 Catalan texts / 256,685 passages (synchronized 19 August 2026) | Public domain, with the IEC's mandatory citation |
| `cuc` | [Copenhagen Ugaritic Corpus](https://github.com/DT-UCPH/cuc) (CACCHT) | 279 Ugaritic tablets / 27,770 words — most of the KTU corpus, independently re-encoded, with per-sign cuneiform and damage flags (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `cv-sardinian` | [Common Voice](https://github.com/common-voice/common-voice) Sardinian sentence collection | 5,237 Sardinian sentences — the text side only, no audio (synchronized 19 August 2026) | CC0 1.0 |
| `dacon` | [DACON — Diachronic Annotated Corpus of Newar](https://zenodo.org/records/12887386) (O'Neill &amp; Meelen) | Classical Newar manuscripts, morphosyntactically annotated (synchronized 29 August 2026) | CC BY 4.0 |
| `damaskini` | [CLARIN.SI](https://www.clarin.si/) (hdl [11356/1441](http://hdl.handle.net/11356/1441)) | Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1: 23 gold-annotated witnesses, 15th–19th c., with English translations (synchronized 17 July 2026) | CC BY-SA 4.0 |
| `dcs` | [Digital Corpus of Sanskrit](https://github.com/OliverHellwig/sanskrit) (Hellwig) | 15,741 gold-lemmatized Sanskrit chapters across 270 texts, ~5.46M analyzed words (synchronized 18 July 2026) | CC BY 4.0 |
| `derge-kangyur` | [Digital Derge Kangyur](https://github.com/Esukhia/derge-kangyur) (Esukhia, on the UVA-SOAS eKangyur) | The Tibetan Buddhist canon's first half: 1,200 Toh-numbered texts / 461,304 woodblock lines, exact-representation of the Degé blocks (synchronized 28 July 2026) | Public Domain (the repo's own declaration) |
| `derge-tengyur` | [Digital Derge Tengyur](https://github.com/Esukhia/derge-tengyur) (Esukhia) | The canon's second half — the treatises: 3,362 texts / 897,142 lines (synchronized 28 July 2026) | Public Domain (the repo's own declaration) |
| `derom` | [DÉRom](http://www.atilf.fr/DERom) (ATILF/Ortolang — Buchi &amp; Schweickard, eds.) | The Dictionnaire Étymologique Roman: 513 open etymon articles yielding 233 Proto-Romance reference entries with per-language reflexes, feeding `etym` under the `roa:pro` lect (synchronized 2 August 2026) | CC BY-NC-SA 4.0 |
| `dharma-campa` | [DHARMA](https://github.com/erc-dharma/tfc-campa-epigraphy) — Campā epigraphy (ERC DHARMA, EFEO/CNRS) | 121 Old Cham and Sanskrit inscriptions of Champa (synchronized 1 September 2026) | CC BY 4.0 / CC BY-SA 4.0 per file |
| `dharma-deccan` | [DHARMA — Deccan epigraphy](https://github.com/erc-dharma) (ERC project no. 809994) | 1,694 inscriptions / 27,929 passages in Telugu, Kannada, Sanskrit and Prakrit (synchronized 11 October 2026) | CC BY 4.0 |
| `dharma-javanese-texts` | [DHARMA](https://github.com/erc-dharma/tfd-nusantara-philology) — Nusantara philology | The Old Javanese kakawin library and Old Sundanese texts: 92 editions / 46,482 passages (synchronized 1 September 2026) | CC BY 4.0 / CC BY-SA 4.0 per file |
| `dharma-khmer` | [DHARMA](https://github.com/erc-dharma/tfc-khmer-epigraphy) — Corpus des inscriptions khmères | 1,219 Old Khmer and Sanskrit inscriptions under their Cœdès K-numbers (synchronized 1 September 2026) | CC BY 4.0 / CC BY-SA 4.0 per file |
| `dharma-mdt` | [DHARMA — metadata of texts](https://github.com/erc-dharma) (ERC project no. 809994) | The project's works database: 734 catalog records joining the epigraphy estates (synchronized 11 October 2026) | Metadata rights stated CC0 per row |
| `dharma-nusantara` | [DHARMA](https://github.com/erc-dharma/tfc-nusantara-epigraphy) — Nusantara epigraphy | 291 Old Javanese, Old Malay and Old Sundanese charters (synchronized 1 September 2026) | CC BY 4.0 / CC BY-SA 4.0 per file |
| `dharma-pyu` | [DHARMA](https://github.com/erc-dharma/tfc-pyu-epigraphy) — Corpus of Pyu Inscriptions | 145 inscriptions of the Pyu city-states (synchronized 1 September 2026) | CC BY 4.0 / CC BY-SA 4.0 per file |
| `dharma-tamil` | [DHARMA — Tamil-country epigraphy](https://github.com/erc-dharma) (ERC project no. 809994) | 1,267 inscriptions / 17,993 passages — the Pallava and Chola donative record, Śaka and Kollam dates converted (synchronized 12 October 2026) | CC BY 4.0 |
| `diccas` | [DiCCAS — Disaster Corpus in Classical Arabic Sources](http://hdl.handle.net/11356/2097) (Cicola, Bologna) | Ten Classical Arabic source texts on disasters, annotated by the project (synchronized 3 September 2026) | CC BY-NC-SA 4.0 |
| `digiliblt` | [digilibLT](https://digiliblt.uniupo.it/) (Vercelli/UniUPO, via CIRCSE) | 373 late-antique secular Latin prose texts, 2nd–7th c. — the classical→medieval transition band, UDPipe-lemmatized (the silver tier, labelled as such): 370 documents / 457,560 passages (synchronized 25 July 2026) | CC BY-SA 4.0 (in-repo grant) |
| `dillmann` | [Dillmann, Lexicon linguae aethiopicae](https://dillmann.betamasaheft.eu/) (TraCES digitization) | The Gəʿəz dictionary: 13,727 entries, Ethiopic headwords with Dillmann's 1865 Latin definitions (synchronized 26 July 2026) | CC BY-NC-SA 4.0 |
| `diorisis` | [Diorisis Ancient Greek Corpus](https://doi.org/10.6084/m9.figshare.6187256) (Vatri &amp; McGillivray) | 764 lemmatized second editions of the Greek canon, ~10.2M words — the library's first silver-tier source, labeled as such (synchronized 18 July 2026) | CC BY-SA 3.0 US (in-file) |
| `disco` | [DISCO — Diachronic Spanish Sonnet Corpus](https://github.com/pruizf/disco) (Ruiz Fabo et al.) | 1,215 Spanish sonnets, the 15th century to the 20th (synchronized 13 August 2026) | CC BY |
| `dss` | [ETCBC dss](https://github.com/ETCBC/dss) (Abegg/Bowley/Cook) | The Dead Sea Scrolls: 1,001 scrolls, 500,995 words, biblical and non-biblical, with text-critical flags intact (synchronized 18 July 2026) | CC BY-NC 4.0 (Abegg's grant) |
| `dta` | [Deutsches Textarchiv](https://www.deutschestextarchiv.de/) (BBAW) | The German print corpus 1473–1969: 5,478 works / 729,090 passages (synchronized 3 September 2026) | CC BY-SA 4.0 |
| `e84000` | [84000 — Translating the Words of the Buddha](https://84000.co/) (data-tei) | English translations of 388 Kangyur texts at Reading-Room citation grain, folio-anchored so `--parallel` pairs them with the Tibetan (synchronized 28 July 2026) | CC BY-NC-ND 3.0 |
| `ebl` | [electronic Babylonian Library](https://www.ebl.lmu.de/) Fragmentarium (LMU Munich) | 23,288 tablet fragments from the museum drawers — ~326k lines with inline English translations, 79.9% cross-linked to their CDLI records (2023 snapshot, synchronized 19 July 2026) | Held at CC BY-NC-SA 4.0 (the data paper's grant) pending clarification of the deposit's CC BY field |
| `edh` | [Epigraphic Database Heidelberg](https://edh.ub.uni-heidelberg.de/) | 81,881 Latin inscriptions (upstream archived 2021 — a preservation snapshot) | CC BY-SA 4.0 |
| `edl` | [LiLa / CIRCSE](https://lila-erc.eu/) | De Vaan, *Etymological Dictionary of Latin* (linked-data skeleton): 2,860 etymons (synchronized 14 July 2026) | CC BY-NC-SA 4.0 |
| `edr` | [Epigraphic Database Roma](http://www.edr-edr.it/) (Sapienza; Zenodo release v12) | The inscriptions of Italy — EDH's geographic complement: 115,590 EpiDoc records / 596,064 passages, Latin and Greek (synchronized 26 July 2026) | CC BY 4.0 (the project leadership's Zenodo deposit grant) |
| `edrdg`, `kradfile` | [EDRDG](https://www.edrdg.org/) (Breen) | JMdict and KANJIDIC2, plus the KRADFILE kanji→component index | CC BY-SA 4.0 |
| `eebo-tcp` | [EEBO-TCP](https://textcreationpartnership.org/) — Early English Books Online, Text Creation Partnership (Phases I–II) | 60,325 early printed books in English, 1473–1700 / 25,065,921 passages — the library's second-largest language (synchronized 26 August 2026) | CC0 1.0 (the transcriptions; page images not fetched) |
| `elektire` | [eLektire](https://lektire.skole.hr/) (CARNET / Bulaja naklada) | The Croatian school canon: 205 public-domain works, the editorial apparatus excluded (synchronized 11 October 2026) | Public domain per work |
| `elephantine` | [Texts and Scripts from Elephantine Island](https://elephantine.smb.museum/) (Staatliche Museen zu Berlin, ERC ELEPHANTINE) | The island's 4,000-year multilingual archive: 15,539 documents / 69,350 passages — the Judean garrison's Imperial Aramaic (892 texts, Hebrew script), Greek, Demotic and Hieratic in transliteration, Coptic, Arabic — with English translation siblings and daf-free page.line citations (synchronized 27 July 2026) | CC BY-SA 3.0 (per-document in-file grants; the site's stricter blanket notice recorded — owner ruling D47-d) |
| `eltec-srp` | [ELTeC-srp](https://github.com/COST-ELTeC/ELTeC-srp) (European Literary Text Collection; ed. C. Krstev) | 96 Serbian novels / 150,794 passages (synchronized 11 October 2026) | Texts PD; markup CC BY 4.0 |
| `eng-web` | [eBible.org](https://ebible.org/) via open-bibles | World English Bible | Public domain |
| `etcsl` | [ETCSL](https://etcsl.orinst.ox.ac.uk/) (Oxford, via the OTA/LLDS record) | The Electronic Text Corpus of Sumerian Literature: 394 hand-lemmatized composites + 381 English prose translations (synchronized 19 July 2026) | CC BY-NC-SA 3.0 |
| `first1k-greek` | [First1KGreek, Open Greek &amp; Latin](https://opengreekandlatin.github.io/First1KGreek/) | Post-classical Greek prose, incl. Swete's Septuagint | CC BY-SA |
| `fornsvenska` | [Fornsvenska textbanken](https://spraakbanken.gu.se/) (Språkbanken Text) | Old Swedish laws, prose and verse: 155 texts / 170,872 passages (synchronized 13 August 2026) | CC BY 4.0 |
| `freising` | [Brižinski spomeniki e-edition](https://nl.ijs.si/e-zrc/bs/) (ZRC SAZU / IJS) | The Freising Manuscripts, three transcription layers + translations | CC BY-ND 2.5 SI → `research_private` |
| `gams-zrcalo` | [*Zrcalo člověčaskago spasenja* (1445)](https://gams.uni-graz.at/speculum) (Kramarić &amp; Schneider, GAMS / Univ. of Graz) | The Slavonic *Speculum humanae salvationis* of 1445 in a digital edition (synchronized 11 October 2026) | CC BY 4.0 |
| `glaux` | [GLAUx](https://github.com/alekkeersmaekers/glaux) (Keersmaekers, Leuven) | ~20M tokens of Ancient Greek, 8th c. BCE – 4th c. CE, automatically annotated for lemma/morphology/syntax — the analysis-side complement to the held editions and the library's silver lemma tier, labeled as such on every hit: 1,421 works / 968,578 passages (synchronized 24 July 2026) | CC BY-SA (72 restrictively licensed texts carried as `nc`) |
| `goo300k`, `imp` | [CLARIN.SI](https://www.clarin.si/) (Erjavec, JSI; hdl [11356/1025](http://hdl.handle.net/11356/1025), [11356/1031](http://hdl.handle.net/11356/1031)) | Gold and silver-annotated historical Slovenian, 1584–1899 | CC BY 4.0 / CC BY-SA 4.0 |
| `goryeosa` | [고려사 History of Goryeo](https://www.data.go.kr/data/15053637/fileData.do) (National Institute of Korean History) | The official dynastic history, 138 volumes / 31,207 passages (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `goryeosa-jeoryo` | [고려사절요 Essentials of Goryeo History](https://www.data.go.kr/data/15115521/fileData.do) (National Institute of Korean History) | The annalistic digest of the Goryeo record (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `gpc` | [GPC — Geiriadur Prifysgol Cymru](https://www.geiriadur.ac.uk/) (open subset) | 89,386 entries of the historical dictionary of Welsh, each linked to its GPC Online page (synchronized 11 September 2026) | CC BY 4.0 (the open subset) |
| `gretil` | [GRETIL](https://gretil.sub.uni-goettingen.de/), Göttingen | 780 Sanskrit (and related) TEI editions | CC BY-NC-SA 4.0 |
| `gu-wikisource` | [Gujarati Wikisource](https://gu.wikisource.org/) | The bhakti cone: 207 documents / 1,462 passages from the 1888–1913 print editions (synchronized 12 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `guaman-poma` | [Guaman Poma, *Nueva corónica y buen gobierno*](https://poma.kb.dk/permalink/2006/poma/info/es/frontpage.htm) (Royal Danish Library) | The whole chronicle, page by page — Spanish with Quechua and Aymara passages (transcription Murra, Adorno, Urioste; synchronized 11 October 2026) | Public Domain Mark 1.0 |
| `hdic` | [HDIC](https://github.com/shikeda/HDIC) | The Heian-period hanzi dictionaries: Yuanben/Songben Yupian, Tenrei Banshō Meigi, Shinsen Jikyō | CC BY-SA 4.0 |
| `hebrew-lexicon` | [OpenScriptures HebrewLexicon](https://github.com/openscriptures/HebrewLexicon) | Two dictionaries: 9,299 augmented-Strong entries (every OSHB lemma resolves) + the 11,845-entry BDB outline with print-page anchors (synchronized 18 July 2026) | CC BY 4.0 |
| `helipad` | [HeliPaD](https://zenodo.org/records/4395040) (Walkden) | The Old Saxon *Heliand*, syntactically parsed with gold form-lemma pairs (synchronized 22 July 2026) | CC BY 4.0 |
| `hittite-glossed` | [Glossed Hittite Texts with German Translation](https://doi.org/10.5281/zenodo.14266302) (Zenodo) | 7,099 glossed Hittite texts / 72,507 passages with German translation (synchronized 29 September 2026) | CC BY 4.0 |
| `honkoku` | [みんなで翻刻 honkoku-data](https://github.com/yuta1984/honkoku-data) | Citizen transcriptions of premodern Japanese documents: 6,092 items / 129,458 passages, each crediting its holding institution (synchronized 29 September 2026) | CC BY-SA 4.0 |
| `hr-wikisource` | [Croatian Wikisource](https://hr.wikisource.org/) | The premodern cone, Middle Ages to the 18th century: 1,390 texts / 132,052 passages (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `iecor` | [IE-CoR](https://iecor.clld.org/) (lexibank/iecor via Zenodo) | The Indo-European cognacy database: 4,981 expert-curated cognate sets with loan events (synchronized 14 July 2026) | CC BY 4.0 |
| `iedc` | [Invisible East Digital Corpus](https://invisible-east.org/) (Univ. of Oxford) | 1,316 documents of the medieval Islamicate East — New Persian, Sogdian, Bactrian, Judeo-Persian, Middle Persian, Arabic — with typed dates and located toponyms (synchronized 28 September 2026) | CC BY 4.0 |
| `iip` | [Inscriptions of Israel/Palestine](https://github.com/Brown-University-Library/iip-texts) (Brown) | 5,499 inscriptions, Hebrew/Aramaic/Greek/Latin, ~500 BCE–640 CE (synchronized 18 July 2026) | CC BY-NC 4.0 |
| `isicily` | [I.Sicily](https://github.com/ISicily/ISicily) (Prag, Oxford / ERC Crossreads) | 5,074 inscriptions of ancient Sicily across all its languages — incl. Sicel, Elymian, Sicilian Punic and Mamertine Oscan in their only machine-readable form (synchronized 18 July 2026) | CC BY 4.0 |
| `iswoc` | [ISWOC treebank](https://github.com/iswoc/iswoc-treebank), Oslo | Old English prose and the West-Saxon Gospels, gold-annotated | CC BY-NC-SA |
| `itant` | [Corpus ItAnt](https://github.com/DigItAnt/Corpus_ItAnt) (CNR-ILC/UniFI) | 501 Oscan + 9 Lepontic critical editions with English/Italian translations (synchronized 18 July 2026) | CC BY-NC-SA 4.0 |
| `itkc` | [한국고전번역원 ITKC classical originals](https://www.data.go.kr/data/15022432/fileData.do) (Institute for the Translation of Korean Classics, open datasets) | 10,572 documents of classical Korean writing in hanmun (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `ja-wikisource` | [Japanese Wikisource](https://ja.wikisource.org/) | The premodern era cone, Asuka to Edo: 838 documents / 88,745 passages, the *Man'yōshū* cited by poem number (synchronized 29 September 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `kannada-texts` | [Kannada critical editions](https://github.com/sarit/kannada-texts) (A. Ollett) | 16 texts / 16,151 passages — Old and Middle Kannada literature (synchronized 11 October 2026) | In-file CC BY-SA 4.0 grants; repository README CC BY 4.0 |
| `kanripo` | [Kanseki Repository 漢籍リポジトリ](https://github.com/kanripo) (Wittern, Kyoto) | The classical Chinese library — KR1 classics through KR5 Daoist canon; with CBETA it makes Literary Chinese the corpus's largest language (synchronized 20 July 2026) | CC BY-SA 4.0 (org-level grant) |
| `kdsp` | [KDSP](http://hdl.handle.net/11356/1823) (ZRC SAZU, CLARIN.SI) | Longer Slovenian narrative prose 1836–1918: 262 works / 290,394 passages (synchronized 11 October 2026) | CC BY 4.0 |
| `ko-wikisource-mk` | [Korean Wikisource](https://ko.wikisource.org/) — 용비어천가 | The *Yongbi eocheon ga* (1447), among the first works written in hangul, as the Middle Korean shelf (synchronized 18 August 2026) | Text PD; transcription CC BY-SA 4.0 |
| `kokubunken` | [NIJL kokubunken TEI](https://github.com/kokubunken) (National Institute of Japanese Literature) | The Karoku 2 *Kokinshū* and two *Man'yōshū* witnesses in TEI (synchronized 29 September 2026) | CC BY 4.0 |
| `kouigenji` | [校異源氏物語 text DB](https://kouigenjimonogatari.github.io/) (デジタル源氏物語) | Ikeda Kikan's critical *Genji monogatari* in TEI, 54 chapters (synchronized 29 September 2026) | CC BY 4.0 |
| `larth-etp` | [Larth / Etruscan Texts Project glossary](https://github.com/GianlucaVico/Larth-Etruscan-NLP) | The ETP scholarly Etruscan glossary, 1,122 entries (synchronized 18 July 2026) | CC BY 4.0 |
| `lexica` | [PerseusDL lexica](https://github.com/PerseusDL/lexica) | Liddell-Scott-Jones; Lewis &amp; Short | CC BY-SA 4.0 |
| `lexlep`, `lexlep-words` | [Lexicon Leponticum](https://lexlep.univie.ac.at/) (Vienna) | 494 Cisalpine Celtic inscriptions + the 627-word Lepontic lexicon with morphemic analyses (synchronized 18 July 2026) | Conflicting statements (terms CC BY-SA 3.0 vs footer NC) — held at `nc` pending clarification |
| `litopys` | [Izbornyk](http://litopys.org.ua/) (litopys.org.ua) — the public-domain-edition subset | The complete Ipatiev chronicle after the 1908 Petersburg edition, plus three 19th-century glossaries (synchronized 11 October 2026) | Public domain per text |
| `liv` | [LiLa / CIRCSE LIV-LOD](https://lila-erc.eu/) | *Lexikon der indogermanischen Verben* linked-data edition: 305 PIE verbal etymons (synchronized 14 July 2026) | CC BY-SA 4.0 (with publisher permission) |
| `lo-congres` | [Lo Congrès Occitan news corpus](https://zenodo.org/records/8411197) | Occitan in six dialects, aligned with French (synchronized 19 August 2026) | CC BY 4.0 |
| `madurai` | [Project Madurai](https://www.projectmadurai.org/) (K. Kalyanasundaram et al.) | 755 classical Tamil e-texts / 1,214,683 line passages, the pre-modern cone of the works list (synchronized 13 October 2026) | Header grant: freely distributable with the header page intact — carried verbatim on every document |
| `mdz-protestant` | [MDZ](https://www.digitale-sammlungen.de/) (Bayerische Staatsbibliothek) | 16th-century Slovene and Croatian Protestant prints — Trubar, Bohorič — in MDZ's uncorrected page OCR (synchronized 11 October 2026) | Public Domain Mark 1.0 (two Google-digitized copies held `nc`) |
| `menggu-ziyun` | [menggu-ziyun-data](https://github.com/nk2028/menggu-ziyun-data) (nk2028) | The 蒙古字韻 'Phags-pa rhyme book of 1308, with reconstructions: 9,446 entries (synchronized 29 August 2026) | MIT |
| `menota` | [Menota — the Medieval Nordic Text Archive](https://clarino.uib.no/menota/catalogue/menota) (Univ. of Bergen / CLARINO) | 91 Old Icelandic, Old Norwegian, Old Swedish and Old Danish manuscripts / 229,501 lines in multi-level transcription (synchronized 23 August 2026) | CC BY-SA 4.0 |
| `menotec` | [Menotec, via CLARINO INESS](https://clarino.uib.no/iness) (Bergen/Oslo) | Seven Old Norwegian treebanks and the Poetic Edda of Codex Regius, gold PROIEL-scheme annotation (synchronized 22 July 2026) | CC BY-NC-SA 4.0 |
| `mk-wikisource` | [Macedonian Wikisource](https://mk.wikisource.org/) | The 19th-century cone: the Miladinov brothers, Šapkarev, Cepenkov, Pejčinović (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `monlam-lexicon` | [Monlam Tibetan headword lists](https://github.com/MonlamIT/Tibetan-Lexicon) (Monlam IT) | 449,829 Tibetan headwords — the word lists only; no definitions are machine-readably licensed (synchronized 29 August 2026) | Apache-2.0 |
| `ms-wikisource` | [Malay Wikisource](https://ms.wikisource.org/) | The Jawi manuscript cone: 64 manuscripts / 5,081 passages from the Leiden and British Library scan Indexes (synchronized 12 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `mvp` | [Mahāvyutpatti](https://glossaries.dila.edu.tw/glossaries/MVP) (DILA TEI edition) | The 9th-century imperial Sanskrit–Tibetan–Chinese glossary: 9,379 entries beside Monier-Williams (synchronized 28 July 2026) | Public Domain (DILA's stated belief) |
| `mw` | [Cologne Digital Sanskrit Lexicon](https://www.sanskrit-lexicon.uni-koeln.de/) | Monier-Williams Sanskrit-English Dictionary (1899), 193,890 entries | CC BY-NC-SA 3.0 |
| `ndl-kotenseki` | [NDL 次世代デジタルライブラリー](https://lab.ndl.go.jp/service/tsugidigi/) (National Diet Library) | Machine-OCR full text of the Diet Library's copyright-expired classical books, crawled at a gentle committed pace: 32,733 documents / 1,392,445 passages so far, each with its viewer permalink (synchronized from 29 September 2026, last slice 13 October 2026) | Copyright-expired materials only; bulk route confirmed by NDL Lab (by email, 2026-09-29) |
| `obi-burmese` | [OBI — Structured Corpus of Old Burmese Stone Inscriptions](https://zenodo.org/records/4321314) | 1,121 Old Burmese inscriptions of Bagan (synchronized 1 September 2026) | CC BY 4.0 |
| `ogham` | [Ogham in 3D](https://ogham.celt.dias.ie/) v2.0 (DIAS / Maynooth) | ~500 ogham stones in real Ogham codepoints with transliteration layers (synchronized 17 July 2026) | Conflicting statements (site CC BY-NC-SA vs in-file CC BY 4.0) — held at the restrictive `nc` reading pending clarification |
| `ojw` | [OJW — the Old Javanese Wordnet](https://github.com/davidmoeljadi/OJW) (Moeljadi et al.) | 3,632 Old Javanese wordnet entries, the Southeast Asia desk's glossary (synchronized 1 September 2026) | CC BY 4.0 |
| `okhc` | [Open Korean Historical Corpus](https://huggingface.co/datasets/seyoungsong/Open-Korean-Historical-Corpus) (historical slice) | 1,198,779 records / 3,542,662 passages of the Korean historical record (synchronized 1 September 2026) | CC BY-NC 4.0 (public-domain rows relabelled `open`) |
| `old-tibetan` | [Old Tibetan Corpus](https://github.com/tibetan-nlp/old-tibetan-corpus) | The Old Tibetan Annals and Chronicle, annotated, the Annals paired with Dotson's English translation (synchronized 28 July 2026) | MIT |
| `oncoj`, `oncoj-lexicon` | [ONCOJ](https://oncoj.ninjal.ac.jp/) (Oxford-NINJAL) | The Corpus of Old Japanese — gold-morphology Man'yōshū-era verse — and its lexicon (synchronized 20 July 2026) | CC BY 4.0 (annotation; the texts are ancient) |
| `open-etruscan` | [OpenEtruscan](https://doi.org/10.5281/zenodo.20075836) | 6,248 Etruscan inscriptions with English siblings (synchronized 18 July 2026) | CC BY 4.0 |
| `openiti` | [OpenITI — Open Islamicate Texts Initiative](https://openiti.org/) (2025.1.9 Zenodo release) | The Islamicate library at corpus scale: 9,079 primary text versions of premodern Arabic and Persian — hadith, falsafa, history, poetry — 34.6M passages parsed from OpenITI mARkdown (synchronized 23 July 2026) | CC BY-NC-SA 4.0 (the Zenodo record's grant) |
| `openmgh` | [openMGH](https://www.mgh.de/en/digital-mgh/openmgh) (Monumenta Germaniae Historica + Bayerische Staatsbibliothek) | The critical-edition backbone of medieval Latin as TEI: the complete openMGH offering, 153 volumes — the SS rerum Germanicarum series (Einhard, the Frankish annals, Widukind, Adam of Bremen) joined by the Auctores antiquissimi, SS rerum Merovingicarum, Diplomata and further series (second wave synchronized 3 August 2026) | CC BY 4.0 (texts themselves free of copyright) |
| `oracc` | [ORACC](https://oracc.museum.upenn.edu/), 102 projects incl. the State Archives of Assyria, the Achaemenid royal trilinguals, the four ePSD2 corpora, and the P46 CC0 pack — eCUT (Urartian), the Amarna letters, the ATAE/TCMA Assyrian archives | 118,366 cuneiform tablets with gold lemmatization (synchronized 26 July 2026); since 26 September 2026 also the project glossaries as a dictionary lane — 340 glossaries, 211,040 entries | CC0 (per project); translation prose CC BY-SA |
| `oshb` | [Open Scriptures Hebrew Bible](https://github.com/openscriptures/morphhb) | The Westminster Leningrad Codex — 39 books, 23,213 verses with full morphology and ketiv/qere, byte-verbatim Masoretic text (synchronized 18 July 2026) | Text public domain; morphology CC BY 4.0 |
| `osta` | [OSTA — Old Spanish Textual Archive](https://github.com/hispanicseminary/OSTA) (Hispanic Seminary of Medieval Studies) | 740 Old Spanish texts (synchronized 13 August 2026) | CC BY-NC-SA 4.0 |
| `otdo` | [Old Tibetan Documents Online](https://otdo.aa-ken.jp/) (ILCAA, Tokyo) | 413 critical editions of Old Tibetan: the Dunhuang scrolls, the imperial pillar inscriptions, five Old Zhangzhung texts (synchronized 28 July 2026) | CC BY 4.0 |
| `papyri-ddbdp` | [papyri.info](https://papyri.info/) — Duke Databank of Documentary Papyri + DCLP | 61,414 documentary papyri; since 26 September 2026 also the DCLP literary/paraliterary papyri (2,245 documents) | CC BY |
| `perseus-anglit` | [Perseus canonical-angLit](https://github.com/PerseusDL/canonical-angLit) | *Beowulf* in the Perseus edition (synchronized 3 September 2026) | CC BY-SA 3.0 US |
| `perseus-farsilit` | [Perseus canonical-farsiLit](https://github.com/PerseusDL/canonical-farsiLit) | The *Dīwān* of Ḥāfeẓ (synchronized 3 September 2026) | CC BY-SA 3.0 US |
| `perseus-greek`, `perseus-latin` | [Perseus Digital Library](https://www.perseus.tufts.edu/) (PerseusDL canonical-greekLit / canonical-latinLit) | The classical Greek and Latin canons with English translations | CC BY-SA |
| `peshitta` | [ETCBC peshitta](https://github.com/ETCBC/peshitta) | The Peshitta Old Testament incl. deuterocanon — 65 books / 31,341 verses; the Syriac leg of the verse-alignment hub (synchronized 19 July 2026) | CC BY-NC 4.0 |
| `pl-wikisource` | [Polish Wikisource](https://pl.wikisource.org/) | The premodern Polish-literature cone, with Brückner's 1927 etymological dictionary of Polish as a queryable shelf (5,711 entries; synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `prague-bible-1488` | [HTR Winter School 2024 — the Prague Bible (1488)](https://doi.org/10.5281/zenodo.14524858) | Medieval Czech ground-truth transcription of the first complete printed Czech Bible (synchronized 10 October 2026) | CC BY-SA 4.0 (the stricter of the deposit's two statements) |
| `prakrit-texts` | [Prakrit critical editions](https://github.com/sarit/prakrit-texts) (A. Ollett) | 22 texts / 27,124 passages, the library's first individually-named Prakrit (synchronized 11 October 2026) | Per-file CC BY-SA statements |
| `prilit` | [PriLit](http://hdl.handle.net/11356/1319) (ZRC SAZU / JSI, CLARIN.SI) | Older Slovenian narrative prose: 43 works (synchronized 3 September 2026) | CC BY 4.0 |
| `proiel` | [PROIEL treebank](https://proiel.github.io/) | Parallel NT (Greek, Latin, Gothic, Armenian, OCS) + classical prose, gold-annotated | CC BY-NC-SA |
| `qieyun-restored` | [qieyun-restored](https://github.com/nk2028/qieyun-restored) (nk2028; restoration by Fujita Takumi) | The 切韻 of 601 CE in Fujita's restoration: 11,158 entries, cross-linked rime by rime to the Guangyun (synchronized 29 August 2026) | MIT |
| `ref` | [ReF — Referenzkorpus Frühneuhochdeutsch](https://zenodo.org/records/5793616) | Early New High German 1350–1650: 190 texts / 447,115 passages, annotated (synchronized 19 August 2026) | CC BY-SA 4.0 (the stricter of the deposit's statements) |
| `rem` | [Referenzkorpus Mittelhochdeutsch](https://zenodo.org/records/13982324) (Bochum/Bonn) | 360 gold-annotated Middle High German texts, 1050–1350, diplomatic layer preserved (synchronized 22 July 2026) | CC BY-SA 4.0 |
| `ren` | [Referenzkorpus Mittelniederdeutsch/Niederrheinisch](https://www.fdr.uni-hamburg.de/record/9195) (Univ. Hamburg) | 235 Middle Low German / Low Rhenish texts, 1200–1650: 1.49M gold-annotated + 838K transcribed tokens, the Hanseatic rung (synchronized 26 July 2026) | CC BY 4.0 (the deposit's stated license) |
| `riig` | [RIIG — Recueil informatisé des inscriptions gauloises](https://riig.huma-num.fr/) (ANR, Ausonius/Bordeaux) | 428 Gaulish inscriptions, Gallo-Greek and Gallo-Latin, with French translations (synchronized 17 July 2026) | CC BY 4.0 (in-file grant) |
| `rsti` | [Ras Shamra Tablet Inventory](https://ochre.uchicago.edu/) (University of Chicago, OCHRE/CORPUS) | 5,075 inscribed-object inventory cards from Ugarit with the RS↔KTU/CTA concordances the field cites, and published editions at line grain (synchronized under a written grant, 1 August 2026) | CC BY-NC-SA 4.0 grant |
| `ru-wikisource` | [Russian Wikisource](https://ru.wikisource.org/) | The Old East Slavic cone, edition-filtered: texts keyed to in-copyright editions are excluded by rule (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `rundata` | [Samnordisk runtextdatabas / Rundata](https://www.runforum.nordiska.uu.se/srd/) (Uppsala, via rundata.info) | ~6,800 Scandinavian runic inscriptions in up to five text lanes: transliteration, Old-West-Norse and runic-Swedish normalisations, English and Swedish translations (synchronized 22 July 2026) | ODbL 1.0 + DbCL 1.0 — *based on the Scandinavian Runic-text Database* |
| `sabellic-loans` | en.wiktionary curation | 85 Latin lemmas with Oscan/Umbrian/Sabine etyma, loan-flagged (curated 18 July 2026) | CC BY-SA + GFDL |
| `salom` | [Şalom Ladino articles](https://huggingface.co/datasets/collectivat/salom-ladino-articles) (Col·lectivaT / Sephardic Center of Istanbul) | Judeo-Spanish news text from the Istanbul weekly *Şalom* (synchronized 19 August 2026) | CC BY 4.0 |
| `sarit` | [SARIT](https://sarit.indology.info/) | 78 scholarly TEI editions incl. a complete Southern-Recension Mahābhārata, Devanagari + IAST (synchronized 18 July 2026) | CC BY-SA (per file) |
| `sblgnt` | [SBL Greek New Testament](https://sblgnt.com/) (SBL / Logos) | Critical edition of the Greek NT | CC BY 4.0 |
| `scripta-bulgarica` | [Scripta Bulgarica](http://scripta-bulgarica.eu) (Bulgarian Academy of Sciences, Institute for Literature) | 124 medieval Bulgarian monuments — the Bitola inscription, charters, damaskini — each with its printed-edition citation (synchronized 28 September 2026) | CC BY-NC-SA 2.0 |
| `sdbh` | [UBS Semantic Dictionary of Biblical Hebrew](https://github.com/ubsicap/ubs-open-license) | 7,932 entries with semantic domains and 260,813 verse-level scripture references (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `seal` | [SEAL — Sources of Early Akkadian Literature](https://seal.huji.ac.il) (M. P. Streck and N. Wasserman) | 408 Old Babylonian and Old Akkadian literary texts, cited by SEAL number (synchronized 30 August 2026) | Personal research grant (N. Wasserman, by email, 2026-08-30) — held at `research_private`, never redistributed |
| `sefaria` | [Sefaria](https://www.sefaria.org/) (Sefaria-Export, named versions only) | The Targum shelf plus the Rabbinic library — Mishnah (three complete Hebrew editions incl. the Kaufmann MS), the Wikisource Bavli, Guggenheimer's Yerushalmi, Tosefta, Minor Tractates, the Davidson/Steinsaltz nc lane: with daf-grain Talmud citations, joined by the classical midrash (the ten Rabbah collections and the Midrash Halakhah shelf, synchronized 1 August 2026) | Per version (PD / CC0 / CC BY / CC BY-SA; NC versions carried as `nc`) |
| `shabados` | [Shabad OS database](https://github.com/shabados) (Shabad OS Organization and contributors) | The Gurmukhī primary text of Sikh scripture: 127 section documents / 141,264 lines — the Gurū Granth Sāhib, the Vārāṅ of Bhāī Gurdās, the Dasam-tradition works (synchronized 13 October 2026) | Public Domain Mark 1.0 (scripture primary text) |
| `shkz` | [ŠKZ — the trilingual Kaʿba-ye Zartošt inscription](https://doi.org/10.5281/zenodo.15050878) (Shamsian &amp; Berti) | Šābuhr I's res gestae in Middle Persian, Parthian and Greek, sentence-aligned (synchronized 28 September 2026) | CC BY 4.0 |
| `siddham` | [Siddham — the South Asia inscriptions database](https://siddham.network/) | 427 Gupta-era inscriptions / 6,334 passages, regnal years converted through the era table (synchronized 11 October 2026) | CC BY-SA 4.0 (Zenodo record) |
| `sii-clean` | [South Indian Inscriptions, DHARMA conversions](https://github.com/erc-dharma/south-indian-inscriptions) (ERC project no. 809994; original editions Archaeological Survey of India) | The 589 license-marked editions / 8,372 passages of the printed SII volumes, original ASI editors credited per document (synchronized 13 October 2026) | Per-file CC BY-SA 4.0 statements |
| `sillok` | [조선왕조실록 Veritable Records of the Joseon Dynasty](https://www.data.go.kr/data/15053647/fileData.do) (National Institute of Korean History) | 743 volumes / 414,321 entries of the dynasty's annals (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `sjw` | [승정원일기 Daily Records of the Royal Secretariat](https://www.data.go.kr/data/15064218/fileData.do) (National Institute of Korean History) | 297 volumes / 1,896,858 entries (synchronized 18 August 2026) | KOGL open (unrestricted use), credit the institute |
| `skjaervo-khotanese` | [Khotanese Manuscripts from Chinese Turkestan in the British Library](https://doi.org/10.5281/zenodo.3372682) (P. O. Skjærvø) | 2,357 manuscript records / 14,574 transliterated Khotanese lines — upstream's own draft caveat carried verbatim (synchronized 28 September 2026) | CC BY 4.0 |
| `sl-lexica` | [ZRC SAZU](https://www.zrc-sazu.si/) via [CLARIN.SI](https://www.clarin.si/) | Pleteršnik's *Slovensko-nemški slovar* (1894–95), the Janez Svetokriški lexicon, and the 16th-century Slovenian word inventory — 139,405 entries (synchronized 17 July 2026) | CC BY 4.0 |
| `sl-wikisource` | [Wikivir — Slovene Wikisource](https://sl.wikisource.org/) | The dated cone to 1899: 1,539 texts / 145,035 passages (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `slavistics-pd` | Public-domain Slavistics reference shelf ([archive.org](https://archive.org/details/etymologischesw00mikluoft) scans) | Miklosich, Berneker, Leskien, Vondrák and Jagić in archive.org's uncorrected OCR, OCR quality measured per volume (synchronized 11 October 2026) | Public domain |
| `slouniki-nasovic` | [Slouniki — Nasovič](https://github.com/Belarus/Slouniki-Nasovic) | Nasovič's *Slovar' belorusskago narěčija* (1870): 35,159 entries, opening the Belarusian shelf (synchronized 11 October 2026) | Public domain |
| `soas-tibetan` | [SOAS gold POS corpus](https://doi.org/10.5281/zenodo.574878) (Hill & Garrett) | Four classical texts with hand-corrected segmentation and POS — 991 lines / 318K tokens (synchronized 28 July 2026) | CC BY 4.0 |
| `sr-wikisource` | [Serbian Wikisource](https://sr.wikisource.org/) | The oral-tradition cone: the epic songs, the Erlangen manuscript, Vuk's collections — 4,607 texts / 581,423 passages (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `starling` | [StarLing / Tower of Babel](https://starlingdb.org/) (G. Starostin et al.) | The etymological databases — 56 shelves, 113,419 entries as of October 2026: Pokorny's IEW, Nikolayev's PIE database, Vasmer's dictionary of Russian (Trubachev ed.), Common Germanic, Baltic, the Kartvelian base (Klimov lineage), and — since 26 September 2026 — Altaic with its Japanese companion, North Caucasian, Sino-Tibetan, Dravidian, the Chukchee-Kamchatkan trio, and Yenisseian; since October 2026 the Indo-European package's thirteen lexicostatistical tables | Written grant ("free for anybody to use … as long as the source is properly acknowledged"), per-base compiler credit carried on every surface |
| `suttacentral` | [SuttaCentral](https://suttacentral.net/) bilara-data | The Pali Tipiṭaka (Mahāsaṅgīti) + the Patna Dhammapada, with segment-aligned English (synchronized 18 July 2026) | CC0 (per publication) |
| `syriac-corpus` | [Digital Syriac Corpus](https://syriaccorpus.org/) (Srophé) | 632 classical Syriac TEI documents — a millennium of literature (synchronized 19 July 2026) | CC BY 4.0 (per file) |
| `tamilex` | [TAMILEX](https://github.com/UHH-Tamilex) (Universität Hamburg; E. Wilden, J.-L. Chevillard) | Critical TEI editions of the classical Tamil corpus: 7,830 documents / 14,972 passages with 262,093 gold wordsplit rows (synchronized 13 October 2026) | CC BY-NC-SA 4.0 (stated by the maintainers, 2026-10-12; repository license file pending) |
| `th-wikisource` | [Thai Wikisource](https://th.wikisource.org/) | The Collected Chronicles to BE 2473 and the Three Seals Law tradition: 92 documents / 11,006 passages (synchronized 12 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `tibetan-verbs` | [Tibetan Verbs Database](https://github.com/tibetan-nlp/tibetan-verbs-database) | 2,491 verb tense-stem tuples (synchronized 28 July 2026) | CC0 |
| `ticha` | [Ticha](https://github.com/HCDigitalScholarship/ticha-xml-tei) (Haverford College; B. D. Lillehaugen et al.) | Colonial Valley Zapotec in TEI: Córdova's 1578 *Arte*, the notarial testaments and their period Spanish translations (synchronized 11 October 2026) | CC BY-SA 4.0 |
| `tir` | [Thesaurus Inscriptionum Raeticarum](https://tir.univie.ac.at/) (Vienna) | 389 Raetic inscriptions — the corpus of record (synchronized 18 July 2026) | Same conflicting statements — held at `nc` |
| `titus-avestan` | [TITUS — Avestan corpus](https://titus.uni-frankfurt.de/) (J. Gippert, Frankfurt) | The Avestan canon: 248 documents / 40,108 passages (synchronized August 2026) | Personal research grant (by email, 2026-07-23) — held `nc`, never redistributed |
| `titus-bactrian` | [TITUS — Bactrian documents](https://titus.uni-frankfurt.de/) | 123 documents / 3,537 passages (synchronized October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-khotanese` | [TITUS — Khotanese books](https://titus.uni-frankfurt.de/) | 1,648 documents / 20,279 passages (synchronized October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-manichaica` | [TITUS — Manichaica](https://titus.uni-frankfurt.de/) | 542 documents / 3,089 passages in Middle Persian, Parthian and Sogdian (synchronized October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-osco-umbrian` | [TITUS — Osco-Umbrian corpus](https://titus.uni-frankfurt.de/) | The complete Iguvine Tables with the Oscan inscriptions: 386 documents / 1,697 passages (synchronized 31 August 2026) | Personal research grant (by email, 2026-08-31) — held `nc` |
| `titus-pahlavi` | [TITUS — Pahlavi books](https://titus.uni-frankfurt.de/) | The Zoroastrian theological library: 1,572 documents / 20,302 passages (synchronized October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-sogdian` | [TITUS — Sogdian books](https://titus.uni-frankfurt.de/) | 364 documents / 21,354 passages (synchronized October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-tocharian-a` | [TITUS — Tocharian A corpus](https://titus.uni-frankfurt.de/) (data entry Gippert, Carling et al.) | 466 documents / 5,779 passages (synchronized 10 October 2026) | Personal research grant (by email, 2026-10-06) — held `nc` |
| `titus-tocharian-b` | [TITUS — Tocharian B corpus](https://titus.uni-frankfurt.de/) (data entry Olivier, Schaefer, Tamai, Kupfer; London/Paris Widmer, Kupfer, Peyrot) | The whole members-area chain: 4,250 documents / 43,480 passages across the Berlin, London and Paris collections, retrieved through the credentials seam (synchronized 13 October 2026) | Personal research grant (by email, 2026-10-06) — held `nc`, never redistributed |
| `tla-hf` | [Thesaurus Linguae Aegyptiae](https://huggingface.co/thesaurus-linguae-aegyptiae) official datasets | 13,383 Demotic + 3,606 Late Egyptian sentences with German — the only bulk demotic anywhere (synchronized 18 July 2026) | CC BY-SA 4.0 |
| `tlhdig` | [TLHdig](https://www.hethiter.net/) (Thesaurus Linguarum Hethaeorum digitalis, Hethitologie-Portal Mainz) | The Hittite corpus: 23,486 tablet manuscripts in 663 CTH compositions — >98% of published Hittite fragments, with cuneiform, transliteration and candidate morphology (synchronized 19 July 2026) | CC BY 4.0 |
| `tls` | [Thesaurus Linguae Sericae](https://hxwd.org/) (tls-kr/tls-data) | Concept and word nets over classical Chinese with sense-level attributions into the classics (synchronized 20 July 2026) | CC BY-SA 4.0 |
| `torot` | [TOROT](https://torottreebank.github.io/) — Tromsø OCS and Old Russian Treebank | OCS and Old East Slavic, gold-annotated | CC BY-NC-SA |
| `traces` | [TraCES](https://www.traces.uni-hamburg.de/) (ERC 338756, Hamburg) | 75,440 morphologically analyzed Gəʿəz tokens, lemma-linked into Dillmann's entries — Matthew, Kebra Nagast, chronicles, Aksumite royal inscriptions (synchronized 26 July 2026) | CC BY-NC-ND 4.0 (ZFDM record 707) |
| `tshet-uinh` | [tshet-uinh-data](https://github.com/nk2028/tshet-uinh-data) (nk2028) | The 廣韻 Guangyun critical edition — Qieyun-system Middle Chinese phonology (synchronized 19 July 2026) | CC0 1.0 |
| `ud` | [Universal Dependencies](https://universaldependencies.org/) (some forty historical treebanks) | Latin (Aquinas, Perseus, and the medieval-to-vernacular continuum), Ancient Greek (Perseus), Vedic Sanskrit, Gothic, Greek, Old East Slavic (birchbark, RNC, Ruthenian), Old Irish glosses (St Gall Priscian, Würzburg), Hittite (HitTB — since 19 July 2026), Classical Chinese, Old Icelandic, Old French, Coptic, Old Turkic, and — since October 2026 — Tupinambá and Old Guaraní | CC BY-SA / CC BY-NC-SA per treebank |
| `uk-wikisource` | [Ukrainian Wikisource](https://uk.wikisource.org/) | The chronicles, edition-filtered (synchronized 10 October 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `unihan` | [Unihan](https://www.unicode.org/reports/tr38/) — the Unicode Han Database | 65,092 Han codepoint records: radicals, strokes, variants, readings (synchronized 20 July 2026) | Unicode License V3 |
| `viet-wikisource` | [Wikisource](https://zh.wikisource.org/) — the Đại Việt classical shelf | The 大越史記全書 and chữ Hán showpieces of Vietnam's classical literature (synchronized 18 August 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `vuk-danicic` | [Rs1Bible](https://github.com/spthmpsn/Rs1Bible) (USFM, after the Unbound Bible) | The Vuk–Daničić Serbian Bible — the 1847 New Testament and 1865 Old Testament, ijekavian (synchronized 11 October 2026) | Public domain |
| `vulgate` | [open-bibles](https://github.com/seven1m/open-bibles) / [eBible.org](https://ebible.org/) (Tweedale text) | The complete Clementine Vulgate, 73 books | Public domain |
| `westoldturkic` | [West Old Turkic](https://doi.org/10.5281/zenodo.7893910) (Róna-Tas &amp; Berta 2011, CLDF) | 480 Turkic loanwords in Hungarian with their etymologies (synchronized 29 September 2026) | CC BY 4.0 |
| `wiktionary-akk`, `wiktionary-hit`, `wiktionary-sux` | [kaikki.org](https://kaikki.org/) (Wiktextract) from [Wiktionary](https://www.wiktionary.org/) | The Akkadian, Hittite and Sumerian lexica, whose sense glosses ride the cuneiform sign cards (synchronized August–September 2026) | CC BY-SA + GFDL |
| `wiktionary-bo` | Wiktionary Tibetan (kaikki extract) | 3,651 entries with reflex edges (synchronized 28 July 2026) | Wiktionary dual license (CC BY-SA) |
| `wiktionary-cu`, `wiktionary-recon` | [kaikki.org](https://kaikki.org/) (Wiktextract) from [Wiktionary](https://www.wiktionary.org/) | OCS lexicon; seven reconstruction dictionaries (PIE, Proto-Slavic, Proto-Germanic, Proto-West Germanic, Proto-Balto-Slavic, Proto-Italic, Proto-Indo-Iranian) with descendant trees; Old Irish, Middle Irish, Middle Welsh, Old Japanese, Etruscan, and Umbrian extracts; and — since 26 September 2026 — the Chinese lexicon (323,839 entries) | CC BY-SA + GFDL |
| `wold` | [WOLD — World Loanword Database](https://wold.clld.org/) (MPI-EVA / Lexibank) | 41 vocabularies / 64,289 lexemes with loanword status and donor languages — the loanword-flow layer of the comparativist desk (synchronized 26 July 2026) | CC BY 4.0 |
| `zh-wikisource` | [Chinese Wikisource](https://zh.wikisource.org/) | Censused works: the complete 全唐文, the 續資治通鑑, and the Ming Chinese 元朝秘史 — 1,238 documents / 71,547 passages (synchronized 29 September 2026) | Texts PD; transcription CC BY-SA 4.0 |
| `zhongyuan` | [zhongyuan-data](https://github.com/nk2028/zhongyuan-data) (nk2028) | The 中原音韻 Old Mandarin rhyme book of 1324 with four reconstruction lanes: 5,877 entries (synchronized 29 August 2026) | CC0 1.0 |

## Feature modules

A further {{ census.feature_modules }} registry rows are **feature modules**, not corpora:
machinery that fetches reference data but mints no documents of its own.

| Module | What it provides | License |
|---|---|---|
| `actib` | The segmented-Tibetan anchor layer, republished through nabu-data | CC BY 4.0 |
| `althurayya` | The [al-Ṯurayyā Gazetteer](https://althurayya.github.io/) of the early Islamic world — the place lane of the Arabic desk | CC BY 4.0 |
| `bridging` | The OSHB ↔ BHSA verse crosswalk | MIT |
| `burman-concordance` | The [Burman Digital Concordance](https://zenodo.org/records/7801485) of Etruscan, Faliscan and early Latin inscriptions — the crosswalk between the Italic editions | CC0 |
| `cbdb` | The [China Biographical Database](https://github.com/cbdb-project/cbdb_sqlite) — the person index behind `nabu person` | CC BY-NC-SA 4.0 |
| `chgis` | The [China Historical GIS](https://doi.org/10.7910/DVN/H3OB28) temporal gazetteer — the place lane of the Sinitic desk | CC0 1.0 |
| `cigs` | The [Cuneiform Inscriptions Geographical Sites](https://zenodo.org/records/14568765) index — site mnemonics behind hundreds of thousands of cuneiform findspot links | CC BY 4.0 |
| `cldf-spine` | The shared Cross-Linguistic Data Formats reference tables ([Concepticon](https://concepticon.clld.org/) + [Glottolog](https://glottolog.org/)) that WOLD/CLICS rows resolve through | CC BY 4.0 |
| `edubba-overlay` | The didactic overlay from [Edubba](https://arvicco.github.io/nabu-edubba), the scribal-school sibling — course keywords and chapters riding the hieroglyph cards | CC BY-SA 4.0 |
| `hypotactic` | Greek metrical scansion — meter, pattern and caesura annotated onto held verse | CC BY 4.0 |
| `kitab` | [KITAB](https://kitab-project.org/) text-reuse alignments over the OpenITI library | CC BY-NC-SA 4.0 |
| `kitab-reuse` | The [KITAB](https://doi.org/10.5281/zenodo.11501559) pairwise text-reuse statistics over the OpenITI library | CC BY-NC-SA 4.0 |
| `kr-gaiji` | The Kanripo gaiji (rare-glyph) map | CC BY-SA 4.0 (the kanripo org grant) |
| `lila` | The [LiLa](https://lila-erc.eu/) Latin lemma bank behind `nabu define`'s variant-spelling fallback | CC BY-SA 4.0 |
| `nabu-data` | The library's own [published datasets](https://github.com/arvicco/nabu-data), consumed back as a source — e.g. the Sanskrit form→lemma table behind `nabu define`'s inflected-form expansion; the reproducibility loop closed in public | CC BY 4.0 |
| `nabu-lects` | The [lect registry](https://arvicco.github.io/nabu-lects) sister project — the stage ladders, stage-aware search and reconstruction honesty on the [Languages]({{ '/languages/' | relative_url }}) page | CC BY 4.0 |
| `nabu-places` | The [place-decisions registry](https://arvicco.github.io/nabu-places) sister project — which gazetteer identity each source's verbatim place name denotes; see [Places]({{ '/layers/' | relative_url }}#places) | CC BY 4.0 |
| `nrct` | [NRCT](https://geoshape.ex.nii.ac.jp/nrct/) — the historical placenames of Japan (日本歴史地名大系) behind the Japanese place lane | CC BY 4.0 |
| `osl` | The Oracc Sign List behind `nabu signs` | CC0 |
| `pedecerto` | Latin metrical scansion ([Pedecerto](https://www.pedecerto.eu/), digital metrical analyses) | CC BY-NC-ND 4.0 |
| `pleiades` | The [Pleiades](https://pleiades.stoa.org/) ancient-world gazetteer behind `nabu place` and the findspot line | CC BY 3.0 |
| `trismegistos` | The [Trismegistos](https://www.trismegistos.org/) TexRelations concordance crosswalk resolving `tm:` reference edges across epigraphic corpora | CC BY-SA 4.0 |
| `trismegistos-geo` | The Trismegistos Geo gazetteer — 64,857 ancient-world places behind the `tm:` lane of the place desk | CC BY-SA 4.0 |
| `ucd` | The core of the [Unicode Character Database](https://www.unicode.org/ucd/) — character identity for every script the library holds | Unicode License V3 |
| `unikemet` | Unicode's Unikemet data file — the 5,067-hieroglyph Egyptian sign spine behind `nabu char` for Egyptian | Unicode License V3 |

## The local shelves

A further {{ census.local_shelves }} registered sources hold no upstream at all — they are the
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
through `nabu note`. The lemma shelf (`local-lemmas`) keeps the raw
output of the local lemmatization campaigns (`nabu lemma-enrich`) — hours
of computation that cannot be re-derived for free, projected from there
into the silver lemma tier. What these shelves hold is, by design, the owner's
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
the Referenzkorpus Mittelhochdeutsch teams at Bochum and Bonn; the
Text Creation Partnership and the Middle English Compendium at Michigan;
the Deutsches Textarchiv at the BBAW; Menota and Språkbanken Text; the
Instituut voor de Nederlandse Taal; the National Institute of Korean
History and the Institute for the Translation of Korean Classics; the
ERC DHARMA project; the National Diet Library and NDL Lab, the National
Institute of Japanese Literature, and the volunteer transcribers of
Minna de Honkoku and the Wikisource projects; the Invisible East
programme at Oxford, Prods Oktor Skjærvø, and the Beyond Boundaries
project; ATMO at Indiana and Lund; Monumenta Altaica; Ilya Yakubovich
and the Luwian corpus team; Michael Streck and Nathan Wasserman's SEAL;
the Bulgarian Academy of Sciences' Scripta Bulgarica; ZRC SAZU and
CLARIN.SI for the Slovenian prose corpora; the Ticha project at
Haverford College; the Royal Danish Library's Guaman Poma edition; the
nk2028 group's rime-book editions; and
Uppsala University's Samnordisk runtextdatabas — this library is *based
on the Scandinavian Runic-text Database*, as its Open Database License
asks to be said. Users of
this software are bound by, and should credit, these upstream projects
under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance the Rahlfs
Septuagint under CATSS conditions, and Brill's in-copyright dictionaries).
