---
name: nabu-indic
description: "Use when searching, reading or citing Sanskrit, Pali, Prakrit, Tamil and other Indic texts and inscriptions through the nabu MCP tools: GRETIL, SARIT, the DCS treebank, Monier-Williams, SuttaCentral, the DHARMA and South Indian inscription corpora. Covers stored scripts and transliterations, the Devanagari-to-IAST bridge and its limits, exact language tags in the lang filter, sandhi in DCS, stems versus nominatives in dictionary lookup, composition-era bands, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: indic
  origin: hand-tuned
  sources: "dacon dcs dharma-deccan dharma-mdt dharma-tamil gretil gu-wikisource kannada-texts madurai mw nabu-data prakrit-texts sarit shabados siddham sii-clean suttacentral tamilex ud"
---

# The Indologist — the `indic` desk

The Indologist — Veda to sastra, the Sanskrit library and its instruments.

The Sanskrit, Prakrit and Pali lane: GRETIL and SARIT, the DCS treebank, Monier-Williams, the Vedic UD treebank, and SuttaCentral's canon.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `dacon` | DACON — Diachronic Annotated Corpus of Newar (O'Neill & Meelen) | attribution |
| `dcs` | Digital Corpus of Sanskrit (DCS) — gold lemmatized CoNLL-U | attribution |
| `dharma-deccan` | DHARMA Task Force B — South Asian inscriptions (Deccan, Āndhra, Karnataka, Odisha, Bengal, Gujarat) | attribution |
| `dharma-mdt` | DHARMA text metadata (mdt-texts) — dating and typology rows for the DHARMA inscription corpora | attribution |
| `dharma-tamil` | DHARMA Tamil-country epigraphy (Task Force A) | attribution |
| `gretil` | GRETIL — Göttingen Register of Electronic Texts in Indian Languages (TEI corpus) | nc |
| `gu-wikisource` | Gujarati Wikisource — the bhakti cone (Narsinh Mehta · Mirabai · Dayaram · Akho · Premanand; Bruhat Kavyadohan) | attribution |
| `kannada-texts` | Kannada Digital Texts Project — Old and Middle Kannada classics in TEI (A. Ollett) | attribution |
| `madurai` | Project Madurai — classical Tamil e-texts | attribution |
| `mw` | Monier-Williams — A Sanskrit-English Dictionary (Cologne CDSL) | nc |
| `nabu-data` | nabu-data — Nabu's own published datasets, consumed back (form→lemma instrument) | attribution |
| `prakrit-texts` | Prakrit Digital Texts Project — Prakrit literature in TEI (A. Ollett) | attribution |
| `sarit` | SARIT — Search and Retrieval of Indic Texts (scholarly TEI editions) | attribution |
| `shabados` | Shabad OS — Gurbāṇī and Panthic texts (Gurmukhī primary text) | open |
| `siddham` | Siddham Epigraphic Archive — texts in EpiDoc (Gupta-age Sanskrit epigraphy) | attribution |
| `sii-clean` | South Indian Inscriptions — DHARMA editions and conversions | attribution |
| `suttacentral` | SuttaCentral — bilara-data segmented canon (Pali Tipiṭaka + Chinese Āgamas + aligned English) | open |
| `tamilex` | TAMILEX — critical editions of the classical Tamil corpus (Universität Hamburg) | nc |
| `ud` | Universal Dependencies — ancient treebanks | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `dacon` — DACON, the Diachronic Annotated Corpus of Newar, by Alexander O'Neill and Marieke Meelen (AHRC project "The Emergence of Egophoricity"; Zenodo, 2024). It holds four Classical Newar texts from the 12th to the 19th century, romanized in IAST: the Ukubāhāḥ inscription, the Gopālarājavaṃśāvalī chronicle, and the first 10,000 lines each of a Vetālapañcaviṃśati manuscript and the Maṇicūḍāvadāna. Together they make some 28,800 tokens with gold segmentation and part-of-speech tags, but no lemmas. Each text is dated by the deposit's own century attribution. CC BY 4.0; cite the deposit and the authors' companion article (CLAO 54.2, 2025).
- `dcs` — The Digital Corpus of Sanskrit — 15,900 chapters across 270 texts with human-verified sandhi splitting, lemmatization and morphology: the Sanskrit gold standard.
- `dharma-deccan` — The South Asian inscription estate of the ERC DHARMA project (EFEO), Task Force B: some 1,700 romanized editions from twenty repositories gathered into one shelf. It covers the Early Inscriptions of Āndhradeśa, Kanaganahalli, the Early Western Deccan, Andrew Ollett's Sātavāhana inscriptions, the Telugu corpus, the Kalyāṇa, Vengī and Bādāmi Cālukyas, the Maitrakas, Bengal charters and dedications, Dakṣiṇa Kosala, the Somavaṁśins and smaller dynastic corpora (Bhaumakara, Śailodbhava, Tuṅga and others). Languages are Prakrit, Sanskrit, Telugu and Kannada. Dates and findspots are taken where the files record them, chiefly in Ollett's data and the Vengī metadata table. Each file's own licence governs (CC BY-SA 4.0, CC BY 4.0 or CC BY 3.0); Ollett's unlicensed files fall back on his repository's CC BY 4.0.
- `dharma-mdt` — The per-inscription metadata tables of the ERC DHARMA project (EFEO/CNRS), one table per corpus: Dakṣiṇa Kosala, Pallava, Somavaṁśin and Telugu. They hold about 730 records and no texts. Each record gives the inscription's designation, typology, languages and scripts, lettering and line counts, its dating (CE date or range, with certainty and evidence, chiefly for the Telugu inscriptions), bibliography and a description of where the text sits on its object. Every record carries the identifier of the matching DHARMA edition, so it works as a dating and description sidecar to the inscription shelves. The metadata is released as CC0 row by row; the repository is CC BY 4.0.
- `dharma-tamil` — The Tamil-country inscriptions of the ERC DHARMA project (Task Force A; EFEO/CNRS/CEIAS): about 1,270 romanized editions from eleven corpora. The largest are the Pallava corpus (Sanskrit and Prakrit charters alongside Tamil) and the Tamil Nadu miscellany; the rest are selections from South Indian Inscriptions and the corpora of Tiruvāvaṭutuṟai, Cīrkāḻi, the Pāṇḍyas, Koṭumpāḷūr, Uttiramērūr, Mēlappaḻuvūr and Cempiyaṉ Mahādevī, plus Tamil inscriptions found outside Tamil Nadu, from Quanzhou to Réunion. Tamil dominates, with Sanskrit, a few Prakrit and Pali texts, Telugu lines in later grants and one French slab. The editors' dating statements are kept verbatim, and those given in the Śaka or Kollam eras are converted to CE. CC BY-SA 4.0 per the files' own licence; the few licence-less files fall back on the repository's CC BY 4.0.
- `gretil` — Rāmāyaṇa (18,761 verses), Mahābhārata-adjacent texts, Bhāgavata and other purāṇas, Kālidāsa and the kāvya tradition, Brahmasūtra with commentaries and sub-commentaries, dharmaśāstra, Nāṭyaśāstra, Dhvanyāloka with its commentary layers (kārikā vs. vṛtti separately citable as `:DhvK.…`/`:DhvA.…`), Buddhacarita, Gītagovinda, and — recovered by the silent-skip audit — the Mitākṣarā (the standard commentary on Yājñavalkya, 4,788 passages). Only 4 of 784 upstream files remain unparsed: flat verse lists with no numbering of any kind, genuinely unaddressable (and now loudly reported as `unrecognized` in every sync's discovery line).
- `gu-wikisource` — The Gujarati bhakti poets on Gujarati Wikisource: the medieval and early-modern devotional verse of Narsinh Mehta, Mirabai, Dayaram, Akho and Premanand, together with the pages of Ichchharam Suryaram Desai's Bruhat Kavyadohan anthology (Bombay, 1888–1913). About 207 poems are held in Gujarati script, each dated by the year of the scanned edition it was transcribed from. Pages taken from scans that state no edition year are left out, which keeps out much of the Mirabai material. Texts public domain; transcriptions CC BY-SA 4.0.
- `kannada-texts` — Andrew Ollett's Kannada Digital Texts Project, with text entry and correction by Krishnaprasada G. and Adishila Publications: 16 TEI editions in ISO-15919 romanization. It holds the Old Kannada campū classics, namely Pampa's Ādipurāṇaṁ and Vikramārjunavijayaṁ (941), Ponna's Śāntipurāṇaṁ (953), Ranna's Sāhasabhīmavijayaṁ and his lexicon, Nāgavarma II's Vardhamānapurāṇaṁ, Kāvyāvalōkanaṁ and the Sanskrit-sūtra grammar Karṇāṭakabhāṣābhūṣaṇaṁ (ca. 1042), and Janna's Anantanāthapurāṇaṁ. Beside them are the later poets Harihara, Rāghavāṅka, Kanakadāsa, Ratnākaravarṇi and Saṁciya Honnamma. Verse is cited stanza by stanza with its metre, and the six works the project dates carry those dates. CC BY-SA 4.0 per every file.
- `madurai` — Project Madurai (K. Kalyanasundaram and volunteers, since 1998), the open volunteer library of Tamil e-texts, in its classical-Tamil portion: about 755 works in Tamil script. It covers the Caṅkam anthologies, the didactic canon of the Patiṉeṇkīḻkkaṇakku, the Tēvāram, Tiruvācakam, Tirumantiram and the Nālāyira Tivyap Pirapantam, Śaiva Siddhānta, the epics and purāṇas, the minor prabandha genres, and grammars, poetics and lexicons. Selection follows the project's own genre labels, so a later poet writing in a classical form can ride in, while novels, essays, modern poetry and every translation stay out. Texts are read line by line as the e-texts are laid out; the works carry no dates. The project permits free distribution provided its header page is kept intact, and that header travels with every text.
- `mw` — Monier-Williams' Sanskrit-English Dictionary — 193,890 entries with citation sigla into the classical corpus.
- `nabu-data` — The datasets this library publishes back to the world (github.com/arvicco/nabu-data), registered as an ordinary source: a Sanskrit form-to-lemma table of 428,825 rows derived from the Digital Corpus of Sanskrit's gold annotations, plus Tibetan Wylie-folding and verb-lemma tables — each packaged with machine-readable metadata and its full upstream attribution chain. CC BY 4.0.
- `prakrit-texts` — Andrew Ollett's Prakrit Digital Texts Project: TEI editions of Prakrit literature in ISO-15919 romanization, about 22 works. Among them are Hāla's Sattasaī, Vākpatirāja's Gaüḍavaho with its Sanskrit chāyā, Kautūhala's Līlāvaī, Jayavallabha's Vajjālagga, Vimala's Paümacariya, and Haribhadra's Samarāiccakahā and Dhuttakkhāṇa. The lexica (Dēśīnāmamālā, Pāiyalacchī), Vararuci's Prākṛtaprakāśa with and without Bhāmaha, the Prākṛtapaiṅgala, the gāhā anthologies and the Āgamas Nandī and Aṇuōgaddārāiṁ are included too. Most are Prakrit, with Sanskrit grammars and commentary and two Ardhamāgadhī Āgamas. Only the files that carry the project's CC BY-SA 4.0 grant are held, so nine Śvētāmbara Āgama files without one are left out, and the Sētubandha is read from its SARIT edition instead.
- `sarit` — Scholarly TEI editions of Sanskrit śāstra — 83 texts including a complete Mahābhārata (Southern Recension), in Devanagari and IAST.
- `shabados` — The Gurmukhī scripture text of the Shabad OS database, the volunteer-proofread digital Gurbāṇī with a public correction log (Shabad OS Organization and contributors). It holds some 141,000 lines in 127 sections. The sources are the Sri Guru Granth Sahib (the bāṇī of the Gurus and the bhagats from Sheikh Farīd on, by raag), the Sri Dasam Granth, the Vārāṅ and Kabitt Savayye of Bhāī Gurdās, Bhāī Nand Lāl's four Persian works in Gurmukhī transliteration, selections from the Sarabloh Granth, and the Ardās. Each line is cited by its database id with its page (ang), line group and author, and second printed readings of the Dasam Granth are kept as variants. Language is declared coarsely as Punjabi, Braj or Persian per work, all in Gurmukhī script. Only the scripture is taken: the database marks the Gurbāṇī and Panthic texts public domain (PDM 1.0), while its modern translations and notes carry no such grant and are left out.
- `siddham` — The texts of the Siddham Epigraphic Archive: Dániel Balogh's EpiDoc editions of early historic Indian epigraphy, archived on Zenodo in 2019 as "the complete collection of siddham editions prepared offline". It holds 427 editions of Sanskrit inscriptions, romanized, from the Gupta, Vākāṭaka, Aulikara, Parivrājaka and Uccakalpa and neighbouring corpora: praśastis, copper-plate charters, pillar and cave inscriptions, seal legends and graffiti. They are read at the inscription's physical line, with stanza, metre, plate and face noted. The deposit carries no translations or findspots. Dates come only from the English titles: nine Gupta-era years are converted to CE, a few century attributions are kept, and untyped regnal years are left as written. CC BY-SA 4.0 per the Zenodo record.
- `sii-clean` — The Archaeological Survey of India's printed South Indian Inscriptions (vols. 1–42), re-keyed as EpiDoc by the ERC DHARMA project and shown on dharmalekha.info. Only the editions that carry their own CC BY-SA 4.0 grant are held: about 590 inscriptions from SII volumes 2, 3, 4, 8, 17, 22, 26 and 41, nearly all romanized Tamil, with a few Sanskrit, Telugu and Kannada. The SII editors' printed headings are mined for each inscription's village, taluk and district, its Annual Report number, and its date where the editor gave a CE conversion or a Śaka year. A few inscriptions also appear on the DHARMA Tamil shelf in DHARMA's own re-edition, and both editions are kept. The repository itself carries no licence, so the thousands of files still without an in-file grant are left out.
- `suttacentral` — The Pali Tipiṭaka from SuttaCentral — the Buddhist canon in roman-script Pali (Mahāsaṅgīti edition) plus the Patna Dhammapada, with segment-aligned English translations riding the same citation ids.
- `tamilex` — TAMILEX (Universität Hamburg; Eva Wilden and Jean-Luc Chevillard, an Academies' Programme project): critical TEI editions of the classical Tamil corpus, one repository per work, about 7,800 files. It covers the Caṅkam anthologies (Kuṟuntokai, Naṟṟiṇai, Aiṅkuṟunūṟu, Puṟanāṉūṟu, Akanāṉūṟu, Kalittokai, Patiṟṟuppattu, Paripāṭal, Pattuppāṭṭu), the Tirukkuṟaḷ with its commentaries, the epics Cilappatikāram, Maṇimēkalai and Peruṅkatai, the grammars and poetics from the Tolkāppiyam to the Naṉṉūl, the Tivākaram lexicon, and the devotional canons (the Nālāyirat Tivviyap Pirapantam and the Eleventh Tirumuṟai). The texts are in ISO-15919 romanized Tamil with parallel English, commentaries as their own layers, witness lists and variant apparatus. A gold word-by-word analysis (segmentation, gloss, grammatical role) exists nowhere else for Old Tamil. CC BY-NC-SA 4.0, as stated by the TAMILEX maintainers by email (2026).
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *dharma across the Sanskrit corpus, by lemma.* — `nabu_search (lemma: dharma, lang: san)`: DCS hits with inflected surface forms (dharmeṇa, dharmaś) and the lexicon gloss beside each — upaniṣads first, ranked by relevance.

## Field semantics on this desk

- **Scripts as stored.** `gretil` is IAST (tagged `san-Latn`, Vedic accents kept
  as combining marks); `sarit` is partly Devanagari (`san-Deva`), partly IAST;
  `dcs` is IAST; `mw` (Monier-Williams) is converted from SLP1 to IAST at ingest.
  SuttaCentral's Pali is romanized (`pli`, with ṁ). The DHARMA and South Indian
  inscription corpora hold ISO 15919 transliteration (`tam-Latn` and similar);
  Project Madurai holds Tamil script.
- **Devanagari and IAST meet only for Sanskrit.** For `san`, Devanagari is
  transcoded to IAST before folding, on both the index and the query side, so a
  Devanagari query reaches IAST texts and vice versa. Diacritics then fold away
  (`kṛṣṇa` → `krsna`), at the accepted price of merging distinct letters. There is
  no Velthuis, Harvard-Kyoto or SLP1 query input, and no bridge between Tamil
  script and its transliteration: Madurai and the Tamil inscription corpora do
  not cross-match.
- **The `lang` filter matches stored tags.** It expands only two-letter and
  bibliographic aliases, not script subtags: `san` reaches the sources stored as
  plain `san` (DCS, Monier-Williams, the Vedic treebank) but not `san-Latn` or
  `san-Deva`. Read the language list in `nabu_status` and pass the exact tag, or
  search without `lang` and read each hit's `language`.
- **DCS is sandhied text with gold lemmas.** The passage text is the sandhied
  sentence; unsandhied forms ride token annotations; lemmas are gold only where
  upstream marks the chapter's lexicon layer verified. A text search must match
  the sandhied surface; a `lemma` search escapes sandhi.
- **Stems versus nominatives.** Monier-Williams and DCS cite stems; the
  Mahāvyutpatti cites nominatives (`bodhisattvaḥ`). `nabu_define` tries both and
  keeps what exists.
- **DCS dates are composition-era bands.** DCS's time slots map to five
  deliberately overlapping bands (from c. 1300 BCE to 1900 CE), class
  `composition`, precision `era`. They date the work's attributed period, not a
  manuscript — and the overlap is real uncertainty, not error.

## Conflation traps

- The Vedic UD treebank and DCS share material at different grains and are not
  deduplicated. GRETIL and SARIT can hold different editions or recensions of the
  same work (SARIT's Mahābhārata is the Southern Recension); counts across them
  are counts across editions.
- SuttaCentral's Pali canon is a root text with translations as sibling
  documents; Chinese Āgama parallels and the Tibetan canon live on other desks
  (`nabu-buddhist`, `nabu-tibetan`), joined by curated parallel links that
  `nabu_links` reads.
- Inscriptions (DHARMA, Siddham, the South Indian Inscriptions) follow the
  epigraphy rules: the text is an edited reading.

## Licensing on this desk

GRETIL, Monier-Williams and TAMILEX are `nc`; SARIT, DCS, Siddham, the DHARMA
corpora and most of the Indic-language shelves are `attribution`; SuttaCentral's
root texts, the Mahāvyutpatti and the Shabad OS database are `open`.

## House cautions

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
