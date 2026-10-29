---
name: nabu-tibetan
description: "Use when searching, reading or citing Tibetan texts through the nabu MCP tools: the Derge Kangyur and Tengyur, 84000's English translations, OTDO and the Old Tibetan Annals and Chronicle, the SOAS gold corpus, the verbs database, the Mahāvyutpatti and the Tibetan dictionaries. Covers script versus Wylie, xct/otb/bod language tags, syllable-grain indexing and the words filter, woodblock errors preserved, Toh numbers and folio lines, the Kangyur-84000 pairing, annotation tiers, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: tibetan
  origin: hand-tuned
  sources: "actib derge-kangyur derge-tengyur e84000 jaschke-1881 lotsawa-house monlam-lexicon mvp nabu-data old-tibetan otdo soas-tibetan tibetan-verbs wiktionary-bo"
---

# The Tibetologist — the `tibetan` desk

The Tibetologist — the Land of Snows from Dunhuang documents to the complete Derge canon.

The Tibetan desk opens with the canon whole: the Public-Domain Digital Derge Kangyur and Tengyur (Esukhia's exact-representation of the woodblocks, Toh numbers as the crosswalk key), 84000's English translation layer, OTDO's Old Tibetan documents, and the gold-annotation lane (SOAS POS, the Annals and Chronicle); the lexicon shelves join as their packets land.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `actib` | ACTib v2.0 — The Annotated Corpus of Classical Tibetan (eKangyur seg + POS layers) | attribution |
| `derge-kangyur` | Digital Derge Kangyur (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur) | open |
| `derge-tengyur` | Digital Derge Tengyur (Esukhia/Barom Theksum Choling faithful copy of the Derge edition) | open |
| `e84000` | 84000 — Translating the Words of the Buddha (English Kangyur translations) | nc |
| `jaschke-1881` | Jäschke, A Tibetan-English Dictionary (London 1881; archive.org scan) | open |
| `lotsawa-house` | Lotsawa House — Tibetan Buddhist texts and translations | nc |
| `monlam-lexicon` | Monlam Tibetan headword lists (MonlamIT/Tibetan-Lexicon) | attribution |
| `mvp` | Mahāvyutpatti — Sanskrit–Tibetan–Chinese glossary (DILA TEI edition) | open |
| `nabu-data` | nabu-data — Nabu's own published datasets, consumed back (form→lemma instrument) | attribution |
| `old-tibetan` | Old Tibetan Corpus — the Annals and the Chronicle (tibetan-nlp) | attribution |
| `otdo` | OTDO — Old Tibetan Documents Online | attribution |
| `soas-tibetan` | SOAS Classical Tibetan gold POS corpus (Tibetan in Digital Communication) | attribution |
| `tibetan-verbs` | Tibetan Verbs Database (tibetan-nlp TVD) | open |
| `wiktionary-bo` | Wiktionary Tibetan — kaikki.org machine-readable extract | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `actib` — The Annotated Corpus of Classical Tibetan (ACTib) v2.0, by Meelen, Hill and Faggionato — a word-segmented and part-of-speech-tagged edition of the eKangyur, the Tibetan Buddhist canon, in 103 volume files per annotation layer (one of segmented word forms, one of form/tag pairs) with page and line markers carried inline. The segmentation and tagging are automatic rather than hand-checked. CC BY 4.0, published on Zenodo (doi:10.5281/zenodo.3951503).
- `derge-kangyur` — The Digital Derge Kangyur (Esukhia and Barom Theksum Choling, 2014–2018, building on the 2013 UVA-SOAS eKangyur): the first half of the Tibetan Buddhist canon — the Derge Kangyur whole, 103 volumes covering Tohoku numbers 1–1108, an exact representation of the Library of Congress Derge woodblock prints with even carving and spelling mistakes preserved, proofread against independent transcriptions. Classical Tibetan, every line self-cited by page and line of the printed volumes. Public domain.
- `derge-tengyur` — The Digital Derge Tengyur (Esukhia and Barom Theksum Choling): the second half of the Tibetan Buddhist canon — the Derge Tengyur whole, 213 volumes covering Tohoku numbers 1109–4569, disjoint by design from the Kangyur's 1–1108, in the same faithful page-and-line transcription as its Kangyur companion. Classical Tibetan. Public domain.
- `e84000` — 84000 — Translating the Words of the Buddha: the English translation layer of the Tibetan Buddhist canon — 396 published Kangyur translations and 3 Tengyur publications of sutra, tantra, and dhāraṇī literature, translated by named teams under 84000's editorial process. The body text is English; Tibetan titles (with Wylie transliteration) and Sanskrit where attested ride alongside, with a glossary of terms behind each translation, and everything is keyed to the Tohoku catalogue numbers of the Derge canon. CC BY-NC-ND 3.0.
- `monlam-lexicon` — The Monlam Tibetan headword lists published by Monlam IT, the only openly licensed machine-readable part of the Monlam dictionaries. Two lists are held: the Monlam Dictionary (about 107,000 headwords) and the Monlam Grand Dictionary (about 343,000), roughly 450,000 Tibetan headwords in all, which makes this the largest Tibetan lexical shelf. Headwords only: the Monlam definitions are not openly licensed and are not included. The Grand list has a gap upstream, where one late alphabetical band is missing. Apache 2.0.
- `mvp` — Dual-tagged like sdbh (domain + language desk): the 9th-c. glossary IS the Tibetan translators' instrument AND a Buddhist-studies reference. NOT indic — mw itself rides [indic] alone; MVP's Sanskrit side serves the crosswalk, and whole-source membership here is the Tibetan and Buddhist desks' (multi-tagging is dual, not maximal — the house rule).
- `nabu-data` — The datasets this library publishes back to the world (github.com/arvicco/nabu-data), registered as an ordinary source: a Sanskrit form-to-lemma table of 428,825 rows derived from the Digital Corpus of Sanskrit's gold annotations, plus Tibetan Wylie-folding and verb-lemma tables — each packaged with machine-readable metadata and its full upstream attribution chain. CC BY 4.0.
- `old-tibetan` — The two foundational Old Tibetan histories from Dunhuang — the Old Tibetan Annals (Pelliot tibétain 1288, 546 sentences) and the Old Tibetan Chronicle (Pelliot tibétain 1287, 1,577 sentences) — with gold word segmentation and part-of-speech tags, hand-annotated verb-argument dependencies, and Dotson's (2009) English translation aligned sentence-by-sentence to the Annals. Prepared by Faggionato, Garrett, and Meelen from the OTDO editions. MIT license.
- `otdo` — Old Tibetan Documents Online (ILCAA, Tokyo; Takeuchi et al.) — 414 critically edited Old Tibetan texts in Wylie transliteration: Dunhuang manuscripts (among them the Old Tibetan Annals and Chronicle), 34 imperial-period inscriptions (the Zhol pillar, the 821/822 Sino-Tibetan Treaty pillar, the Ldan-ma rock carvings), and five Old Zhangzhung texts. CC BY 4.0.
- `soas-tibetan` — A part-of-speech tagged corpus of Classical Tibetan (Hill, Garrett et al.; AHRC project "Tibetan in Digital Communication", SOAS 2012–2015): four classical texts with hand-corrected gold segmentation and POS tags — the Mdzangs blun (9th-century canonical sutra), Bu ston's 13th-century history of Buddhism, and the 15th-century biographies of Milarepa and Marpa — 991 lines and some 318,000 tagged tokens. CC BY 4.0.
- `tibetan-verbs` — The Tibetan Verbs Database: 2,491 rows of Tibetan verb tense stems — present, past, future, and imperative forms in Tibetan script — each attributed to its lexicographic sources, with the grammarians' disagreements deliberately preserved as separate rows rather than collapsed into a single verdict. CC0 1.0.
- `wiktionary-bo` — English Wiktionary's Tibetan entries in machine-readable form, via the kaikki.org wiktextract extraction: 3,651 records covering 3,394 words — a crowd-compiled glossary with English glosses, etymologies on 1,548 entries, and descendant trees. CC BY-SA and GFDL (the Wiktionary dual license).

## Field semantics on this desk

- **Script and Wylie meet in the index.** The Derge canon, the SOAS corpus and the
  dictionaries are stored in Tibetan script; OTDO is stored in Wylie
  transliteration; the Old Tibetan Annals and Chronicle are converted to script.
  Tibetan script is transcoded to EWTS before folding, so a script query and a
  Wylie query reach both kinds of shelf. Quote in the form `nabu_show` returns.
- **The language codes are distinct claims.** `xct` (Classical Tibetan: the
  canon), `otb` (Old Tibetan: Dunhuang documents, imperial inscriptions, the
  Annals), `bod` (the dictionaries), `xzh` (Zhangzhung). The `lang` filter does
  not widen `bod` to `xct` or `otb`; pass the tag you mean.
- **Indexing is per syllable.** A multi-syllable query also matches a syllable
  run that crosses a word boundary. `words: true` keeps only hits aligned with
  word boundaries from the segmentation dataset (a statistical segmenter, not a
  gold one; Tibetan-script queries only). `nabu_show` with `segmented: true`
  renders the same boundaries.
- **The Derge text reproduces the woodblocks.** Spelling and carving errors are
  preserved on purpose; for an error/correction pair the carved form is the
  text, the correction rides the apparatus annotations. Do not "correct" a
  quotation.
- **Toh numbers and folio lines.** Documents are Tohoku catalog numbers
  (`urn:nabu:derge-kangyur:toh<N>`; Kangyur Toh 1–1108, Tengyur Toh 1109–4569);
  passages are page.line on the woodblock folio (`…:1b.3`), volume-prefixed for
  multi-volume texts.
- **Kangyur and 84000.** The English 84000 translations are linked to their
  Kangyur text by Toh number, and `nabu_show` with `parallel: true` pairs them at
  folio-page grain from 84000's folio anchors. Pages without a counterpart render
  one-sided; translation front matter is omitted on the Tibetan side.
- **Lemma and annotation tiers.** The SOAS corpus has gold segmentation and POS;
  the Old Tibetan Corpus has gold segmentation and POS but silver lemmas.
  `tibetan-verbs` lists tense stems with each grammarian's analysis kept as a
  separate row — disagreement is data. `monlam-lexicon` holds headwords only.
- **Mahāvyutpatti.** `mvp` is the ninth-century Sanskrit–Tibetan translation
  glossary; its Sanskrit headwords are nominatives and its Tibetan lane is in
  Wylie.

## Conflation traps

- An 84000 translation is one modern translation of one Toh text; it is not the
  Tibetan and not the Sanskrit original. The Tibetan canon is itself a
  translation corpus: a Kangyur reading is evidence for the Tibetan translators'
  text, not for an Indic source.
- Old Tibetan (`otb`) and Classical Tibetan (`xct`) orthographies differ; a
  modern-orthography query can miss an Old Tibetan spelling.

## Licensing on this desk

The Derge Kangyur and Tengyur, the Mahāvyutpatti and the verbs database are
`open`; OTDO, the Old Tibetan and SOAS corpora and the dictionaries are
`attribution`; 84000 is `nc` (CC BY-NC-ND: no derivatives — quote, do not adapt).

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
