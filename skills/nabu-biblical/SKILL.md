---
name: nabu-biblical
description: "Use when comparing scripture across Hebrew, Aramaic, Greek, Latin, Syriac, Coptic, Ge'ez, Old Church Slavonic, Gothic and English witnesses through the nabu MCP tools (nabu_align, collate, nabu_cognates, nabu_parallels): the registered works nt, ot and psalms, witness statuses, sentence-versus-verse grain, Greek-numbered psalms and versification gaps, editions versus manuscripts, and the per-witness license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: biblical
  origin: hand-tuned
  sources: "betamasaheft-works bhsa bridging coptic-scriptorium dss eng-web hebrew-lexicon oshb peshitta sblgnt sdbh sefaria syriac-corpus ud vulgate"
---

# The Biblical scholar — the `biblical` desk

The Biblical scholar — one text across Hebrew, Greek, Latin, Syriac, Coptic and English witnesses.

The cross-language scripture hat: the Masoretic shelves and the Scrolls, the Greek NT, Vulgate and WEB, Peshitta and the Syriac corpus, Coptic Scriptorium, the Targums, and the OSHB-BHSA bridging module. The hebrew and syriac language desks coexist with this hat by design.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `betamasaheft-works` | Beta maṣāḥǝft Works — Ethiopic literature (Hiob-Ludolf-Zentrum, Hamburg) | attribution |
| `bhsa` | BHSA — Biblia Hebraica Stuttgartensia Amstelodamensis (ETCBC, Text-Fabric tf/2021) | nc |
| `bridging` | ETCBC bridging — OSHB↔BHSA word-level crosswalk (Text-Fabric tf/2021 module) | attribution |
| `coptic-scriptorium` | Coptic Scriptorium corpora (release v6.2.0) | nc |
| `dss` | DSS — Dead Sea Scrolls (Abegg/ETCBC, Text-Fabric tf/2.0) | nc |
| `eng-web` | World English Bible (eBible.org, via open-bibles) | open |
| `hebrew-lexicon` | OSHB Hebrew Lexicon — augmented Strong's + BDB outline (openscriptures) | attribution |
| `oshb` | Open Scriptures Hebrew Bible (Westminster Leningrad Codex + OSHM morphology) | open |
| `peshitta` | Peshitta OT incl. deuterocanon (ETCBC, Text-Fabric tf/0.2) | nc |
| `sblgnt` | SBL Greek New Testament (SBLGNT) | attribution |
| `sdbh` | UBS Dictionary of Biblical Hebrew (Semantic Dictionary of Biblical Hebrew) | attribution |
| `sefaria` | Sefaria — Targum shelf + Rabbinic core (Mishnah, Bavli, Minor Tractates, Yerushalmi, Tosefta) + Midrash (Rabbah, halakhic midrashim) | open |
| `syriac-corpus` | Digital Syriac Corpus (srophe, 632 TEI documents) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `vulgate` | Biblia Sacra Vulgata Clementina (Tweedale/eBible.org, via open-bibles) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `betamasaheft-works` — The Beta maṣāḥǝft Works collection (Hiob Ludolf Centre for Ethiopian and Eritrean Studies, Universität Hamburg) — 6,548 TEI records of Ethiopic (Gǝʿǝz) literature, one per work. Most are catalog records, but the text-bearing minority carries the Gǝʿǝz Bible (a near-complete Old Testament, all four Gospels, Acts, Epistles, Revelation), 1 Enoch, Jubilees, the Kebra nagast, royal chronicles of Susǝnyos and ʿAmda Ṣǝyon, and the Physiologus. CC BY-SA 4.0, granted in each file.
- `bhsa` — The Biblia Hebraica Stuttgartensia Amstelodamensis (ETCBC, VU Amsterdam) — the Amsterdam syntax corpus of the Hebrew Bible: 426,590 words across 39 books, 929 chapters and 23,213 verses, analyzed into 88,131 clauses and 253,203 phrases over 9,230 lexemes. Each word carries its ETCBC lexeme with English gloss and frequency, full morphology, and the ketiv/qere apparatus; clause and phrase constituency sits above the verse text. CC BY-NC 4.0, citing DOI 10.17026/dans-z6y-skyh. The license was confirmed by the ETCBC directorate (W. van Peursen, by email, 2026-10-15): all ETCBC-created data CC BY-NC 4.0, software MIT, the BHSA one indivisible package, commercial use via the Deutsche Bibelgesellschaft. Official attribution: "The text used for this work is the Biblia Hebraica Stuttgartentsia Amstelodamensis (BHSA), which contains the text of the Hebrew Bible augmented with linguistic annotations compiled by the Eep Talstra Centre for Bible and Computer, Vrije Universiteit Amsterdam. This work is licensed under a Attribution-NonCommercial 4.0 International (CC BY-NC 4.0). The Hebrew text is based on the Biblia Hebraica Stuttgartensia, edited by Karl Elliger and Wilhelm Rudolph, Fifth Revised Edition, edited by Adrian Schenker, (c) 1977 and 1997 Deutsche Bibelgesellschaft, Stuttgart."
- `bridging` — ETCBC's bridging dataset, by Dirk Roorda — a word-level concordance between the two major digital Hebrew Bibles, giving each word of the ETCBC's BHSA syntax corpus the morphological tag of its counterpart in the OpenScriptures Hebrew Bible: 420,108 of 426,590 words aligned (98.5 percent), computed by matching consonantal word forms with hand-curated exceptions, and honest markers on the regions that would not align. MIT license.
- `coptic-scriptorium` — Coptic Scriptorium corpora — the Sahidic and Bohairic New Testament plus monastic literature (Shenoute, Besa, apophthegmata), lemmatized and serving the alignment hub.
- `dss` — The Dead Sea Scrolls — Martin Abegg's transcriptions and morphological tagging of the scrolls from Qumran and the Judaean Desert, converted to Text-Fabric by Jacobs, Naaijer, and Roorda: about 501,000 words on 52,895 lines across roughly 1,000 scrolls, Hebrew and Aramaic in consonantal Hebrew script, cited by scroll, fragment, and line, with the editors' text-critical marks — corrections, reconstructions, vacats — preserved intact. CC BY-NC 4.0.
- `eng-web` — The World English Bible — 84 books of public-domain modern English scripture: the readable English witness in the alignment hub.
- `hebrew-lexicon` — The Open Scriptures Hebrew Bible project's Hebrew and Aramaic lexicon: an augmented Strong's dictionary — 9,299 augmented entry ids with Hebrew citation-form headwords, transliteration, part of speech, and curated one-line glosses, backed by 8,674 full Strong's entries — together with the Brown–Driver–Briggs lexicon in outline form, 11,845 entries citing the print pages of the 1906 edition. CC BY 4.0 for the files; the underlying Strong's and BDB texts are public domain.
- `oshb` — The Hebrew Bible in the Westminster Leningrad Codex — 39 books with complete morphology, augmented-Strong lemmas and ketiv/qere readings: the Masoretic leg of the OT alignment hub. Hebrew text kept byte-verbatim (never NFC-normalized).
- `peshitta` — The Peshitta Old Testament — the Syriac OT in 65 books including the deuterocanon: the electronic text of the Leiden Vetus Testamentum Syriace / Codex Ambrosianus, without the separately copyrighted apparatus. 426,835 words in 1,269 chapters and 31,341 verses, following the Masoretic versification; parallel manuscript recensions of ten books are kept as distinct witnesses. From the ETCBC (Amsterdam); CC BY-NC.
- `sblgnt` — The SBL Greek New Testament — a critically edited Greek NT with apparatus sigla, the corpus's NT Greek witness in the alignment hub.
- `sdbh` — The UBS Semantic Dictionary of Biblical Hebrew (ed. Reinier de Blois, United Bible Societies, 2000–2023), v0.9.2 — a semantic-domain dictionary of Biblical Hebrew and Aramaic: 7,932 entries carrying 16,220 definitions, 23,879 glosses, 16,686 semantic-domain tags, and 260,813 verse-word scripture references in Masoretic versification, keyed to the augmented Strong's number space; 372 entries cover Biblical Aramaic. CC BY-SA 4.0.
- `sefaria` — Sefaria's open library of Jewish texts: the Aramaic Targum column of the Tanakh (Onkelos, Targum Jonathan on the Prophets, the Writings targums, Pseudo-Jonathan, Targum Sheni) together with the rabbinic core — Mishnah, Babylonian and Jerusalem Talmud, Tosefta, minor tractates — and the classical midrash (Midrash Rabbah, the halakhic midrashim, Pesikta, Tanchuma, and the aggadic collections). Hebrew and Aramaic with English translations; Talmud cited by daf and amud, Bible by chapter and verse. Licensing is per version, mostly public domain and Creative Commons.
- `syriac-corpus` — The Digital Syriac Corpus (syriaccorpus.org; BYU, Oxford, Vanderbilt, Texas A&M) — 632 TEI editions of classical Syriac literature: Aphrahat's Demonstrations, the verse of Ephrem and Jacob of Serugh (over 100,000 poetry lines), the Peshitta New Testament letters, and hagiography, with author and work identifiers linked to syriaca.org. The Syriac base texts are public domain; the TEI editions CC BY 4.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `vulgate` — The complete Clementine Vulgate — the Latin Bible in canonical books, an OT and NT witness in the alignment hub.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *GEN 1.1 across all the versions at once.* — `nabu_align "GEN 1.1" (work: ot)`: Seven witnesses in one reply: LXX (Swete), Clementine Vulgate, both Masoretic texts (OSHB and BHSA), Targum Onkelos, the Peshitta, and the WEB English — every row carrying its own license class.

## Field semantics on this desk

- **`nabu_align` renders one citation across registered witnesses.** Three works
  are registered: `nt`, `ot`, `psalms`. Each witness row carries its own urn,
  language and license class, and a status: `ok`, `no_match` (synced, verse not
  attested there), `not_synced`, or `withheld` (excluded by license class). The
  registry asserts a shared *citation scheme*, not a shared text.
- **Sentence is not verse.** The PROIEL-family treebank witnesses are stored by
  sentence; verse identity comes from per-token citation parts, and many
  sentences cross verse boundaries. An aligned row lists every ref a sentence
  covers — do not quote a whole sentence as "the verse".
- **Versification.** The `psalms` work uses the Greek (Septuagint) numbering as
  its vocabulary; the Hebrew-numbered witnesses are remapped onto it, and the
  psalms Hebrew and Greek divide differently are left "not attested" rather than
  forced. The `ot` work covers only the books its witnesses share a scheme for;
  some Masoretic-family witnesses hold out books whose chapter division differs.
  A `no_match` can be a versification gap, not a textual omission.
- **The Septuagint is Swete's edition** (in the First1KGreek shelf), not Rahlfs.
- **`collate: true`** diffs raw tokens within cells of the same language *and*
  script; a same-language witness in another script or transcription is set
  aside (`cross_script`), not collated. Every diacritic is kept in a collation.
- **Two Masoretic texts, two annotation grains.** `oshb` and `bhsa` both edit the
  Leningrad Codex. OSHB lemmas are augmented Strong's numbers (`b/7225`); BHSA
  and DSS lemmas are Hebrew lexemes. A `lemma` search therefore speaks a
  different vocabulary per source; see the `nabu-hebrew` skill.

## Conflation traps

- **Witnesses are editions, not manuscripts.** SBLGNT, the PROIEL Greek NT and
  the Swete LXX are modern critical or diplomatic editions; Vulgate, Peshitta,
  Targum and the Coptic and Old Church Slavonic codices are distinct witnesses
  with their own textual histories. An agreement across columns is agreement
  between editions.
- **Translation is not a witness of the original.** The WEB English and the
  translation siblings help reading; they never establish what a Greek or Hebrew
  text says.
- **Two NT editions of the same language are never deduplicated** (SBLGNT beside
  PROIEL Greek; the Clementine Vulgate beside the PROIEL Latin NT; Marianus in
  Cyrillic and in transcription). Count per witness.
- **Cognates in parallel.** `nabu_cognates` meets at a reconstruction root; a meet
  at Proto-Germanic involving a Slavic word is very possibly a loan, while a PIE
  meet is the inheritance signal. Recall is bounded by Wiktionary coverage and
  gold lemmatization: no hit is not evidence.

## Licensing on this desk

Mixed by design, so read every row: the PROIEL treebank witnesses (Greek,
Latin, Gothic, Armenian, OCS NT) are `nc`, as are BHSA, the Dead Sea Scrolls and
the Peshitta; SBLGNT, the lexicons and the Syriac corpus are `attribution`; OSHB,
the Vulgate, WEB and the Sefaria versions marked public domain are `open`.
Coptic Scriptorium documents vary between `nc` and `attribution`.

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
