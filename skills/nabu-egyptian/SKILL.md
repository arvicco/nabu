---
name: nabu-egyptian
description: "Use when searching, reading or citing Ancient Egyptian (hieroglyphic, hieratic, Demotic) or Coptic material through the nabu MCP tools: the TLA sentence corpora (aes, tla-hf), the AED word list and the Coptic lexicon, Coptic Scriptorium, the Elephantine papyri and the Unikemet sign card. Covers transliteration and fold conventions, text versus dataset grain, lemma ids, stage and script labels, typed dates, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: egyptian
  origin: hand-tuned
  sources: "aed aes ccl coptic-scriptorium edubba-overlay elephantine tla-hf ud unikemet"
---

# The Egyptologist — the `egyptian` desk

The Egyptologist — hieroglyphs to Coptic, one language across four millennia of script.

The Egyptian-Coptic continuum: the TLA corpora and word list (tla-hf, aes, aed), the Coptic lexicon with its egy-cop crosswalk, and Coptic Scriptorium.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `aed` | AED — Ägyptische Wortliste (TLA/BBAW dictionary export) | attribution |
| `aes` | AES — Ancient Egyptian Sentences (TLA/BBAW snapshot, January 2018) | attribution |
| `ccl` | Comprehensive Coptic Lexicon v1.2 (BBAW/DDGLC) + ORAEC & KELLIA egy↔cop etymologies | attribution |
| `coptic-scriptorium` | Coptic Scriptorium corpora (release v6.2.0) | nc |
| `edubba-overlay` | Edubba didactic overlay — hiero sign pedagogy (module) | attribution |
| `elephantine` | Elephantine — the Berlin ERC papyri and ostraca database | attribution |
| `tla-hf` | Thesaurus Linguae Aegyptiae — official Hugging Face datasets (Demotic v18 + Late Egyptian v19, premium) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `unikemet` | Unikemet — Unicode Egyptian Hieroglyph data (sign spine instrument) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `aed` — The Ägyptische Wortliste (AED) — the dictionary of Ancient Egyptian exported from the Thesaurus Linguae Aegyptiae (BBAW): 35,052 entries with headwords in Egyptological transliteration, German glosses throughout and English on 16,972, one part of speech per entry, 13,369 page citations of the Wörterbuch der ägyptischen Sprache, and 19,399 cross-references linking roots, compounds and successor forms. Entry ids are the TLA lemma ids, so the dictionary keys directly to TLA-lemmatized texts. CC BY-SA 4.0.
- `aes` — Ancient Egyptian Sentences (AES; Schweitzer, TLA/BBAW) — 101,796 lemmatized Ancient Egyptian sentences from 13,026 texts in 16 subcorpora: the Pyramid Texts, the Book of the Dead, Amarna, Ramesside inscriptions and letters, medical papyri, the literary canon, tomb and temple inscriptions, archive letters. Every word carries Unicode transliteration, hieroglyphic encodings and the Thesaurus Linguae Aegyptiae's gold lemmatization with fine morphology; nearly every sentence has an editor's German translation. A frozen January-2018 snapshot of the TLA database. CC BY-SA 4.0.
- `ccl` — The Comprehensive Coptic Lexicon v1.2 (BBAW and the FU Berlin DDGLC project, 2020) — 11,284 Coptic dictionary entries whose ids are the Coptic Dictionary Online C-ids, with dialect sigla (Sahidic, Bohairic, Akhmimic, Lycopolitan, Fayyumic and others), senses as German, English and French translation triples, 3,382 etymological notes, 123 marked loanword entries, and print citations of the standard dictionaries (Crum, CED, KoptHWb, DELC). CC BY-SA 4.0.
- `coptic-scriptorium` — Coptic Scriptorium corpora — the Sahidic and Bohairic New Testament plus monastic literature (Shenoute, Besa, apophthegmata), lemmatized and serving the alignment hub.
- `edubba-overlay` — The sister school's curated hieroglyph pedagogy — the didactic layer Edubba (edubba.ac) teaches its Hieroglyphs 101/102 courses from, read back into the library's Egyptian sign card. For each Gardiner sign it carries the one-word didactic keyword, the iconic identification after Gardiner's Sign List, the sound or sense gloss as taught, a certainty grade (textbook-standard vs origin-debated — the latter never presented as fact), the signs learners confuse it with, the teaching chapter, and a deep link into the school's codex sign pages. Authored by the Edubba project against Allen and Gardiner; CC BY-SA 4.0 with the school's attribution line.
- `elephantine` — The Berlin database of papyri and ostraca from Elephantine (Ägyptisches Museum und Papyrussammlung, ERC project "Localizing 4000 Years of Cultural History", Verena Lepper): 10,744 objects documenting four millennia of life on the island — Greek, Imperial Aramaic, Demotic, Coptic, hieratic, Middle Egyptian, Arabic, and Phoenician among the languages, the Aramaic written in unpointed Hebrew script — in TEI editions with English translations, structured dating, and Trismegistos links. CC BY-SA 3.0 under each record's own grant.
- `tla-hf` — Sentence-grain extracts from the Thesaurus Linguae Aegyptiae (BBAW and the Saxon Academy, Leipzig): 13,383 Demotic sentences — the only bulk Demotic dataset anywhere — and 3,606 Late Egyptian sentences with a Unicode hieroglyph layer, all fully lemmatized with Leiden Unified transliteration, part-of-speech tags, glossing, German translations, and dating ranges. CC BY-SA 4.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `unikemet` — Unicode's normative Egyptian Hieroglyph data file — the Egyptian analogue of Unihan. 5,067 signs at Unicode 17.0, spanning the basic hieroglyph block and Extended-A: each sign carries a Gardiner-plus catalog code, an English description of what the glyph depicts, its function (phonemogram, logogram, classifier), phonetic value, a core-vs-legacy flag, and concordances into JSesh, Hieroglyphica, and the IFAO catalogue. Compiled by Unicode's Script Ad Hoc group from Egyptological sources, it is the first machine-readable sign list to cover the full extended repertoire rather than Gardiner's classic 763. Nabu reads it as the sign spine behind the Egyptian character card. Unicode License V3 (MIT-style), one flat versioned file.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Search the Egyptian sentences for nfr.* — `nabu_search nfr (lang: egy)`: AES hits in Egyptological transliteration (tomb inscriptions, offering lists) — ꜣ and ꜥ fold to a, so an ASCII query reaches them.

## Field semantics on this desk

- **Grain differs by source — check it before counting.** An `aes` document is one
  TLA text and a passage one sentence (`urn:nabu:aes:<subcorpus>:<text>:<sentence>`).
  A `tla-hf` document is a whole *dataset* (Demotic, Earlier Egyptian, Late
  Egyptian — one document each, plus German siblings), its passages sentences
  numbered by line because upstream ships no text ids: a `tla-hf` "document count"
  says nothing about texts. `elephantine` works at object/line grain, Coptic
  Scriptorium at book/verse grain (Bible chapters merged into books).
- **Passage text is transliteration, not hieroglyphs.** `aes` and `tla-hf` store
  Unicode Egyptological transliteration (Leiden Unified, space-separated tokens);
  the hieroglyphic encodings ride token annotations (`aes`: Manuel de Codage,
  Gardiner-code sequences, decoded Unicode, and a per-sign inventory; `tla-hf`:
  Unicode hieroglyphs for Earlier and Late Egyptian only — Demotic has none).
  Search the transliteration.
- **The Egyptian fold is narrow.** ꜣ and ꜥ fold to `a`, ʾ is dropped, and dotted
  and underlined consonants (ḥ ḫ ẖ š ṯ ḏ) lose their marks, so `nfr`, `hm`,
  `aa` reach the edited forms. The fold assumes the yod is written `j`; a source
  that writes another yod glyph will not answer a `j` query, so try both
  spellings before concluding absence.
- **Two transliteration fields, two conventions.** In `aes`, the passage text is
  the written form (morpheme boundaries with commas, `ṯḥn,t`), while the lemma
  form uses dots (`ṯḥn.t`). Search the written form; search `lemma:` the lemma
  form. Editorial brackets and half-brackets stay inline in the text.
- **Lemmas are TLA lemma ids and gold.** `aes` and `tla-hf` carry
  editor-verified TLA lemmatization (gold). `tla-hf` lemma pairs carry a `d`/`dm`
  prefix for Demotic. The `aed` dictionary's entry urns prefix the id with
  `tla` (`urn:nabu:dict:aed:tla550034`) while token annotations carry the bare
  number — when moving from a token to the word list, query `nabu_define` with
  the transliterated headword, or prefix the id yourself.
- **Stage is a facet, not the language tag.** Every Egyptian passage is `egy`;
  the stage (Old, Middle, New Kingdom, the late traditional register, Demotic)
  rides the document facets and the lect axis. The `aes` corpus called
  "Earlier Egyptian" in fact spans Old Kingdom to Roman-period texts; its latest
  band is classified as a traditional *register*, not a stage. Do not read the
  dataset name as a dating.
- **`egy-Egyd` names the artifact's script, not the held text.** Elephantine
  Demotic is tagged `egy-Egyd`, but the text you read is Latin-script
  transliteration; the `script` filter reaches it through the artifact-script
  lane.
- **Coptic: diplomatic text, normalized search.** Coptic Scriptorium stores the
  diplomatic bound-group reading and indexes the normalized word sequence;
  the fold drops the combining ⳿ and supralinear strokes. Dialect (Sahidic,
  Bohairic) is a facet and a lect (`cop/sah`, `cop/boh`). Lemmas are gold only
  on documents upstream marks checked; others carry automatic lemmas.
- **German translations have two codes.** `aes` siblings are `ger`, `tla-hf`
  siblings `deu`: pass the matching `parallel_lang` to `nabu_show`.

## Conflation traps

- **`aes` and `tla-hf` overlap.** `aes` is a frozen 2018 TLA snapshot at text
  grain; `tla-hf` is a later TLA release at sentence grain. The same sentence can
  appear in both, as can Pyramid Texts sentences in the UD Egyptian treebank. Count
  attestations per source and say so; never add the sources together as if
  independent.
- **Dictionary versus attestation.** An `aed` or `ccl` entry proves the word is in
  the lexicographic tradition, not that this library attests it. The Coptic
  lexicon's Egyptian etymologies point into `aed` and into a Demotic id space
  for which no dictionary shelf is held.
- **Dates are typed bands.** `aes` dates come from the TLA text headers
  (reign, dynasty, period or century precision) with four broad period envelopes
  as the fallback; `tla-hf` dates are per-sentence ranges; Elephantine dates are
  the edition's custom bounds. A period-band date is not a precise dating — report
  the precision with the range.
- **Sign card didactics are not philology.** `nabu_char` on a hieroglyph merges
  Unikemet's normative data with a teaching overlay; an overlay value graded
  `unclear` is a debated identification and must not be presented as fact.

## Licensing on this desk

Most of the desk is `attribution` (CC BY-SA). Coptic Scriptorium's source class is
`nc`, with per-document overrides to `attribution` on most documents — read the
class on each passage. Elephantine's per-record grant is CC BY-SA while the
project site states non-commercial terms; the library follows the in-file grant,
but a cautious reuser may prefer the stricter reading.

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
