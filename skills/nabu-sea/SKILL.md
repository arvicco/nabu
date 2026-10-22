---
name: nabu-sea
description: "Methodological guidance for the sea desk of a Nabu library (Southeast Asianist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: sea
  origin: generated
  sources: "ban-wikisource dharma-campa dharma-javanese-texts dharma-khmer dharma-nusantara dharma-pyu jv-wikisource ms-wikisource obi-burmese ojw su-wikisource th-wikisource"
---

# The Southeast Asianist — the `sea` desk

The Southeast Asianist — the Indic cosmopolis at its eastern edge: Sanskrit charters beside the vernaculars they seeded.

Epigraphy-first, opening on the DHARMA corpora: the Old Khmer inscriptions (the Cœdès K-numbers), the Campā corpus, the Nusantara charters (Old Malay, Old Javanese, Old Sundanese), the Pyu corpus, and the Bagan Old Burmese inscriptions — with the kakawin critical editions as the literary wing and the Old Javanese Wordnet as its glossary, joining as their packets land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `ban-wikisource` | Balinese Wikisource — the lontar (palm-leaf manuscript) transcriptions | attribution |
| `dharma-campa` | DHARMA Campā inscriptions (Old Cham epigraphy) | attribution |
| `dharma-javanese-texts` | DHARMA Nusantara philology (the kakawin library and Old Sundanese texts) | attribution |
| `dharma-khmer` | DHARMA Corpus des inscriptions khmères (Old Khmer epigraphy) | attribution |
| `dharma-nusantara` | DHARMA Nusantara epigraphy (Old Javanese/Malay/Sundanese charters) | attribution |
| `dharma-pyu` | DHARMA Corpus of Pyu Inscriptions | attribution |
| `jv-wikisource` | Javanese Wikisource — the dated 19th-century cone (manuscripts and prints to 1900) | attribution |
| `ms-wikisource` | Malay Wikisource — the Jawi manuscript cone (Leiden · BL · BnF · KITLV manuscripts) | attribution |
| `obi-burmese` | OBI — Structured Corpus of Old Burmese Stone Inscriptions | attribution |
| `ojw` | OJW — the Old Javanese Wordnet (Moeljadi et al.) | attribution |
| `su-wikisource` | Sundanese Wikisource — the dated 19th-century cone (prints to 1900 · the Carita Parahyangan) | attribution |
| `th-wikisource` | Thai Wikisource — ประชุมพงศาวดาร (the Collected Chronicles, parts printed to BE 2473) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `ban-wikisource` — The lontar corpus of Balinese Wikisource: palm-leaf manuscripts transcribed leaf by leaf in Balinese script straight from photographs of the leaves, with no printed edition in between. The photographs come from the Internet Archive's Balinese Digital Library, village-collection photography campaigns and Leiden manuscripts. There are about 1,250 manuscripts, one document per manuscript and one passage per transcribed page, with the manuscript's lines, leaf numbers and per-page proofreading status kept. Kawi (Old Javanese) and Balinese dominate, with a handful of Sasak texts, and the Gedong Kirtya classes (Agama, Itihasa, Wéda, Babad) are recorded. Much of the corpus came over from the palmleaf.org transcription wiki under a Wikimedia project grant. Printed books and modern studies on the wiki are left out. CC BY-SA 4.0.
- `dharma-campa` — The corpus of the inscriptions of Campā from the ERC DHARMA project (EFEO): about 120 editions of Old Cham and Sanskrit epigraphy from the Cham polities of coastal Vietnam, absorbing and superseding the earlier ISAW–EFEO corpus. Its Old Cham inscription from Đông Yên Châu is the oldest attested Austronesian text anywhere. The editions are romanized TEI, read line by line for prose and verse by verse for Sanskrit. Each file's own licence governs, recorded verbatim: CC BY-SA 4.0 (CC BY 4.0 on some).
- `dharma-javanese-texts` — The Nusantara philology corpus of the ERC DHARMA project (EFEO), the literary side of the Old Javanese record. It holds kakawin critical editions of the first rank (the Deśavarṇana, Sutasoma, Arjunavivāha, Pararaton and Calon Arang among them), prose critical editions such as the Bhīma Svarga with its four-witness apparatus (the editor's chosen reading is served), Old Sundanese treatises, and diplomatic manuscript transcriptions at folio-and-line grain. There are about ninety editions, with verse cited by chapter, canto, stanza and line and each canto's metre recorded. CC BY 4.0, per the files' own licence.
- `dharma-khmer` — The Corpus des inscriptions khmères of the ERC DHARMA project (EFEO): George Cœdès's K-numbered corpus digitized, about 1,200 editions of pre-Angkorian and Angkorian epigraphy. It is Old Khmer prose and Sanskrit verse, romanized, with a few Middle Khmer, Pali and Prakrit pieces, and it is the largest single corpus of Southeast Asian inscriptions. Prose is read at the inscription's physical line and verse at the edition's own stanza and line; bilingual inscriptions keep each passage's own language. It is a working corpus, and each edition's maturity is recorded. CC BY-SA 4.0 per the files' own licence.
- `dharma-nusantara` — The Nusantara epigraphy corpus of the ERC DHARMA project (EFEO): about 300 editions of inscriptions from the Indonesian archipelago and beyond. It includes Old Javanese sīma charters (Sangguran, Mantyasih), the Borobudur inscriptions, Old Sundanese (Kawali, Batutulis), Old Malay (Sojomerto, and the Laguna copperplate, the oldest document of the Philippines) and Sanskrit. It holds the library's whole Old Malay record. Editions are romanized and read at the stone's physical line, words broken across faces kept whole. CC BY-SA 4.0 per the files' own licence.
- `dharma-pyu` — The Corpus of Pyu Inscriptions (Arlo Griffiths et al., ERC DHARMA project): about 160 romanized editions in Pyu, the extinct Sino-Tibetan language of the city-states of the Irrawaddy valley (roughly 5th–13th century CE). Alongside the Pyu are short Pali, Sanskrit, Old Burmese and Prakrit passages, and a run of Old Mon lines that forms the first digital Old Mon text anywhere. Each file's own CC BY-SA 4.0 licence is the whole grant.
- `ms-wikisource` — The Jawi manuscript transcriptions of Malay Wikisource: classical Malay texts transcribed straight from manuscript scans held in Leiden, London, Paris, Berlin, Harvard, Princeton and elsewhere, with no printed edition in between. About 64 texts are held, nearly all in Jawi (Arabic script), with one Rumi text and one Rencong text with its Latin transliteration. More than half are dated by the manuscript dates the wiki gives, from single years to centuries, and the copyist named on each page is recorded. Most pages are not yet proofread; each text records its proofreading levels rather than being filtered by them. Language is held coarsely as Malay. Texts public domain; transcriptions CC BY-SA 4.0.
- `obi-burmese` — OBI, A Structured Corpus of Old Burmese Stone Inscriptions (Zenodo), compiled from the Archaeological Directorate's Ancient Burmese Inscriptions, Thein Tun's recently found inscriptions and the Bagan Epigraphic Database. It holds about 1,120 files, one per face and page, of Bagan-period inscriptions in Old Burmese from the Myazedi era on. Each line gives the Myanmar-script text with its transliteration beside it. CC BY 4.0.
- `ojw` — The Old Javanese Wordnet (David Moeljadi et al., LREC 2020), extracted from the digitized Old Javanese–English Dictionary of Zoetmulder: about 3,600 Old Javanese lemmas over some 5,000 senses in 2,054 synsets. Each lemma carries its Princeton WordNet 3.0 synset ids, which link it to other wordnets, and its derived forms. No glosses ship with the data. It stands in as the open Old Javanese glossary, since the dictionary itself is not openly licensed. CC BY 4.0.
- `th-wikisource` — The Prachum Phongsawadan (ประชุมพงศาวดาร), the Collected Chronicles that the Vajirañāṇa Library and Royal Institute printed in parts from 1914, as transcribed on Thai Wikisource from the scanned first prints. About 92 texts are held in Thai script, each dated by its print year (converted from the Buddhist Era) and naming its publisher. Parts known only from reprints after 1930 are left out, as are the funeral-print prefaces, biographies and contents pages. The Three Seals Law, which the wiki hosts only in post-1930 editions, is excluded entirely. Texts public domain; transcriptions CC BY-SA 4.0.

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
