---
name: nabu-cuneiform
description: "Use when searching, reading or citing Sumerian, Akkadian, Ugaritic, Hittite or other cuneiform material through the nabu MCP tools: ORACC, CDLI, eBL, ETCSL, the Copenhagen Ugaritic Corpus, Achemenet, TLHdig, the Oracc Sign List (nabu_signs, nabu_char). Covers the document/passage grain per corpus, ATF transliteration conventions and the index fold, composites versus exemplars, gold versus silver lemmas, period-band dating, sign-resolution statuses, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: cuneiform
  origin: hand-tuned
  sources: "achemenet cdli cigs cuc ebl edubba-overlay etcsl oracc osl rsti seal tlhdig ud wiktionary-akk wiktionary-hit wiktionary-sux"
---

# The Assyriologist — the `cuneiform` desk

The Assyriologist — Sumerian, Akkadian, Ugaritic, Hittite: the tablet world entire.

The cuneiform-culture shelves: Oracc and CDLI, ETCSL's Sumerian literature, eBL's fragments, the Copenhagen Ugaritic Corpus (alphabetic cuneiform), and TLHdig shared with the Hittitologist.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `achemenet` | Achemenet Babylonian — linguistically annotated Achaemenid-period texts (Helsinki) | attribution |
| `cdli` | CDLI — Cuneiform Digital Library Initiative (2023-10 bulk-dump snapshot) | attribution |
| `cigs` | CIGS — Cuneiform Inscriptions Geographical Site Index (gazetteer instrument) | attribution |
| `cuc` | CUC — Copenhagen Ugaritic Corpus (CACCHT/DT-UCPH, Text-Fabric tf/0.2.8) | nc |
| `ebl` | eBL Fragmentarium — Electronic Babylonian Library transliterated fragments (Zenodo 10018951 snapshot, 2023-10-18) | nc |
| `edubba-overlay` | Edubba didactic overlay — hiero sign pedagogy (module) | attribution |
| `etcsl` | ETCSL — Electronic Text Corpus of Sumerian Literature (Oxford, revised edition 2006) | nc |
| `oracc` | ORACC — Open Richly Annotated Cuneiform Corpus | open |
| `osl` | OSL — the Oracc Sign List (cuneiform sign/value/codepoint instrument) | open |
| `rsti` | RSTI — Ras Shamra Tablet Inventory (U. Chicago CORPUS/OCHRE; the inscribed objects of Ugarit and Ras Ibn Hani) | nc |
| `seal` | SEAL — Sources of Early Akkadian Literature | research_private |
| `tlhdig` | TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Beta 0.3, Zenodo 20328284) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `wiktionary-akk` | Wiktionary Akkadian — kaikki.org machine-readable extract | attribution |
| `wiktionary-hit` | Wiktionary Hittite — kaikki.org machine-readable extract | attribution |
| `wiktionary-sux` | Wiktionary Sumerian — kaikki.org machine-readable extract | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `achemenet` — Linguistically Annotated Achemenet Babylonian Texts (Alstola, Sahala, Valk & Ong, University of Helsinki): 2,830 legal and administrative documents and letters of Achaemenid-period Babylonia (550–330 BCE) — the Murašû firm's archive from Nippur, Eanna temple records from Uruk, the Sippar texts of CT 55 and Jursa's Bēl-rēmanni, and Strassmaier's editions from the reigns of Cyrus, Cambyses and Darius. Akkadian (Late Babylonian) in Oracc-style transliteration, with lemmas, parts of speech and English glosses on every word. CC BY 4.0.
- `cdli` — The Cuneiform Digital Library Initiative — the field's universal catalog of cuneiform artifacts: 353,283 objects with curatorial metadata (period, genre, provenience, collection), of which 135,255 carry ATF transliterations totaling about 2.19 million lines, spanning proto-cuneiform and proto-Elamite through Sumerian, Akkadian and Eblaite, many lines with inline English translations, plus concordances to BDTNS and to composite texts. Freely reusable under CDLI's open terms, with attribution to CDLI requested for substantial reuse.
- `cigs` — The Cuneiform Inscriptions Geographical Site Index — the cuneiform world's site gazetteer, built at Uppsala University's "Geomapping Landscapes of Writing" project and published through CDLI's own journal. 597 archaeological sites of the cuneiform sphere (Mesopotamian, Anatolian, Levantine, Iranian tells), each with WGS84 coordinates and a four-tier accuracy grade, ancient and transcribed toponyms with multilingual name forms, and per-site identifiers in Pleiades, GeoNames, OpenStreetMap and CDLI's own provenience registry — a crosswalk hub for exactly the sites the tablet corpora name. Nabu derives it into the place index and its crosswalk assertions into the place crosswalk. CC BY 4.0, distributed as one versioned CSV on Zenodo.
- `cuc` — The Copenhagen Ugaritic Corpus (CACCHT project, University of Copenhagen, with collaborators) — the Ugaritic corpus in annotated form: 279 tablets, 7,616 lines, 27,770 words and 146,017 signs, cited by KTU number with the corpus's own tablet, column and line scheme. The consonantal transliteration carries a per-sign text-critical layer — restorations, excisions, damage and certainty marks — alongside the Ugaritic cuneiform signs themselves. CC BY-NC 4.0.
- `ebl` — The eBL Fragmentarium — the Electronic Babylonian Library (LMU Munich, Enrique Jiménez et al.): transliterations of the cuneiform tablet fragments held in museum collections, foremost the Kuyunjik and Babylon collections — 23,289 fragments in eBL-ATF, mostly Akkadian with a Sumerian minority, many carrying genre classifications, period labels, museum data, and inline English, German, or Arabic translations. CC BY-NC-SA 4.0 per the project's data paper.
- `edubba-overlay` — The sister school's curated hieroglyph pedagogy — the didactic layer Edubba (edubba.ac) teaches its Hieroglyphs 101/102 courses from, read back into the library's Egyptian sign card. For each Gardiner sign it carries the one-word didactic keyword, the iconic identification after Gardiner's Sign List, the sound or sense gloss as taught, a certainty grade (textbook-standard vs origin-debated — the latter never presented as fact), the signs learners confuse it with, the teaching chapter, and a deep link into the school's codex sign pages. Authored by the Edubba project against Allen and Gardiner; CC BY-SA 4.0 with the school's attribution line.
- `etcsl` — The Electronic Text Corpus of Sumerian Literature (Oxford; revised edition, completed 2006): composite editions of the Sumerian literary corpus — 394 compositions, among them the ancient literary catalogues, with 381 paired English prose translations. The Sumerian is hand-lemmatized throughout: citation form, word class, and English gloss on some 170,000 tokens. CC BY-NC-SA 3.0.
- `oracc` — The founding dream: Nabu's own tablets. Fetched as per-project zips over HTTP (the first non-git source; full attic/retention parity, TLS chain vendor-fixed) from a menu of 144 public projects. The **English translation layer** ships 8,911 `-en` sibling documents, so `show <tablet> --parallel` renders SAA letters like the Homers — transliteration beside the running English, line-aligned.
- `osl` — The Oracc Sign List (Veldhuis & Tinney) — the field's reference registry of cuneiform signs: 3,241 sign records with names, readings by language (11,278 value tokens), variant forms, Unicode codepoints and component sequences, and concordances to the standard print sign lists (MZL, LAK, aBZL, HZL, and others). CC0 — public domain.
- `rsti` — The Ras Shamra Tablet Inventory (University of Chicago OCHRE/CORPUS; M. Prosser, D. Pardee et al.) — the complete inventory of inscribed objects from Ugarit (Ras Shamra) and Ras Ibn Hani: over 5,000 records carrying RS/RIH excavation numbers, museum numbers, findspots, script and language, dimensions, and the KTU/CTA/UT concordances Ugaritologists actually use. Chiefly Ugaritic and Akkadian, with Hurrian, Egyptian, and others represented; a small set of records also carries full text editions in parallel transliteration, phonemic rendering, Ugaritic cuneiform, and translation. CC BY-NC-SA 4.0.
- `seal` — SEAL, Sources of Early Akkadian Literature (Michael P. Streck and Nathan Wasserman; Hebrew University of Jerusalem and Leipzig), the edition of record for Akkadian literature of the third and second millennia BCE. It covers epics and myths (among them the Old Babylonian Gilgameš witnesses), hymns, prayers, incantations, love lyrics and wisdom. About 400 texts with online transliterations are held, each cited by its fixed SEAL number and read line by line in the transliteration's own numbering (obverse, reverse, column), with the English translation, genre, period, provenance and bibliography alongside. The sister series on the same site are not included. Held under a personal research grant from N. Wasserman (2026) on CC BY-NC-ND terms: text only, local use, attribution on display, never redistributed.
- `tlhdig` — TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Hethitologie-Portal Mainz): the Hittite corpus, covering more than 98% of published cuneiform fragments from the Hittite tablet collections in transliteration — 23,937 per-manuscript documents organized by CTH number, with line-grain transliteration, Unicode cuneiform, and candidate morphological analyses. Predominantly Hittite, with Akkadian, Hurrian, Hattic, Luwian, Sumerian, and Palaic passages. CC BY 4.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `wiktionary-akk` — English Wiktionary's Akkadian lexicon, as extracted by kaikki.org (wiktextract, Tatu Ylönen): about 1,350 entries with sense glosses, romanized headwords (šarrum "king"), etymologies and descendant trees. Some 540 entries are headed by cuneiform Sumerograms, which lets their senses attach to the cuneiform sign cards. The descendant trees record borrowings onward, such as ṭuppum into Elamite and the Aramaic, Arabic and Hebrew loans, and Sumerian entries that point into Akkadian land here. CC BY-SA and GFDL, as Wiktionary.
- `wiktionary-hit` — English Wiktionary's Hittite lexicon, as extracted by kaikki.org (wiktextract, Tatu Ylönen): about 480 entries with sense glosses, etymologies and descendant trees. Most entries (some 414) are headed in cuneiform (𒉿𒀀𒋻 wātar "water"), so their senses attach to the cuneiform sign cards beside the Hittite tablet corpus. About a hundred are romanization pointers. The descendant trees record borrowings such as the Hittite-to-Akkadian lane. CC BY-SA and GFDL, as Wiktionary.
- `wiktionary-sux` — English Wiktionary's Sumerian entries in the kaikki.org machine-readable extraction (wiktextract, Tatu Ylönen): 2,499 entries, more than half headed by the cuneiform glyphs themselves — sense glosses, romanized readings, and etymology sections for the classical Sumerian vocabulary, with descendant trees recording which words Akkadian borrowed (𒊬 sar taken as kirûm 'orchard'). The community lexicon that complements the sign lists: where the Oracc Sign List says what a sign can read, these entries say what the words mean. CC BY-SA and GFDL, dual-licensed with Wiktionary.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Attestations of šarru 'king' — as lemma, not spelling.* — `nabu_search (lemma: šarru, lang: akk)`: Logographic LUGAL spellings resolved through ORACC's lemmatization — the first hits are the Cyrus Cylinder's opening lines, each with the surface form shown beside the lemma.

## Field semantics on this desk

- **Document and passage per source.** `oracc`: one text per document — a
  P-number is a physical artifact, a Q-number a *composite* (a reconstructed text
  assembled from several exemplars); a passage is one tablet line
  (`urn:nabu:oracc:<project>:<P/Q>:<line label>`, subprojects joined with `-`).
  `cdli`: one P-number artifact, passages addressed object/face/column/line;
  about two hundred thousand catalog records carry no transliteration at all
  (`text_layer: none`) — metadata-only documents, not empty texts. `ebl`: one
  museum-numbered fragment. `etcsl`: one composite literary text. `cuc`: one
  KTU tablet, passages `<column>.<line>`. `achemenet`: one text as a single
  passage (no line grain upstream). `tlhdig`: one manuscript, passages by line.
  `rsti`: inventory records of Ugarit's inscribed objects, nearly all without
  text.
- **Passage text is transliteration as the source ships it.** ORACC keeps its
  Unicode ATF forms (`{d}`, subscript indices, š ṣ ṭ); CDLI keeps C-ATF ASCII
  (`sz`, `s,`, `t,`); ETCSL keeps its own ASCII (`c` = š, `j` = ĝ); TLHdig marks
  damage with `[ ]`, `⌈ ⌉`, `⟦ ⟧`, `⟨ ⟩` and determinatives with `°…°`; CUC marks
  illegible signs `x`. Cuneiform characters, where held, ride annotations.
- **The index fold opens sign joins.** For `akk` and `sux`, hyphens, dots and
  determinative braces become spaces and subscript digits become ASCII, so every
  sign reading is its own token: `{d}amar-{d}suen` is searched as `d amar d suen`,
  and a determinative sits between the signs it classifies. Marks on š ṣ ṭ fold
  away — but there is **no** `sz`→`š` mapping in the index, so a CDLI line
  written `szar-rum` does not answer `šarrum`. Search both spellings. Hittite
  has only the generic fold: type it syllabified and hyphenated (`ne-pi-ša-aš`).
- **Language is the majority tag; the details ride the tokens.** An ORACC
  document's `language` is the majority base subtag of its words (an Old
  Babylonian dialect tag folds to `akk`); per-word tags, logogram languages and
  Emesal ride token annotations and the lect axis. TLHdig assigns language per
  *line* (Hittite, Akkadian, Sumerian, Hurrian, Hattic, Luwian, Palaic); a
  document's tag is only its majority.
- **Lemmas.** ORACC lemmatization (citation form, guide word, sense, part of
  speech) and ETCSL's are gold. TLHdig and Achemenet lemmas are silver
  (upstream-automatic; TLHdig lemmatizes only its disambiguated words). CDLI and
  eBL contribute no lemmas. ORACC carries no inflectional morphology, so `morph`
  never matches it. A `lemma` search for `šarru` finds logographic LUGAL
  spellings a text search cannot.
- **Translations.** ORACC English translations are sibling documents (`…-en`)
  aligned by line label: `nabu_show` with `parallel: true`. ETCSL English siblings
  are paragraph-grain, not line-grain. CDLI and eBL translations are per-line
  annotations, not documents.
- **Sign identity.** `nabu_signs` resolves ATF token by token through the Oracc
  Sign List: `deterministic` (one sign), `qualified` (an explicit value(SIGN)
  form), `ambiguous` (all candidate signs listed — choose with evidence, never
  silently), `no-codepoint` (resolved, honestly unencoded in Unicode),
  `broken`, `unknown` (not in the sign list). ETCSL romanization is applied
  automatically for ETCSL urns. `nabu_char` serves the sign card (values,
  list numbers, variant forms, corpus counts).

## Conflation traps

- **One tablet, several editions.** The same P-number can be a CDLI document and
  an ORACC document, and ORACC re-edits some tablets across projects; these are
  distinct urns, never merged. The ORACC Sumerian literary corpus and ETCSL are
  two deliberately separate editions of overlapping compositions. Cite the
  edition you read, and count tablets by P-number, not by urn.
- **Composite versus exemplar.** A Q-number composite (and every ETCSL text) is
  a modern reconstruction across manuscripts; it has no single findspot or
  artifact date. Do not attribute a composite's reading to a particular tablet.
- **Dates are typed and coarse.** ORACC and CDLI dates come, in order of
  preference, from the stated date of origin or regnal formulas, then the
  accounting period, then the period label mapped to a year band (Ur III,
  Old Babylonian, Neo-Assyrian …; precision `period`). A period band is a
  convention, not a dating of the tablet. Standard Babylonian has no band and
  stays undated. ETCSL, TLHdig and CUC carry no timeline rows.
- **Sender is not findspot.** For State Archives of Assyria letters, the sender's
  location is a separately labeled place row, never the find place. CDLI's
  place is upstream provenience verbatim.
- **Old Persian rides this desk.** The Achaemenid trilinguals' Old Persian
  column (`peo`) and Elamite sit in ORACC and CDLI; the Iranian desk shares
  them.
- **CDLI is a dated snapshot.** The held CDLI dump is a 2023 bulk snapshot; newer
  upstream readings are not reflected.

## Licensing on this desk

ORACC's in-scope projects are CC0 (`open`), its English translations
`attribution`; CDLI is a bespoke open grant held as `attribution`; TLHdig and
Achemenet are `attribution`. ETCSL, CUC, RSTI and eBL are `nc` (eBL because its
upstream statements conflict and the stricter reading is held). SEAL (early
Akkadian literature) is `research_private` under a personal grant from its
editor (2026-08-30): it is excluded unless `include_restricted: true`, and must
never be redistributed — local research use only, cited by SEAL number.

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
