---
name: nabu-arabic
description: "Methodological guidance for the arabic desk of a Nabu library (Arabist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: arabic
  origin: generated
  sources: "althurayya diccas kitab kitab-reuse ociana openiti"
---

# The Arabist — the `arabic` desk

The Arabist — the Islamicate library whole, Quran and hadith to falsafa and adab.

The OpenITI lane: premodern Arabic and Persian literature at corpus scale — Quran and hadith, history and biography, law and falsafa, the dīwāns and adab — with the Persian shelf (Ḥāfiẓ, Ibn Sīnā) riding the same Arabic-script fold that makes ara/fas cross-searchable — and DiCCAS, disaster accounts excerpted from ten classical sources with catastrophe terminology tagged — and,, the KITAB text-reuse instrument: upstream-computed reuse edges joining the held OpenITI books pairwise on the intertext desk.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `althurayya` | al-Ṯurayyā Gazetteer — the early Islamic world (gazetteer instrument) | attribution |
| `diccas` | DiCCAS — Disaster Corpus in Classical Arabic Sources (Cicola, Bologna) | nc |
| `kitab` | KITAB Text Reuse Data — passim pairwise alignments over OpenITI (links instrument, pilot) | nc |
| `kitab-reuse` | KITAB Text Reuse Data — pairwise statistics (intertext instrument) | nc |
| `ociana` | OCIANA — Online Corpus of the Inscriptions of Ancient North Arabia | research_private |
| `openiti` | OpenITI — Open Islamicate Texts Initiative (premodern Arabic + Persian), release 2025.1.9 | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `althurayya` — al-Ṯurayyā, the gazetteer of the early Islamic world, by Maxim Romanov, Masoumeh Seydi and colleagues at the University of Leipzig. It is georeferenced from Georgette Cornu's Atlas du monde arabo-islamique à l'époque classique, IXe–Xe siècles (Brill 1983). Some 2,500 features (towns, waystations, villages, capitals, regions, waters, sites) each carry the Arabic name, a full transliteration, simplified search forms and variant lists, a region and a map point. The gazetteer holds no texts. It serves as a place index of about 2,330 named places for resolving place mentions on the Arabic shelf. The data is CC BY 4.0; the code is Apache 2.0.
- `diccas` — DiCCAS, the Disaster Corpus in Classical Arabic Sources (Cicola, University of Bologna, 2025; CLARIN.SI). It gathers accounts of catastrophe from ten classical works: the Qurʾān, Ṣaḥīḥ al-Bukhārī and Ṣaḥīḥ Muslim, al-Ṭabarī's history and his tafsīr, Ibn Taghrībirdī, al-Maqrīzī, al-Dhahabī, Ibn al-Jawzī and al-Jāḥiẓ. Disaster terminology is tagged throughout. Each book is one document cited paragraph by paragraph, and the project's English translations of the paragraphs travel as glosses beside the Arabic, never mixed into it. CC BY-NC-SA 4.0.
- `kitab` — Text-reuse data from the KITAB project (kitab-project.org), computed over the OpenITI corpus of premodern Arabic texts: for each pair of books, aligned passages with exact character and word offsets — a map of quotation, borrowing, and shared material across the Islamicate written tradition. CC BY-NC-SA 4.0 via the Zenodo record.
- `kitab-reuse` — The KITAB project's text-reuse statistics (Aga Khan University; Zenodo, release 2023.1.8): for some 1.6 million pairs of books in the OpenITI corpus of premodern Arabic, the number of passages one book shares with another, with character-match figures and chronology flags. It holds no texts. It serves as an intertext instrument, linking the held OpenITI books that reuse each other, about 930,000 book-to-book links. The passage-level alignments on the same deposit are not yet taken in. CC BY-NC-SA 4.0.
- `ociana` — OCIANA, the Online Corpus of the Inscriptions of Ancient North Arabia (Khalili Research Centre, University of Oxford): the inscriptions the pre-Islamic peoples of northern Arabia and the Syro-Jordanian desert carved on rocks, in the Safaitic, Hismaic, Dadanitic and Taymanitic scripts and their smaller relatives (Hasaitic, Dumaitic, the Thamudic families), with a handful of Greek, Latin, Minaic and Nabataean texts found among them. Most are short graffiti left by nomads and oasis dwellers, signatures and genealogies ("By N son of N") that grow into prayers to their deities, laments for the dead and notes on camping, herding and raiding. About 37,000 texts are held, each read in its scholarly transliteration with the English translation, readings of earlier editors, commentary, references and the find site, usually with coordinates. From the University of Oxford's archive deposit (2017), held for private study and research under the archive's terms of use, never redistributed.
- `openiti` — OpenITI — the Open Islamicate Texts Initiative (Miller, Romanov, Savant et al.): the premodern Islamicate library at corpus scale, 14,107 text versions and 2.35 billion words of premodern and early-modern Arabic with a Persian shelf (Ḥāfiẓ, Ibn Sīnā) — Quran and hadith, history and biography, law, philosophy, and poetry, aggregated from Shamela, Hindawi, and other digital collections. CC BY-NC-SA 4.0.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Who reused this passage of Ibn Sīnā's Šifāʾ?* — `nabu_links urn:nabu:openiti:0428IbnSina.ShifaAfcalWaInficalat.ALCorpus00001-ara2:1.223.4`: kind="reuse" edges from the KITAB pairwise data: the passage reappears in Faḫr al-Dīn al-Rāzī's Mulaḫḫaṣ (two centuries later) with character/word offsets riding the edge detail — upstream- computed alignments, distinct from nabu's own intertext detection.

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
