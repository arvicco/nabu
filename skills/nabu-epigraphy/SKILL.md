---
name: nabu-epigraphy
description: "Use when searching, reading or citing inscriptions, papyri, ostraca and tablets at the artifact grain through the nabu MCP tools: EDH, EDR, the DDbDP papyri with HGV dates, I.Sicily, IIP, the Celtic, Italic and Etruscan editions, Rundata, DAMOS, the DHARMA corpora and the place instruments (nabu_place, Pleiades, Trismegistos). Covers what the Leiden-encoded text does and does not show, restored letters in search hits, date envelopes, the three kinds of place claim, kind facets, duplicate witnesses across databases, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: epigraphy
  origin: hand-tuned
  sources: "ceipom damos dharma-campa dharma-deccan dharma-khmer dharma-nusantara dharma-pyu dharma-tamil edh edr elephantine ig-cyprus iip isicily itant lexlep lexlep-words nabu-places obi-burmese ociana ogham open-etruscan papyri-ddbdp pleiades riig rundata siddham sii-clean tir tlhdig trismegistos trismegistos-geo ucd"
---

# The Papyrologist-Epigraphist — the `epigraphy` desk

The Papyrologist-Epigraphist — reads what survives on stone, sherd, papyrus and tablet, lacunae and all.

Documentary corpora at the artifact grain: papyri, the Latin/Greek and Levantine and Sicilian inscription databases, the Continental Celtic, Italic and Tyrsenian editions, ogham stones, Hittite tablets — the shelves where fragment search and findspots earn their keep.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `ceipom` | CEIPoM — Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium BCE (Pitts, KU Leuven; Zenodo v1.3) | attribution |
| `damos` | DĀMOS — Database of Mycenaean at Oslo (the Linear B corpus) | nc |
| `dharma-campa` | DHARMA Campā inscriptions (Old Cham epigraphy) | attribution |
| `dharma-deccan` | DHARMA Task Force B — South Asian inscriptions (Deccan, Āndhra, Karnataka, Odisha, Bengal, Gujarat) | attribution |
| `dharma-khmer` | DHARMA Corpus des inscriptions khmères (Old Khmer epigraphy) | attribution |
| `dharma-nusantara` | DHARMA Nusantara epigraphy (Old Javanese/Malay/Sundanese charters) | attribution |
| `dharma-pyu` | DHARMA Corpus of Pyu Inscriptions | attribution |
| `dharma-tamil` | DHARMA Tamil-country epigraphy (Task Force A) | attribution |
| `edh` | EDH — Epigraphic Database Heidelberg | attribution |
| `edr` | EDR — Epigraphic Database Roma (EpiDoc data release) | attribution |
| `elephantine` | Elephantine — the Berlin ERC papyri and ostraca database | attribution |
| `ig-cyprus` | IG XV 1,1 — Inscriptiones Cypri syllabicae (BBAW Inscriptiones Graecae digital edition) | attribution |
| `iip` | Inscriptions of Israel/Palestine (Brown University) | nc |
| `isicily` | I.Sicily — the inscriptions of ancient Sicily (Prag, Oxford / ERC Crossreads) | attribution |
| `itant` | Corpus ItAnt — Languages and Cultures of Ancient Italy (PRIN 2017, CNR-ILC/UniFI) | nc |
| `lexlep` | Lexicon Leponticum (LexLep) — Cisalpine Celtic inscriptions (Univ. Vienna) | nc |
| `lexlep-words` | Lexicon Leponticum — Dictionary of Attested Forms (Univ. Vienna) | nc |
| `nabu-places` | nabu-places — the place-matching decisions registry | attribution |
| `obi-burmese` | OBI — Structured Corpus of Old Burmese Stone Inscriptions | attribution |
| `ociana` | OCIANA — Online Corpus of the Inscriptions of Ancient North Arabia | research_private |
| `ogham` | OG(H)AM — Ogham in 3D v2.0 (DIAS / Maynooth) | nc |
| `open-etruscan` | OpenEtruscan — Etruscan Machine Learning Corpus (Zenodo 20075836) | attribution |
| `papyri-ddbdp` | Papyri.info — Duke Databank of Documentary Papyri + Digital Corpus of Literary Papyri | attribution |
| `pleiades` | Pleiades — ancient-world gazetteer (place resolver instrument) | attribution |
| `riig` | RIIG — Recueil informatisé des inscriptions gauloises (Ausonius/ANR) | attribution |
| `rundata` | Rundata — Scandinavian Runic-text Database (SRDB, via rundata.info) | odbl |
| `siddham` | Siddham Epigraphic Archive — texts in EpiDoc (Gupta-age Sanskrit epigraphy) | attribution |
| `sii-clean` | South Indian Inscriptions — DHARMA editions and conversions | attribution |
| `tir` | Thesaurus Inscriptionum Raeticarum (TIR) — Raetic corpus of record (Univ. Vienna) | nc |
| `tlhdig` | TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Beta 0.3, Zenodo 20328284) | attribution |
| `trismegistos` | Trismegistos TexRelations — the cross-project concordance crosswalk (links instrument) | attribution |
| `trismegistos-geo` | Trismegistos Geo — places database (gazetteer instrument) | attribution |
| `ucd` | UCD — Unicode Character Database core (universal character-identity instrument) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `ceipom` — The Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium BCE (CEIPoM), by Reuben Pitts (KU Leuven) — 3,875 pre-Roman Italic inscriptions in 5,303 sentences with 37,041 dependency-annotated tokens: Latin (including Faliscan), Oscan, Messapic, Venetic, Umbrian — the Iguvine Tables complete — Old Sabellic and a handful of Greek texts, the Fibula Praenestina and the Duenos inscription among them, with per-text scripts, dates, findspot coordinates and 3,630 Trismegistos ids. A single scholar's dissertation corpus: lemmas, dependencies and Classical Latin equivalences are the editor's own curation. CC BY-SA 4.0, published on Zenodo (doi:10.5281/zenodo.6475427).
- `damos` — The complete corpus of Linear B, the syllabic script in which the palace scribes of Late Bronze Age Crete and mainland Greece (about the 14th to the 13th century BCE) wrote Mycenaean Greek, the oldest attested form of Greek — as edited in DĀMOS, the Database of Mycenaean at Oslo (University of Oslo). Some six thousand documents: the clay tablets of the Knossos and Pylos archives above all, with Thebes, Mycenae, Tiryns, Khania and the smaller sites, the sealings and labels, and the inscribed stirrup jars that carried oil and wine across the Aegean. The texts are the palaces' bookkeeping — rosters of men and women, livestock and wool, land holdings, chariots and armour, offerings of gold vessels to Poseidon and Potnia — given in the standard transliteration line by line, syllabograms romanized, logograms such as VIR (man) or MUL (woman) as Latin abbreviations, damaged signs under-dotted and lacunae marked as the edition marks them. Each document carries its series and scribal hand, findspot, ceramic-phase dating, museum and inventory number and bibliography. CC BY-NC-SA 4.0.
- `dharma-campa` — The corpus of the inscriptions of Campā from the ERC DHARMA project (EFEO): about 120 editions of Old Cham and Sanskrit epigraphy from the Cham polities of coastal Vietnam, absorbing and superseding the earlier ISAW–EFEO corpus. Its Old Cham inscription from Đông Yên Châu is the oldest attested Austronesian text anywhere. The editions are romanized TEI, read line by line for prose and verse by verse for Sanskrit. Each file's own licence governs, recorded verbatim: CC BY-SA 4.0 (CC BY 4.0 on some).
- `dharma-deccan` — The South Asian inscription estate of the ERC DHARMA project (EFEO), Task Force B: some 1,700 romanized editions from twenty repositories gathered into one shelf. It covers the Early Inscriptions of Āndhradeśa, Kanaganahalli, the Early Western Deccan, Andrew Ollett's Sātavāhana inscriptions, the Telugu corpus, the Kalyāṇa, Vengī and Bādāmi Cālukyas, the Maitrakas, Bengal charters and dedications, Dakṣiṇa Kosala, the Somavaṁśins and smaller dynastic corpora (Bhaumakara, Śailodbhava, Tuṅga and others). Languages are Prakrit, Sanskrit, Telugu and Kannada. Dates and findspots are taken where the files record them, chiefly in Ollett's data and the Vengī metadata table. Each file's own licence governs (CC BY-SA 4.0, CC BY 4.0 or CC BY 3.0); Ollett's unlicensed files fall back on his repository's CC BY 4.0.
- `dharma-khmer` — The Corpus des inscriptions khmères of the ERC DHARMA project (EFEO): George Cœdès's K-numbered corpus digitized, about 1,200 editions of pre-Angkorian and Angkorian epigraphy. It is Old Khmer prose and Sanskrit verse, romanized, with a few Middle Khmer, Pali and Prakrit pieces, and it is the largest single corpus of Southeast Asian inscriptions. Prose is read at the inscription's physical line and verse at the edition's own stanza and line; bilingual inscriptions keep each passage's own language. It is a working corpus, and each edition's maturity is recorded. CC BY-SA 4.0 per the files' own licence.
- `dharma-nusantara` — The Nusantara epigraphy corpus of the ERC DHARMA project (EFEO): about 300 editions of inscriptions from the Indonesian archipelago and beyond. It includes Old Javanese sīma charters (Sangguran, Mantyasih), the Borobudur inscriptions, Old Sundanese (Kawali, Batutulis), Old Malay (Sojomerto, and the Laguna copperplate, the oldest document of the Philippines) and Sanskrit. It holds the library's whole Old Malay record. Editions are romanized and read at the stone's physical line, words broken across faces kept whole. CC BY-SA 4.0 per the files' own licence.
- `dharma-pyu` — The Corpus of Pyu Inscriptions (Arlo Griffiths et al., ERC DHARMA project): about 160 romanized editions in Pyu, the extinct Sino-Tibetan language of the city-states of the Irrawaddy valley (roughly 5th–13th century CE). Alongside the Pyu are short Pali, Sanskrit, Old Burmese and Prakrit passages, and a run of Old Mon lines that forms the first digital Old Mon text anywhere. Each file's own CC BY-SA 4.0 licence is the whole grant.
- `dharma-tamil` — The Tamil-country inscriptions of the ERC DHARMA project (Task Force A; EFEO/CNRS/CEIAS): about 1,270 romanized editions from eleven corpora. The largest are the Pallava corpus (Sanskrit and Prakrit charters alongside Tamil) and the Tamil Nadu miscellany; the rest are selections from South Indian Inscriptions and the corpora of Tiruvāvaṭutuṟai, Cīrkāḻi, the Pāṇḍyas, Koṭumpāḷūr, Uttiramērūr, Mēlappaḻuvūr and Cempiyaṉ Mahādevī, plus Tamil inscriptions found outside Tamil Nadu, from Quanzhou to Réunion. Tamil dominates, with Sanskrit, a few Prakrit and Pali texts, Telugu lines in later grants and one French slab. The editors' dating statements are kept verbatim, and those given in the Śaka or Kollam eras are converted to CE. CC BY-SA 4.0 per the files' own licence; the few licence-less files fall back on the repository's CC BY 4.0.
- `edh` — Latin and bilingual inscriptions of the Roman provinces — the Epigraphic Database Heidelberg: 81,856 inscriptions with dating, findspot, province, material and object-type apparatus.
- `edr` — The Epigraphic Database Roma (Sapienza; Panciera, Orlandi et al.): the inscriptions of ancient Italy, the geographic complement to the Heidelberg database's coverage of the Roman provinces — 115,591 records in EpiDoc TEI, about 110,000 Latin and 5,600 Greek, with findspot and repository data, Julian dating, and EAGLE-vocabulary classification of genre, region, material, and object type. CC BY 4.0.
- `elephantine` — The Berlin database of papyri and ostraca from Elephantine (Ägyptisches Museum und Papyrussammlung, ERC project "Localizing 4000 Years of Cultural History", Verena Lepper): 10,744 objects documenting four millennia of life on the island — Greek, Imperial Aramaic, Demotic, Coptic, hieratic, Middle Egyptian, Arabic, and Phoenician among the languages, the Aramaic written in unpointed Hebrew script — in TEI editions with English translations, structured dating, and Trismegistos links. CC BY-SA 3.0 under each record's own grant.
- `ig-cyprus` — The Cypriot syllabary fascicle of Inscriptiones Graecae (IG XV 1,1, ed. Artemis Karnava and Massimo Perna with Markus Egetmeyer, Berlin 2020): 593 inscriptions from ancient Cyprus — Amathus, Kurion and Marion — written in the Cypriot syllabic script between the archaic period and the end of the fourth century BCE. Most records are Greek in its Arcadocypriot dialect (dedications, funerary texts, coin legends of the city kingdoms); eighteen are Eteocypriot, the island's only partly interpreted pre-Greek language, including the Amathus Greek–Eteocypriot bilingual. Each record carries the edition's reading text in transliteration, an alphabetic-Greek transcription where the editors give one, and Hallof's German translation where present, with find place, date and object descriptions. Published by the Berlin-Brandenburg Academy's digital Inscriptiones Graecae under CC BY 4.0, each record asking a link back to its edition page.
- `iip` — Inscriptions of Israel/Palestine (Michael Satlow, Brown University): 5,535 EpiDoc records of the multilingual epigraphy of the southern Levant, roughly 500 BCE–640 CE — ossuaries, ostraca, mosaics, and epitaphs (Beth She'arim, Masada, Zoora) in Greek, Jewish Aramaic, Hebrew, and Latin with smaller Phoenician, Syriac, Armenian, and Georgian slices, spanning Jewish, Christian, and pagan religious contexts, with dating and findspots throughout. CC BY-NC 4.0.
- `isicily` — I.Sicily (Jonathon Prag, Oxford / ERC Crossreads): 5,120 EpiDoc records covering the inscriptions of ancient Sicily in all its languages — Greek and Latin foremost, plus the island's fragmentary Elymian, Sicel, Sicilian Punic, and Oscan material, for which this corpus is the only machine-readable home — with dating, coordinates, and concordances to the major epigraphic databases, and English and Italian translations for part of the corpus. CC BY 4.0.
- `itant` — Corpus ItAnt — Languages and Cultures of Ancient Italy (CNR-ILC and the University of Florence): EpiDoc editions of 501 Oscan and 9 Lepontic inscriptions, word-tokenized with onomastic tagging, interpuncts, and ligature and writing-direction markup; diplomatic renderings accompany the Lepontic texts, Italian and English translations cover much of the corpus, and every record carries dating, findspot, and a Trismegistos concordance. CC BY-NC-SA 4.0.
- `lexlep` — The Lexicon Leponticum (lexlep.univie.ac.at, University of Vienna; ed. Stifter, Salomon, Braun et al.) — the digital edition of Cisalpine Celtic epigraphy: 494 inscriptions in Lepontic and Cisalpine Gaulish, given in scholarly transliteration and joined to catalogs of the inscribed objects (typology, material, dating) and find sites (coordinates), with concordances to the Morandi and Solinas print editions. Made available for scientific use under noncommercial Creative Commons terms.
- `lexlep-words` — The dictionary of attested forms from the Lexicon Leponticum (University of Vienna; ed. Stifter, Salomon, Braun et al.) — a 628-word etymological lexicon of Lepontic and Cisalpine Gaulish, with grammatical analysis, morphemic breakdown, and etymological commentary per entry. Made available for scientific use under noncommercial Creative Commons terms.
- `nabu-places` — The library's own place-matching decisions registry — a sister project recording which gazetteer identity each source's verbatim place-name string denotes ("Girsu (mod. Tello)" is Pleiades 912855 and CIGS GIR; EDR's "Mediolanum" is the Insubrian Milan, not one of its five homonyms), with unlocatable, region and ghost as first-class answers and an unlisted name honestly unmatched. Beyond matching, it can mint its own evidence-backed place records where text-analysis scholarship establishes a place no gazetteer registers. Nabu projects the matched decisions into the catalog's place axis, so hundreds of thousands of named-but-unlinked documents become place-queryable. Plain YAML with a dependency-free validator; CC BY 4.0.
- `obi-burmese` — OBI, A Structured Corpus of Old Burmese Stone Inscriptions (Zenodo), compiled from the Archaeological Directorate's Ancient Burmese Inscriptions, Thein Tun's recently found inscriptions and the Bagan Epigraphic Database. It holds about 1,120 files, one per face and page, of Bagan-period inscriptions in Old Burmese from the Myazedi era on. Each line gives the Myanmar-script text with its transliteration beside it. CC BY 4.0.
- `ociana` — OCIANA, the Online Corpus of the Inscriptions of Ancient North Arabia (Khalili Research Centre, University of Oxford): the inscriptions the pre-Islamic peoples of northern Arabia and the Syro-Jordanian desert carved on rocks, in the Safaitic, Hismaic, Dadanitic and Taymanitic scripts and their smaller relatives (Hasaitic, Dumaitic, the Thamudic families), with a handful of Greek, Latin, Minaic and Nabataean texts found among them. Most are short graffiti left by nomads and oasis dwellers, signatures and genealogies ("By N son of N") that grow into prayers to their deities, laments for the dead and notes on camping, herding and raiding. About 37,000 texts are held, each read in its scholarly transliteration with the English translation, readings of earlier editors, commentary, references and the find site, usually with coordinates. From the University of Oxford's archive deposit (2017), held for private study and research under the archive's terms of use, never redistributed.
- `ogham` — Every known ogham inscription up to the mid-19th century — the ~500 stones of the OG(H)AM digital corpus in real Ogham codepoints with transliteration layers.
- `open-etruscan` — OpenEtruscan — the Etruscan Machine Learning Corpus (OpenEtruscan Project / Edoardo Panichi): 6,567 Etruscan inscriptions, the only bulk machine-readable Etruscan corpus, drawing on the Larth corpus (Vico & Spanakis 2023) and extractions from CIE Vol. I. Each inscription carries the carved glyph stream and a scholarly transliteration, with English translations for 1,800 and date ranges for 307. CC BY 4.0.
- `papyri-ddbdp` — The everyday written record of a millennium of Egypt: what people bought, owed, sued over, and wrote home about. This is *documentary*, not literary — the language is non-standard, formulaic in places, full of phonetic spellings, and therefore a unique witness to living Greek (and the Coptic and Arabic transitions).
- `pleiades` — Pleiades (pleiades.stoa.org) — the community-built gazetteer of the ancient world, successor to the Barrington Atlas: some 42,000 ancient places, each with its title, representative coordinates, place types, and attested time periods. A reference instrument for locating and identifying the places named in ancient sources. CC BY 3.0.
- `riig` — The Gaulish corpus of record — 428 inscriptions from the Recueil informatisé des inscriptions gauloises, Gallo-Greek and Gallo-Latin, with datings, findspots and French apparatus.
- `rundata` — Rundata — the Scandinavian Runic-text Database (Samnordisk runtextdatabas, Uppsala): about 6,800 runic inscriptions from Sweden, Denmark, Norway, and the wider Norse diaspora, Proto-Norse through the medieval period. Each inscription offers up to five text lanes — the scholarly Latin transliteration, Old West Norse and runic Swedish normalizations, and English and Swedish translations — alongside dating, find-spot coordinates, carver, material, and bibliography. ODbL 1.0 with the Database Contents License; based on the Scandinavian Runic-text Database.
- `siddham` — The texts of the Siddham Epigraphic Archive: Dániel Balogh's EpiDoc editions of early historic Indian epigraphy, archived on Zenodo in 2019 as "the complete collection of siddham editions prepared offline". It holds 427 editions of Sanskrit inscriptions, romanized, from the Gupta, Vākāṭaka, Aulikara, Parivrājaka and Uccakalpa and neighbouring corpora: praśastis, copper-plate charters, pillar and cave inscriptions, seal legends and graffiti. They are read at the inscription's physical line, with stanza, metre, plate and face noted. The deposit carries no translations or findspots. Dates come only from the English titles: nine Gupta-era years are converted to CE, a few century attributions are kept, and untyped regnal years are left as written. CC BY-SA 4.0 per the Zenodo record.
- `sii-clean` — The Archaeological Survey of India's printed South Indian Inscriptions (vols. 1–42), re-keyed as EpiDoc by the ERC DHARMA project and shown on dharmalekha.info. Only the editions that carry their own CC BY-SA 4.0 grant are held: about 590 inscriptions from SII volumes 2, 3, 4, 8, 17, 22, 26 and 41, nearly all romanized Tamil, with a few Sanskrit, Telugu and Kannada. The SII editors' printed headings are mined for each inscription's village, taluk and district, its Annual Report number, and its date where the editor gave a CE conversion or a Śaka year. A few inscriptions also appear on the DHARMA Tamil shelf in DHARMA's own re-edition, and both editions are kept. The repository itself carries no licence, so the thousands of files still without an in-file grant are left out.
- `tir` — The Thesaurus Inscriptionum Raeticarum (University of Vienna; ed. Schumacher, Salomon, Kluge, Bajc, Braun) — the corpus of record for Raetic, a Tyrsenian language attested in Iron Age northern Italy and western Austria: 389 inscriptions, from rock-wall petrographs to votives in the Sanzeno and Magrè alphabets, with linked object and site records, in an actively edited online edition; many short inscriptions remain of honestly undetermined language. CC BY-SA 3.0 / GFDL, licensed for scientific use.
- `tlhdig` — TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Hethitologie-Portal Mainz): the Hittite corpus, covering more than 98% of published cuneiform fragments from the Hittite tablet collections in transliteration — 23,937 per-manuscript documents organized by CTH number, with line-grain transliteration, Unicode cuneiform, and candidate morphological analyses. Predominantly Hittite, with Akkadian, Hurrian, Hattic, Luwian, Sumerian, and Palaic passages. CC BY 4.0.
- `trismegistos` — The Trismegistos TexRelations concordance (trismegistos.org) — the cross-project crosswalk of the papyrological and epigraphic world: for each Trismegistos text number, the matching identifiers in more than 80 partner databases (EDH, EDCS, EDR, I.Sicily, DDbDP, HGV, PHI, and others), making one stone or papyrus recognizable across projects. CC BY-SA 4.0.
- `trismegistos-geo` — The places database of Trismegistos, the papyrological metadata platform grown at KU Leuven out of Greco-Roman Egypt and now spanning the wider ancient world — 64,857 places with the field's finest grain for Egypt (nomes, villages, topoi), each carrying TM's standard name plus Latin, Greek, Demotic and Coptic name forms, status vocabulary (city, village, topos…), Roman provincia and Egyptian nomos codes, and coordinates where established. Attested-but-unidentified "ghost names" are kept as their own honest category. The dump is acquired by a human in a browser (the service sits behind a security check) and ingested with full provenance; Nabu derives it into the place index as the tm namespace. CC BY-SA 4.0, per the project's data-services grant.
- `ucd` — The Unicode Character Database (version 17.0), the universal record of character identity: the name, general category, numeric value, canonical decomposition, bidi class and case mappings of every assigned code point, some 40,500 data lines. Around them sit the blocks, scripts, name aliases, Unicode versions of introduction, Hangul jamo, radicals, the Tangut and Nüshu sources, the annotated names list, and the visual-confusables table from the Unicode security data. It holds no texts. It serves as the identity layer behind the character lookups for every script in the library. Unicode License v3 (MIT-style).

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *What survives from Segesta, across every corpus here?* — `nabu_place Segesta`: The gazetteer card (Segesta/Egesta, Pleiades 462487 — settlement, archaic to late-antique, 37.94, 12.84) plus per-source holdings of documents carrying that upstream-asserted Pleiades id, and a labelled tail of findspot text-mentions not yet id-linked.
- *Wage receipts from Oxyrhynchus?* — `nabu_search μισθός (place: oxyrhynch%)`: Documentary papyri hits with provenance-filtered dating — the DDbDP at the artifact grain, lacunae preserved.

## Field semantics on this desk

- **The passage text is the editor's reading, not a diplomatic transcript.** For
  the EpiDoc corpora (`edh`, `edr`, `papyri-ddbdp`, `isicily`, `iip` and the
  Celtic/Italic editions) the text is what a print edition's main text would
  read: abbreviations expanded (`v(otum)` stored as `votum`), regularized and
  corrected readings preferred, and **restored (`supplied`) and uncertain
  letters included without brackets**. A search hit can therefore rest entirely
  on modern restoration. The counts of supplied and unclear letters ride the
  passage annotations (`leiden.supplied_chars`, `leiden.unclear_chars`) — check
  them before treating a reading as preserved on the stone or papyrus.
- **Lacunae and deletions are marked.** Every gap becomes a single `[…]`
  whatever its length (its extent rides annotations), so a phrase search never
  matches across a lacuna. Ancient deletions are kept inside `⟦…⟧`, surplus
  letters inside `{…}`.
- **Exceptions to the rule.** `iip` stores its transcription layer and falls
  back to the diplomatic layer for a minority of records, flagged
  `text_layer: diplomatic`. Inscriptions with no letters (or lost lines) are
  metadata-only documents (`text_layer: none`) or a single `:text` passage.
  Several small corpora (`rundata`, `damos`, `open-etruscan`, `ig-cyprus`, the
  DHARMA corpora, `sii-clean`) hold Latin-script transliteration, not the
  original script.
- **Dates are artifact dates with their envelope.** EDH and EDR give the
  editors' `not_before`/`not_after` bounds; papyri take theirs from the HGV
  metadata joined to the DDbDP text (several HGV date entries merged into one
  envelope, HGV's own precision kept). Years are signed, no year 0. A range is
  an uncertainty envelope, never a point: do not report a midpoint as the date.
  `from`/`to`/`century` filter by interval overlap at document grain; undated
  documents silently fall out of a date-filtered search.
- **Kind and facets.** The `kind` filter folds upstream type labels onto the
  house tree (an EDH `epitaph` and an EDR `sepulcralis` both reach
  `funerary/epitaph`; upstream "unknown" or "cetera" reach `unknown`, a claim,
  not a gap). The raw upstream label rides `kind[].raw` in `nabu_show`. Material,
  object type, province and region are document facets visible in `nabu_show`
  but not filterable through the MCP search.

## Places — three different claims

- `nabu_place` reports **holdings** (documents whose own upstream record asserts
  that Pleiades id — EDH, I.Sicily, IIP, ItAnt), **axis holdings** (documents
  joined through the `place_ref` axis: adapter-asserted refs plus the place
  registry's reviewed name decisions) and an **unlinked** tail (documents whose
  findspot *text* contains the name). Keep the three apart; EDR, for instance,
  appears through registry decisions rather than its own ids.
- Place titles match exactly (case-insensitive): `Segesta` works, `Seges` does
  not. Namespaced refs (`pleiades:…`, `tm:…`) are independent identity claims;
  an equivalence between namespaces exists only where the crosswalk data says so.
- A place *mentioned in* a text is not the place the object was *found at*;
  only findspots and provenance enter the place axis. HGV region-level places
  and letter-sender places are labeled separately from findspots.
- The `script` filter matches the held text's script or the original artifact's
  script where that lane exists (Demotic papyri, Old Italic); for corpora held
  only in transliteration with no artifact-script row, a script filter on the
  original script will miss them.

## Conflation traps

- **EDH and EDR are separate witnesses.** EDH covers the Roman provinces, EDR
  Italy; inscriptions on the border appear in both under two urns and are never
  deduplicated. Count once per monument, by reference number, and say which
  database you read.
- **DDbDP text, HGV metadata.** Papyrus text comes from the DDbDP; its date,
  place and kind come from the HGV record. A dating question is a question
  about HGV's judgment, not the text's.
- **Trismegistos is an instrument, not a text.** TM numbers group "same text"
  records across corpora where the crosswalk resolves; no TM link means
  unresolved, not unique.
- **Persons are attestations.** EDH person rows are one attestation each, never
  merged into individuals across inscriptions; there is no MCP person tool.
- **The fuzzy fragment index is CLI-only.** Bracket-tolerant fragment search
  over EDH, EDR, the papyri, Elephantine, ORACC and the Etruscan corpus exists
  on the command line, not through `nabu_search`.

## Licensing on this desk

Most corpora are `attribution` (CC BY / CC BY-SA). `iip`, `damos`, `itant`,
`ogham`, `lexlep`, `lexlep-words` and `tir` are `nc` — for `ogham`, `lexlep` and
`tir` the stricter of conflicting upstream statements is held (for LexLep and
TIR confirmed by the maintainer, 2026-07-20). `rundata` is `odbl`: name and link
the Scandinavian Runic-text Database, and any database you derive from it is
share-alike. EDR's in-file notice reads "reserved rights"; the CC BY 4.0 grant
of its Zenodo deposit is the one the library follows.

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
