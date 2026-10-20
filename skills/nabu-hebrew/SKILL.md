---
name: nabu-hebrew
description: "Use when searching, reading or citing Hebrew and Aramaic texts through the nabu MCP tools: the two Masoretic editions (OSHB, BHSA) and their bridging module, the Dead Sea Scrolls, Sefaria's Targums and rabbinic texts, the Hebrew lexicons (BDB outline, SDBH), and the inscriptions of Israel/Palestine. Covers the non-NFC Masoretic text, ketiv versus qere, Strong's ids versus ETCBC lexemes, reconstruction marks in the scrolls, per-version Sefaria licensing, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: hebrew
  origin: hand-tuned
  sources: "bhsa bridging dss elephantine hebrew-lexicon iip oshb sdbh sefaria ud"
---

# The Hebraist — the `hebrew` desk

The Hebraist — Masoretic vowels, Qumran consonants, the Aramaic of the Targums.

The Hebrew-and-Aramaic language desk beside the cross-language biblical hat: OSHB, BHSA, DSS, SDBH and the lexicon shelf, the Sefaria Targums, the bridging crosswalk, and IIP's inscriptions of Israel/Palestine.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `bhsa` | BHSA — Biblia Hebraica Stuttgartensia Amstelodamensis (ETCBC, Text-Fabric tf/2021) | nc |
| `bridging` | ETCBC bridging — OSHB↔BHSA word-level crosswalk (Text-Fabric tf/2021 module) | attribution |
| `dss` | DSS — Dead Sea Scrolls (Abegg/ETCBC, Text-Fabric tf/2.0) | nc |
| `elephantine` | Elephantine — the Berlin ERC papyri and ostraca database | attribution |
| `hebrew-lexicon` | OSHB Hebrew Lexicon — augmented Strong's + BDB outline (openscriptures) | attribution |
| `iip` | Inscriptions of Israel/Palestine (Brown University) | nc |
| `oshb` | Open Scriptures Hebrew Bible (Westminster Leningrad Codex + OSHM morphology) | open |
| `sdbh` | UBS Dictionary of Biblical Hebrew (Semantic Dictionary of Biblical Hebrew) | attribution |
| `sefaria` | Sefaria — Targum shelf + Rabbinic core (Mishnah, Bavli, Minor Tractates, Yerushalmi, Tosefta) + Midrash (Rabbah, halakhic midrashim) | open |
| `ud` | Universal Dependencies — ancient treebanks | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `bhsa` — The Biblia Hebraica Stuttgartensia Amstelodamensis (ETCBC, VU Amsterdam) — the Amsterdam syntax corpus of the Hebrew Bible: 426,590 words across 39 books, 929 chapters and 23,213 verses, analyzed into 88,131 clauses and 253,203 phrases over 9,230 lexemes. Each word carries its ETCBC lexeme with English gloss and frequency, full morphology, and the ketiv/qere apparatus; clause and phrase constituency sits above the verse text. CC BY-NC 4.0, citing DOI 10.17026/dans-z6y-skyh. The license was confirmed by the ETCBC directorate (W. van Peursen, by email, 2026-10-15): all ETCBC-created data CC BY-NC 4.0, software MIT, the BHSA one indivisible package, commercial use via the Deutsche Bibelgesellschaft. Official attribution: "The text used for this work is the Biblia Hebraica Stuttgartentsia Amstelodamensis (BHSA), which contains the text of the Hebrew Bible augmented with linguistic annotations compiled by the Eep Talstra Centre for Bible and Computer, Vrije Universiteit Amsterdam. This work is licensed under a Attribution-NonCommercial 4.0 International (CC BY-NC 4.0). The Hebrew text is based on the Biblia Hebraica Stuttgartensia, edited by Karl Elliger and Wilhelm Rudolph, Fifth Revised Edition, edited by Adrian Schenker, (c) 1977 and 1997 Deutsche Bibelgesellschaft, Stuttgart."
- `bridging` — ETCBC's bridging dataset, by Dirk Roorda — a word-level concordance between the two major digital Hebrew Bibles, giving each word of the ETCBC's BHSA syntax corpus the morphological tag of its counterpart in the OpenScriptures Hebrew Bible: 420,108 of 426,590 words aligned (98.5 percent), computed by matching consonantal word forms with hand-curated exceptions, and honest markers on the regions that would not align. MIT license.
- `dss` — The Dead Sea Scrolls — Martin Abegg's transcriptions and morphological tagging of the scrolls from Qumran and the Judaean Desert, converted to Text-Fabric by Jacobs, Naaijer, and Roorda: about 501,000 words on 52,895 lines across roughly 1,000 scrolls, Hebrew and Aramaic in consonantal Hebrew script, cited by scroll, fragment, and line, with the editors' text-critical marks — corrections, reconstructions, vacats — preserved intact. CC BY-NC 4.0.
- `elephantine` — The Berlin database of papyri and ostraca from Elephantine (Ägyptisches Museum und Papyrussammlung, ERC project "Localizing 4000 Years of Cultural History", Verena Lepper): 10,744 objects documenting four millennia of life on the island — Greek, Imperial Aramaic, Demotic, Coptic, hieratic, Middle Egyptian, Arabic, and Phoenician among the languages, the Aramaic written in unpointed Hebrew script — in TEI editions with English translations, structured dating, and Trismegistos links. CC BY-SA 3.0 under each record's own grant.
- `hebrew-lexicon` — The Open Scriptures Hebrew Bible project's Hebrew and Aramaic lexicon: an augmented Strong's dictionary — 9,299 augmented entry ids with Hebrew citation-form headwords, transliteration, part of speech, and curated one-line glosses, backed by 8,674 full Strong's entries — together with the Brown–Driver–Briggs lexicon in outline form, 11,845 entries citing the print pages of the 1906 edition. CC BY 4.0 for the files; the underlying Strong's and BDB texts are public domain.
- `iip` — Inscriptions of Israel/Palestine (Michael Satlow, Brown University): 5,535 EpiDoc records of the multilingual epigraphy of the southern Levant, roughly 500 BCE–640 CE — ossuaries, ostraca, mosaics, and epitaphs (Beth She'arim, Masada, Zoora) in Greek, Jewish Aramaic, Hebrew, and Latin with smaller Phoenician, Syriac, Armenian, and Georgian slices, spanning Jewish, Christian, and pagan religious contexts, with dating and findspots throughout. CC BY-NC 4.0.
- `oshb` — The Hebrew Bible in the Westminster Leningrad Codex — 39 books with complete morphology, augmented-Strong lemmas and ketiv/qere readings: the Masoretic leg of the OT alignment hub. Hebrew text kept byte-verbatim (never NFC-normalized).
- `sdbh` — The UBS Semantic Dictionary of Biblical Hebrew (ed. Reinier de Blois, United Bible Societies, 2000–2023), v0.9.2 — a semantic-domain dictionary of Biblical Hebrew and Aramaic: 7,932 entries carrying 16,220 definitions, 23,879 glosses, 16,686 semantic-domain tags, and 260,813 verse-word scripture references in Masoretic versification, keyed to the augmented Strong's number space; 372 entries cover Biblical Aramaic. CC BY-SA 4.0.
- `sefaria` — Sefaria's open library of Jewish texts: the Aramaic Targum column of the Tanakh (Onkelos, Targum Jonathan on the Prophets, the Writings targums, Pseudo-Jonathan, Targum Sheni) together with the rabbinic core — Mishnah, Babylonian and Jerusalem Talmud, Tosefta, minor tractates — and the classical midrash (Midrash Rabbah, the halakhic midrashim, Pesikta, Tanchuma, and the aggadic collections). Hebrew and Aramaic with English translations; Talmud cited by daf and amud, Bible by chapter and verse. Licensing is per version, mostly public domain and Creative Commons.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Compare the two Masoretic editions of a verse.* — `nabu_align "GEN 1.1" (work: ot)`: OSHB (WLC) and BHSA (ETCBC) side by side with the Targum and Peshitta columns — two independent Masoretic witnesses at deliberately different annotation grains, never merged.

## Field semantics on this desk

- **Hebrew and Aramaic text is not NFC-normalized.** Masoretic combining marks
  (dagesh, shin dot, vowels, accents) are not stable under Unicode NFC, and the
  upstream editions forbid normalizing, so `hbo` and `arc` text is stored in the
  editions' own mark order. Search still folds marks away, so an unpointed query
  finds pointed text; but compare and quote pointed text byte-for-byte only from
  `nabu_show`, and never re-normalize it.
- **Ketiv is the text; qere rides the tokens.** In OSHB and BHSA the stored word
  is the ketiv (the written consonants); the qere (the read form) is a token
  annotation. A search for a qere form may miss the passage.
- **OSHB and BHSA are two editions of the Leningrad Codex** — never merged.
  `oshb` lemmas are augmented Strong's numbers (`b/7225`, `1254 a`) with OSHB
  morphology; `bhsa` lemmas are ETCBC consonantal lexemes (homographs share one
  lexeme), with clause and phrase structure. The `bridging` module adds OSHB
  morphology to BHSA tokens for most words. A `lemma` search must use the
  vocabulary of the source you target.
- **Dictionaries key differently.** `hebrew-lexicon` entries are keyed by the
  same augmented Strong's ids as OSHB (a direct join) and also carry the BDB
  outline; `sdbh` (the Semantic Dictionary of Biblical Hebrew) is keyed by
  Strong's codes in the same space and is still incomplete upstream. These
  shelves are registered as Hebrew, so they do not answer an Aramaic-scoped
  lookup.
- **Dead Sea Scrolls.** `dss`: one document per scroll, passages fragment.line
  (`urn:nabu:dss:<scroll>:<fragment>.<line>`), language per word (Hebrew,
  Aramaic, Greek). Reconstructed, corrected, uncertain and vacat material is
  marked in token annotations, not in the bare text — check them before citing a
  reading as preserved. The scrolls carry no dating rows.
- **Sefaria.** Targums and the Talmuds are tagged `arc`; Mishnah, Tosefta and
  midrash `hbo`. Each version is ingested only under a license named in its own
  file. In the `ot` alignment only Onkelos, Jonathan and the Writings Targum are
  witnesses; Pseudo-Jonathan and Neofiti are held but not aligned.
- **Inscriptions.** IIP (Inscriptions of Israel/Palestine) and the Elephantine
  Aramaic papyri follow the epigraphy rules (`nabu-epigraphy`): the text is an
  edited reading with restorations included.

## Conflation traps

- Biblical Hebrew of Qumran and of the Masoretes are different witnesses with
  different orthographies (Qumran plene spellings); a DSS form is not a variant
  "of the MT" until you have aligned the passage.
- A Strong's number groups by a nineteenth-century lexical decision; an ETCBC
  lexeme groups differently. Do not compare frequency counts across the two
  lemma vocabularies.

## Licensing on this desk

OSHB and the public-domain Sefaria versions are `open`; the lexicon shelves are
`attribution`; BHSA, the Dead Sea Scrolls and IIP are `nc`.

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
