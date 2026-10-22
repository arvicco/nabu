---
name: nabu-classical
description: "Use when searching, reading or citing Ancient Greek and Latin literature through the nabu MCP tools: the Perseus and First1KGreek canons, Diorisis, GLAUx, the PROIEL and UD treebanks, LSJ and Lewis & Short, the meter layer, and the late-antique and medieval Latin shelves. Covers CTS edition urns versus works, translations as documents, gold versus silver lemmas, morphology facets, scansion layers, composition versus edition dates, lexicon citation resolution, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: classical
  origin: hand-tuned
  sources: "corpus-corporum croala damos digiliblt diorisis first1k-greek glaux hypotactic ig-cyprus lasla lexica lila openmgh pedecerto perseus-greek perseus-latin proiel sigla ud vulgate"
---

# The Classicist — the `classical` desk

The Classicist — Greek and Latin letters read whole, Homer to the late grammarians.

The Greco-Roman literary lane: the Perseus canons and First1KGreek, Diorisis, LSJ and Lewis & Short, the grc/lat treebanks, and the Vulgate wearing its Latin-literature hat beside its scripture one.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `corpus-corporum` | Corpus Córporum — Patrologia Latina (mlat.uzh.ch, Univ. of Zurich) | nc |
| `croala` | Croatiae auctores Latini — CroALa (Jovanović, ed.) | attribution |
| `damos` | DĀMOS — Database of Mycenaean at Oslo (the Linear B corpus) | nc |
| `digiliblt` | digilibLT — Biblioteca digitale di testi latini tardoantichi (CIRCSE CoNLL-U) | attribution |
| `diorisis` | Diorisis Ancient Greek Corpus (Vatri & McGillivray, figshare v1 2018) | attribution |
| `first1k-greek` | Open Greek and Latin — First1KGreek | attribution |
| `glaux` | GLAUx — the Greek Language Automated (Keersmaekers) | attribution |
| `hypotactic` | Hypotactic — Greek metrical scansions (D. Chamberlain) | attribution |
| `ig-cyprus` | IG XV 1,1 — Inscriptiones Cypri syllabicae (BBAW Inscriptiones Graecae digital edition) | attribution |
| `lasla` | LASLA — Latin corpus of the Laboratoire d'Analyse Statistique des Langues Anciennes (Liège), CIRCSE LiLa-linked CoNLL-U release | nc |
| `lexica` | Perseus Lexica — LSJ + Lewis & Short | attribution |
| `lila` | LiLa Lemma Bank — Latin canonical forms (lemma-spine instrument) | attribution |
| `openmgh` | openMGH — Monumenta Germaniae Historica editions (MGH / BSB, digital MGH) | attribution |
| `pedecerto` | Pedecerto — Digital Latin Metre (Udine/Ca' Foscari): hexameter + verse scansions | nc |
| `perseus-greek` | Perseus Digital Library — canonical Greek literature | attribution |
| `perseus-latin` | Perseus Digital Library — canonical Latin literature | attribution |
| `proiel` | PROIEL Treebank | nc |
| `sigla` | SigLA — The Signs of Linear A: a paleographical database (Salgarella & Castellan) | nc |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `vulgate` | Biblia Sacra Vulgata Clementina (Tweedale/eBible.org, via open-bibles) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `corpus-corporum` — Migne's Patrologia Latina as held by Corpus Corporum, the Zurich Latin meta-repository: 5,277 patristic and medieval Latin works by 1,528 authors spanning 105-1847 CE — the church fathers (Augustine, Jerome, Gregory the Great), monastic rules, chronicles, sermons, hagiography, and the editorial prefaces of the 221-volume 1844-1864 series. Digitized from the non-critical 16th-18th-century editions Migne reprinted (OCR, upstream's own caveat); Migne column references ride each passage. The Zurich transcription layer is non-commercial; most underlying texts are public domain.
- `croala` — 309,180 passages; eyeballed via urn:nabu:croala:albert-i-inscr:d1.p1 + random passages — the string-place crash found and fixed in that verification). Sparse GitFetch of github.com/nevenjovanovic/croatiae-auctores-latini-textus scoped to the cone [txts, LICENSE.md, README.md]: a blobless no-checkout clone (the DCS/GLAUx recipe), skipping the schemas/ scripts/ oXygen cruft. One file ~6 MB — why the parser streams.
- `damos` — The complete corpus of Linear B, the syllabic script in which the palace scribes of Late Bronze Age Crete and mainland Greece (about the 14th to the 13th century BCE) wrote Mycenaean Greek, the oldest attested form of Greek — as edited in DĀMOS, the Database of Mycenaean at Oslo (University of Oslo). Some six thousand documents: the clay tablets of the Knossos and Pylos archives above all, with Thebes, Mycenae, Tiryns, Khania and the smaller sites, the sealings and labels, and the inscribed stirrup jars that carried oil and wine across the Aegean. The texts are the palaces' bookkeeping — rosters of men and women, livestock and wool, land holdings, chariots and armour, offerings of gold vessels to Poseidon and Potnia — given in the standard transliteration line by line, syllabograms romanized, logograms such as VIR (man) or MUL (woman) as Latin abbreviations, damaged signs under-dotted and lacunae marked as the edition marks them. Each document carries its series and scribal hand, findspot, ceramic-phase dating, museum and inventory number and bibliography. CC BY-NC-SA 4.0.
- `digiliblt` — digilibLT — the Biblioteca digitale di testi latini tardoantichi (Università del Piemonte Orientale, Vercelli): 373 late-antique secular Latin prose texts of the 2nd–7th centuries AD — Ammianus, the grammarians, the agrimensores, the jurists — the transition band between classical and medieval Latin. This edition of the corpus is machine-lemmatized and part-of-speech tagged, with links into the LiLa Latin lemma bank on every token. CC BY-SA 4.0, crediting digilibLT and CIRCSE/LiLa.
- `diorisis` — The Diorisis Ancient Greek Corpus — 820 works from Homer to early Byzantium, automatically lemmatized (10.2M words): the silver layer over the Greek canon.
- `first1k-greek` — The long tail Perseus doesn't cover: Athenaeus, Philo, church fathers, grammarians, scholia, minor historians, medical and mathematical writers. Complements §1 with the texts scholars actually struggle to find in searchable form. English coverage is thin (41 editions) but includes section-aligned pieces like Palaephatus' De Incredibilibus.
- `glaux` — GLAUx — "the Greek Language Automated" (Alek Keersmaekers, Leuven): around 20 million tokens of Ancient Greek spanning the 8th century BC to about the 4th century AD, automatically annotated for morphology, syntax, lemma, animacy, and word sense following the AGDT guidelines — corpus-scale machine analysis reaching well beyond the hand-treebanked canon. Predominantly CC BY-SA, with a small slice carried under non-commercial terms.
- `hypotactic` — Hypotactic (David Chamberlain, hypotactic.com): complete metrical scansions of the major Greek verse corpus, line by line — Homer, Hesiod, the Homeric Hymns, Aeschylus, Pindar, Apollonius, Theocritus, Nicander, Oppian, Callimachus, Bion, and Moschus among them. Each line pairs the Greek text with its scansion pattern, meter name, and caesura labels — a reader's key to the metre of any covered line. CC BY 4.0, with Chamberlain's request that substantial use cite him and the site.
- `ig-cyprus` — The Cypriot syllabary fascicle of Inscriptiones Graecae (IG XV 1,1, ed. Artemis Karnava and Massimo Perna with Markus Egetmeyer, Berlin 2020): 593 inscriptions from ancient Cyprus — Amathus, Kurion and Marion — written in the Cypriot syllabic script between the archaic period and the end of the fourth century BCE. Most records are Greek in its Arcadocypriot dialect (dedications, funerary texts, coin legends of the city kingdoms); eighteen are Eteocypriot, the island's only partly interpreted pre-Greek language, including the Amathus Greek–Eteocypriot bilingual. Each record carries the edition's reading text in transliteration, an alphabetic-Greek transcription where the editors give one, and Hallof's German translation where present, with find place, date and object descriptions. Published by the Berlin-Brandenburg Academy's digital Inscriptiones Graecae under CC BY 4.0, each record asking a link back to its edition page.
- `lexica` — The classical reference desk: Liddell-Scott-Jones for Greek and Lewis & Short for Latin — 168,133 dictionary entries with resolved classical citations.
- `lila` — The Lemma Bank of LiLa ("Linking Latin", CIRCSE) — the Latin lemma spine: 215,102 canonical forms (lemmas and hypolemmas), each with part of speech and its attested orthographic variants ("eclypsans"/"eclipsans"), the linked-data backbone that ties Latin lexical resources to one another. CC BY-SA 4.0.
- `openmgh` — The Monumenta Germaniae Historica critical editions in TEI — the foundational scholarly editions of medieval Europe's historiography. The SS rer. Germ. series carries the classic narrative sources of the Frankish and German Middle Ages (Einhard's Life of Charlemagne, the royal annals, Widukind, Thietmar of Merseburg, Otto of Freising); the second wave adds the late-antique Auctores antiquissimi (Jordanes, Cassiodorus), the Merovingian historians and saints' lives (SS rer. Merov., around Gregory of Tours' world), imperial charters (Diplomata), Middle High German verse chronicles (Deutsche Chroniken), the investiture-contest polemics (Libelli de lite), and the Quellen zur Geistesgeschichte. Mostly Latin with a German lane; page-anchored citations against the printed editions. CC BY 4.0 from the digital MGH.
- `pedecerto` — Pedecerto — Digital Latin Metre (Udine / Ca' Foscari; Colombi, Mondin, Tessarolo): metrical scansions of the Latin verse corpus, 227,791 hexameter lines plus pentameters and other meters, each line carrying its meter, its dactyl-spondee pattern, and per-word syllable positions. CC BY-NC-ND 4.0.
- `perseus-greek` — The backbone of the Greek canon: Homer, Hesiod, the tragedians, Aristophanes, Herodotus, Thucydides, Plato, Aristotle, the orators, Plutarch, Galen and more. 650 of the 768 Greek editions carry an aligned English translation displayable side-by-side (`--parallel`, span-grouped with coverage labels).
- `perseus-latin` — Vergil, Ovid, Horace, Cicero, Caesar, Livy, Tacitus, Seneca and the rest of the PHI-derived canon. Latin folding (v→u, j→i) is applied at the search layer, so `iuvenis`/`juvenis`/`iuuenis` all resolve.
- `proiel` — Gold dependency treebanks of the earliest Indo-European Bible translations — Greek NT, Vulgate, Gothic, Classical Armenian and Old Church Slavonic, morphologically analyzed to the token.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `vulgate` — The complete Clementine Vulgate — the Latin Bible in canonical books, an OT and NT witness in the alignment hub.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Who quotes the opening of the Iliad?* — `nabu_parallels urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1`: The reception of μῆνιν ἄειδε across the library: Galen (De placitis), Aristotle's Ars Rhetorica, Sextus Empiricus (seven loci), Dio Chrysostom, a metrical handbook — each hit with the shared folded phrase as evidence and a urn to open.
- *What does LSJ say about this word, with citations I can open?* — `nabu_define λόγος (lang: grc)`: The LSJ entry with senses as structured text; citations of works this library holds carry resolved passage urns for nabu_show.

## Field semantics on this desk

- **A CTS urn names an edition.** `urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1`
  is textgroup.work.**edition**:citation. Within one source, each work keeps
  only its highest-numbered edition per language; across sources, the same work
  coexists in several editions (Perseus, First1KGreek, Diorisis, GLAUx, the
  treebanks) that are deliberately not merged. Two editions can disagree and
  both be right: cite the edition you quoted, not "the work".
- **Translations are documents.** English (and, for First1KGreek, Latin,
  German, Coptic) translations are ingested as their own edition urns
  (`…perseus-eng4`); `nabu_show` with `parallel: true` pairs them with the
  original within the same source. A translation is never evidence for the
  original's wording.
- **The text is the digitized edition verbatim.** No apparatus is modeled: a
  passage is the editor's constituted text, not a manuscript reading.
- **Search folds.** Diacritics, breathings and case fold, Greek final sigma
  folds to σ, Latin v/u and j/i merge. `μηνιν` reaches `μῆνιν`; quote the
  pristine form from `nabu_show`.
- **Lemma tiers.** The treebanks (`proiel`, `ud`) are gold. `diorisis`, `glaux`
  and `digiliblt` lemmas are silver — automatic, labeled with a `tier` key on
  each hit. Report gold and silver counts separately, and verify any silver
  lemma you build an argument on against the passage itself.
- **Morphology.** `morph` takes Universal Dependencies feature names
  (`case=dat,number=pl`, `tense=aor`) decoded from PROIEL positional tags, UD
  feats and AGDT postags. Where a treebank encodes a category the UD way the
  query must follow it (one Greek treebank writes the aorist as perfective
  aspect plus past tense). `morph` requires `lemma`.
- **Meter.** `meter`/`meter_pattern` keep only *scanned* lines: Latin from
  Pedecerto (codes like `H`, patterns like `DSDS`), Greek from Hypotactic
  (names like `dactylic hexameter`, patterns in `-`/`u`). The two pattern
  vocabularies differ. An unscanned line is unscanned, not prose.
- **Dates.** Greek CTS editions carry a `composition` date joined from the
  GLAUx or Diorisis work datings by TLG author.work id; edition headers yield
  `edition`-class print years, never the work's era. Use
  `date_basis: composition` for literary chronology.

## Conflation traps

- **Edition versus witness.** A Perseus text and a Diorisis or GLAUx re-edition
  of the same work are two documents; counts differ between them. Never add
  attestation counts across editions of one work.
- **LSJ and Lewis & Short citations.** `nabu_define` resolves a lexicon's
  citation to a held passage where it can, ignoring the edition the lexicon
  cited (LSJ cites older Perseus editions): the resolved urn is *a* text of the
  cited passage, not necessarily the one the lexicographer read. Unresolved
  citations keep their display text and a null urn.
- **Parallels are surface quotation.** `nabu_parallels` finds shared rare word
  sequences in the same language; it does not detect allusion across languages
  or paraphrase, and two editions of one work appear as two hits.
- **The Vulgate wears two hats** (Latin literature and scripture); the PROIEL
  Latin New Testament is a separate, treebanked witness.

## Licensing on this desk

Perseus, First1KGreek, the lexica, Diorisis and GLAUx are `attribution`
(CC BY-SA); the Vulgate is `open`. The treebanks `proiel` and most `ud` Greek and
Latin treebanks are `nc`, as are the Pedecerto scansions and Corpus Corporum;
GLAUx carries per-document `nc` overrides — read the class on each passage.

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
