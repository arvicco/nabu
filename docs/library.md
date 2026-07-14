# The Library — content review

**As of 2026-07-14** (post Phase 18, branch phase-18). Live totals:
**170,684 documents / 4,267,213 passages** across the 25 **synced** sources
(20 corpus sources carrying documents + 5 reference sources — lexica,
bosworth-toller, mw, wiktionary-cu, wiktionary-recon — carrying dictionary
entries only), plus **450,092 dictionary entries** on the reference shelf
(twelve dictionaries, including Monier-Williams and the seven
reconstruction shelves), and **2,852,069 gold lemma rows in 15 languages**.
The three Phase-17 adapters (coptic-scriptorium, edh, mw) are synced and
live (§8f–§8g, §8c). Three further sources are **registered but unsynced**
(`iecor`, `liv`, `edl` — Phase 18 adapters, all `enabled: false` awaiting
owner-fired first syncs; §8h). The code-per-language map lives in
[languages.md](languages.md).

This is a living document. Numbers are read from the live catalog
(`sqlite3 db/catalog.sqlite3 "PRAGMA query_only=ON; …"` — the WAL-safe
read-only convention, ops §10), not estimated. See §10 for the review
cadence that keeps it truthful.

---

## 1. Classical Greek literature

| | |
|---|---|
| **Category** | Canonical literary texts: epic, drama, historiography, philosophy, oratory, medicine |
| **Language** | Ancient Greek (`grc`), polytonic; aligned English (`eng`) |
| **Period** | Archaic through Imperial — Homer (8th c. BCE) to roughly 3rd c. CE |
| **Size** | 768 Greek docs + 650 English editions = 1,418 docs / 394,706 passages |
| **Source** | `perseus-greek` (Perseus Digital Library canonical-greekLit), license: `attribution` (CC BY-SA) |
| **Metadata** | CTS URNs (`urn:cts:greekLit:tlg…`), work/edition hierarchy, canonical citation schemes (book.line, Stephanus pages, etc.), TEI EpiDoc structure preserved as passage paths |

The backbone of the Greek canon: Homer, Hesiod, the tragedians, Aristophanes,
Herodotus, Thucydides, Plato, Aristotle, the orators, Plutarch, Galen and more.
650 of the 768 Greek editions carry an aligned English translation displayable
side-by-side (`--parallel`, span-grouped with coverage labels).

**Research uses:** close reading with facing translation; citation-precise
quotation (ranges like `:1.1-1.32` resolve natively); philological search with
Greek-aware folding (final sigma, diacritics); intertext hunting across the
canon; source-checking quotations found in later literature.

## 2. Post-classical Greek (First Thousand Years)

| | |
|---|---|
| **Category** | Later Greek prose: technical, scientific, theological, historiographical, paradoxographical |
| **Language** | Ancient Greek (`grc`); aligned English (`eng`) |
| **Period** | Mostly Hellenistic through Late Antique — 3rd c. BCE to ~6th c. CE |
| **Size** | 1,088 Greek docs + 41 English editions = 1,129 docs / 256,480 passages |
| **Source** | `first1k-greek` (Open Greek & Latin First1KGreek), license: `attribution` |
| **Metadata** | CTS URNs, same EpiDoc parser family as Perseus, section-level citations |

The long tail Perseus doesn't cover: Athenaeus, Philo, church fathers,
grammarians, scholia, minor historians, medical and mathematical writers.
Complements §1 with the texts scholars actually struggle to find in searchable
form. English coverage is thin (41 editions) but includes section-aligned
pieces like Palaephatus' De Incredibilibus.

**Research uses:** reception history (how classical authors were quoted and
reworked); patristics; history of science and medicine; lexicography of
post-classical Greek; locating fragments and testimonia preserved only in
later compilers.

## 3. Classical Latin literature

| | |
|---|---|
| **Category** | Canonical Latin literature: epic, lyric, drama, historiography, oratory, philosophy, letters |
| **Language** | Latin (`lat`); aligned English (`eng`) |
| **Period** | Republican through Imperial — Plautus (3rd–2nd c. BCE) to Late Antiquity |
| **Size** | 353 Latin docs + 181 English editions = 534 docs / 391,799 passages |
| **Source** | `perseus-latin` (Perseus canonical-latinLit), license: `attribution` |
| **Metadata** | CTS URNs (`urn:cts:latinLit:phi…`), canonical citations (book.chapter.section, poem.line), includes legacy P4-TEI editions recovered via the P9-2 ladder (notably Livy, Ab Urbe Condita, in both Latin and English) |

Vergil, Ovid, Horace, Cicero, Caesar, Livy, Tacitus, Seneca and the rest of
the PHI-derived canon. Latin folding (v→u, j→i) is applied at the search
layer, so `iuvenis`/`juvenis`/`iuuenis` all resolve.

**Research uses:** same modes as §1 for the Latin side; prose rhythm and
formula studies via concordance; Livy + Caesar + Tacitus as a continuous
historiographical corpus; checking Latin quotations and mottos to their exact
locus.

## 4. Documentary papyri

| | |
|---|---|
| **Category** | Documentary texts: contracts, tax receipts, petitions, private letters, census returns, leases, court records |
| **Language** | Greek (`grc`, 57,901 docs), Coptic (`cop`, 2,047), Latin (`lat`, 1,425), Arabic (`ar`, 12), Demotic (`egy-Egyd`, 2) |
| **Period** | Ptolemaic to early Islamic Egypt — c. 300 BCE to 8th c. CE |
| **Size** | 61,389 docs / 921,248 passages (the largest shelf by passages; largest by documents until the EDH inscriptions arrived — §8g) |
| **Source** | `papyri-ddbdp` (Duke Databank of Documentary Papyri via papyri.info), license: `attribution` |
| **Metadata** | DDbDP identifiers (series.volume.number), Leiden-convention editorial markup preserved (restorations, cancellations — including the cancelled-⟦⟧ fallback class), fragment/side structure as passage paths |

The everyday written record of a millennium of Egypt: what people bought,
owed, sued over, and wrote home about. This is *documentary*, not literary —
the language is non-standard, formulaic in places, full of phonetic spellings,
and therefore a unique witness to living Greek (and the Coptic and Arabic
transitions).

**Research uses:** social and economic history (prices, wages, taxes, land
tenure); onomastics and prosopography; vernacular/koine linguistics (real
misspellings = real phonology); legal history; formula studies across
centuries (concordance shines here); everyday-life color for any narrative
about Greco-Roman Egypt.

## 5. Sanskrit corpus

| | |
|---|---|
| **Category** | Full breadth of Sanskrit literature: Vedic saṃhitās, epics, purāṇas, kāvya, drama, śāstra (philosophy, law, grammar, poetics), tantra, Buddhist and Jain texts, technical treatises |
| **Language** | Sanskrit in IAST romanization (`san-Latn`, 776 docs), plus stray Tibetan-transliteration, Tamil and English items |
| **Period** | Vedic (c. 1200 BCE) to early modern (18th c. CE) — the longest span of any shelf |
| **Size** | 780 docs / 703,068 passages (second-largest shelf by passages) |
| **Source** | `gretil` (GRETIL, Göttingen Register of Electronic Texts in Indian Languages, via TEI mirror), license: `nc` (CC BY-NC-SA — non-commercial research use; served over MCP with its license label) |
| **Metadata** | Four addressability rungs (attribute-cited divisions, `// Abbr_N //` in-text verse markers, xml:id citations, prose ordinals); collision-disambiguated URNs (`:b2`) preserve upstream numbering errors instead of hiding them; Vedic accents preserved (keep-`<orig>`) |

Rāmāyaṇa (18,761 verses), Mahābhārata-adjacent texts, Bhāgavata and other
purāṇas, Kālidāsa and the kāvya tradition, Brahmasūtra with commentaries and
sub-commentaries, dharmaśāstra, Nāṭyaśāstra, Dhvanyāloka with its commentary
layers (kārikā vs. vṛtti separately citable as `:DhvK.…`/`:DhvA.…`),
Buddhacarita, Gītagovinda, and — recovered by the P11-7 silent-skip audit —
the Mitākṣarā (the standard commentary on Yājñavalkya, 4,788 passages).
Only 4 of 784 upstream files remain unparsed: flat verse lists with no
numbering of any kind, genuinely unaddressable (and now loudly reported as
`unrecognized` in every sync's discovery line).

**Research uses:** Indology across every genre; commentary-tradition studies
(base text and commentaries interleaved but separately citable); Vedic accent
studies; comparative epic (alongside Homer in §1); history of Indian
philosophy through the sūtra + bhāṣya chains; searchable pada-level access to
texts that mostly exist as scanned books elsewhere.

## 6. Morphosyntactic treebanks

| | |
|---|---|
| **Category** | Gold-standard linguistically annotated corpora: lemma, morphology, dependency syntax per token |
| **Language** | Latin (`lat`), Greek (`grc`), Gothic (`got`), Classical Armenian (`xcl`), Old Church Slavonic (`chu`), Old East Slavic (`orv`), Vedic Sanskrit (`san`), Old English (`ang` — ISWOC, §8d) |
| **Period** | 5th c. BCE (Herodotus) through 17th c. CE (Avvakum) |
| **Size** | 73 docs / 175,644 passages across three sources: `proiel` (12 docs / 51,321), `torot` (40 / 33,085), `ud` (21 / 91,238) — plus `iswoc` (5 / 2,536, §8d) in the same family |
| **Sources** | PROIEL (frozen release), TOROT (Tromsø OCS/OES), ISWOC (Old English — §8d), Universal Dependencies (seven treebanks incl. Old East Slavic birchbark letters, Middle Russian RNC, and Ruthenian — the first two CC BY-SA/`attribution` via per-document override); PROIEL/TOROT/ISWOC/legacy-UD license: `nc` |
| **Metadata** | The gold lemma layer: `passage_lemmas` totals **2,852,069 rows in 15 languages** (lat 583k, orv 455k, grc 379k, san 190k, chu 123k, got 99k, ang 25k, xcl 18k from the treebank family; akk 361k, sux 171k + Hurrian/Ugaritic/Hittite scatter from ORACC gold — §8; sl 214k from goo300k — §8e; cop 233k from Coptic Scriptorium — §8f), searchable via `search --lemma` with per-language folding and suppletive-form support (affero → attulimus) |

Three families: PROIEL's parallel New Testament (Greek original + Latin
Vulgate + Gothic Wulfila + Classical Armenian + OCS Codex Marianus — five
versions of the same text, morphologically annotated) plus classical prose
(Herodotus, Caesar, Cicero); TOROT's Old East Slavic and OCS shelf (birchbark
letters, chronicles including the Kiev Chronicle, Domostroj, Avvakum,
Afanasij Nikitin); UD treebanks adding Thomas Aquinas (ITTB, the largest
Latin lemma pool), Vedic Sanskrit, and the Ruthenian (prosta mova) treebank
riding under `orv`.

**Research uses:** any lemma-based query (find every inflected occurrence of
a word regardless of form); historical/comparative linguistics across the
five-way parallel NT — the single best alignment laboratory in the library;
Slavic diachrony from OCS to Middle Russian; morphology-driven stylistics;
training/evaluation data if the local inference cluster takes on tagging
(improvements §3.1 plans to project lemmas onto the other 90% of the corpus).

## 7. Aligned English translations (cross-cutting layer)

| | |
|---|---|
| **Category** | Not a source — an alignment capability spanning §§1–3 (and, since the SAA crawl, §8) |
| **Size** | 873 English editions / ~230,000 passages on the classical shelves |
| **Coverage** | perseus-greek 650, perseus-latin 181, first1k-greek 41 (+1 GRETIL stray); plus 8,911 ORACC `-en` translation documents / 50,406 passages (§8) |

The highest-numbered English edition per work is auto-selected; `show
--parallel` renders original and translation span-grouped, with coverage
labels when the translation's citation grain is coarser than the original
(`eng [:1.1 — covers :1.1–:1.32]`). The same mechanism now pairs cuneiform
tablets with their crawled running English (§8).

**Research uses:** makes the Greek/Latin shelves readable to non-specialists;
translation-studies comparisons; quick orientation before committing to a
close reading; teaching materials.

---

## 8. Cuneiform (ORACC)

| | |
|---|---|
| **Category** | Tablets and inscriptions: administrative/economic records, royal inscriptions, state letters, lexical lists — plus their aligned English translations |
| **Language** | Akkadian (`akk`, 6,261 docs), Sumerian (`sux`, 5,905), proto-cuneiform (`qpc`, 601), English translations (`eng`, 8,911), plus a scatter of Hittite, Hurrian, Ugaritic, Aramaic from the lexical lists |
| **Period** | Proto-cuneiform archaic tablets (late 4th millennium BCE!) through the Neo-Assyrian empire (7th c. BCE) |
| **Size** | 21,692 docs / 385,243 passages across 33 configured projects (30 carry documents — riao/ribo/dcclt-jena are catalog hubs with no corpus): the **complete State Archives of Assyria** (saao saa01–saa21 + saas2), rinap1 (Tiglath-pileser III), etcsri (Ur III royal inscriptions), rimanum (Old Babylonian archive), blms, and the dcclt lexical-list family (main + ebla/nineveh/signlists) |
| **Source** | `oracc` (Open Richly Annotated Cuneiform Corpus), license: **CC0/public domain** (read per-project from upstream metadata, never hardcoded); crawled translation prose CC BY-SA → per-document `attribution` override |
| **Metadata** | One passage per tablet line (`o.1`, `r.5` — the citable unit of Assyriology); transliteration as text; upstream **gold lemmatization** (citation form, normalization, English guide word, POS, per-grapheme logogram language) in annotations and `passage_lemmas` — 532k Akkadian/Sumerian lemma rows (akk 361k, sux 171k) searchable today; translit folding strips determinatives/sign-joins for search |

The founding dream: Nabu's own tablets. Fetched as per-project zips over
HTTP (the first non-git source; full attic/retention parity, TLS chain
vendor-fixed) from a menu of 144 public projects. The **English translation
layer** (P13-4/P14-4 two-stage crawl of the official per-text HTML
fragments) ships 8,911 `-en` sibling documents, so `show <tablet>
--parallel` renders SAA letters like the Homers — transliteration beside
the running English, line-aligned.

**Research uses:** Assyriology proper (ration lists, year-names, royal
titulary, the full SAA state correspondence readable in facing English);
gold-lemmatized
Akkadian/Sumerian as the only professionally lemmatized shelves besides the
treebanks; comparative "epigraphic habit" studies alongside the papyri;
lexical-list traditions (dcclt) as the ancient world's own dictionaries —
including the multilingual lists that carry Hittite, Hurrian and Ugaritic
column entries.

## 8b. Biblical editions

| | |
|---|---|
| **Category** | Scripture editions serving the alignment hub (§9) |
| **Language** | Latin (`lat`), Greek (`grc`), English (`eng`) |
| **Size** | `vulgate`: 73 books / 35,809 verses (the complete Clementine canon, public domain). `sblgnt`: 27 books / 7,939 verses (SBL Greek NT, CC BY 4.0). `eng-web`: 84 books / 37,624 verses (World English Bible, public domain — the readable English witness, P11-8). LXX: no separate source — Swete's Septuagint lives in First1K (§2) and is hub-wired |
| **Metadata** | Native book.chapter.verse citations (`urn:nabu:vulgate:jon:2.1`); every verse a hub-alignable ref |

With these aboard, the NT hub registers **fifteen witnesses** (Greek NT,
Vulgate, Gothic, Armenian, PROIEL Marianus, West-Saxon Gospels, SBLGNT,
Clementine, WEB English, the four CCMH OCS codices — §8e — and, since the
2026-07-13 Coptic sync, the Sahidic and Bohairic NT — §8f); `align "MARK
2.3"` attests fourteen of them (per-witness verse coverage stays honestly
fragmentary), and `align "GEN 1.1"` opens the OT axis (Septuagint ↔
Vulgate ↔ English).
Rahlfs' LXX was honestly blocked on CATSS license terms — recorded in
02-sources.

**Research uses:** textual criticism across traditions; Vulgate as the
bridge between the classical Latin shelf and medieval reception; the NT as
the densest multi-language alignment laboratory in the library.

## 8c. Reference shelf (dictionaries)

| | |
|---|---|
| **Category** | Scholarly lexica and reconstruction dictionaries — entries, not passages (own tables, own `nabu define` / `nabu etym` surfaces) |
| **Size** | **450,092 entries** across twelve dictionaries: LSJ (Greek, 116,497) + Lewis & Short (Latin, 51,636) + **Bosworth-Toller** (Old English, 62,815, CC BY 4.0) + **Monier-Williams** (Sanskrit, 193,890, `nc`) + Wiktionary OCS (`wiktionary-cu`, 4,615) + the seven reconstruction shelves (`wiktionary-recon`: Proto-Germanic 5,717, Proto-West Germanic 5,551, Proto-Slavic 5,431, PIE 1,905, Proto-Indo-Iranian 799, Proto-Italic 745, Proto-Balto-Slavic 491) |
| **Metadata** | Folded-headword keying (diacritic-insensitive lookup, incl. æ/þ/ð→ae/th for Old English); betacode decoded; entry citations parsed and **resolved to in-catalog passages** where the cited work exists (μῆνις → Il. 1.1 as a live urn); glosses surface in `search --lemma` output; the reconstruction entries carry machine-readable **descendant trees** joined to attested gold lemmas (`dictionary_reflexes`) |

`nabu define λόγος` / `define virtus` / `define aethele --lang ang`, and
MCP `nabu_define` for AI-assisted reading. A leading `*` (`define *bogъ`)
scopes to the reconstruction shelves; `nabu etym` walks an attested lemma
up the proto-to-proto chain, and `nabu cognates` crosses that crosswalk
with the alignment hub (§9) — the comparativist loop closed on live data.
All of the Phase 16–17 extensions are **live** since the 2026-07-13 owner
syncs + rebuild: the reflex crosswalk (`dictionary_reflexes`) holds
**1,006,872 edges** across nine shelves, including wiktionary-cu's own
descendants sections (2,210 edges, the P16-5 rider) and Monier-Williams'
Gk./Lat./Goth. comparanda (3,250 edges — a second etym witness beside
kaikki). The P17-3 **multi-hop closure** (PIE \*per- → PBS → \*pьrstъ →
chu/orv in one walk) and the migration-010 **`borrowed`** flag with
per-edge "(loan)" rendering in `etym`/`cognates` are equally live. MW
lookup rides the SLP1↔IAST transcode (`define amsa` reaches aṃśa/aṃsa),
with citation tiers resolving RV./BhP. references to GRETIL urns at verse
grain. Phase 18 registers a third-witness tier — IE-CoR's expert-curated
cognate sets and the two LiLa Turtle shelves (LIV, de Vaan EDL) — shipped
in code, **none synced, no live rows** (§8h).

**Research uses:** the philologist's desk loop (passage → lemma →
definition → cited parallel passage) closed inside one tool; lexicographic
studies over the full entry set; comparative etymology from attested OCS,
Gothic, or Old English forms to their reconstructed roots and back down to
cognates the corpus actually attests.

## 8d. Old English

| | |
|---|---|
| **Category** | The OE axis (docs/oe-survey.md): poetry corpus + gold treebank + dictionary (§8c) |
| **Language** | Old English (`ang`), ca. 700–1150, West-Saxon and Anglian dialects |
| **Size** | `aspr`: 349 poems / 30,550 lines — the complete six-volume Anglo-Saxon Poetic Records (Beowulf, Exeter Book, Junius, Vercelli, Paris Psalter, Minor Poems), CC BY-SA → `attribution`. `iswoc`: 5 prose+gospel texts / 2,536 gold-annotated sentences (Ælfric's Lives, Apollonius, Chronicles, Orosius, West-Saxon Gospels), CC BY-NC-SA → `nc` |
| **Metadata** | ASPR: canonical printed line numbers as citations (`urn:nabu:aspr:A4.1:1` = Beowulf line 1), Cameron/DOE record slugs; ISWOC: PROIEL-family gold lemma+morphology (24,822 `ang` lemma rows), verse-cited Gospel of Mark = an **alignment-hub witness** (`align MARK 2.3` renders the West-Saxon) |

All three OE sources live (synced + flipped 2026-07-11); Bosworth-Toller
holds 62,815 entries on the reference shelf (§8c) — `define --lang ang`
with æ→ae/þ,ð→th folding works.

**Research uses:** OE philology with canonical citability; comparative
Germanic (Gothic ↔ OE ↔ ON gap visible); the many-witness Mark (§8b) as a
Germanic-inclusive alignment laboratory; lemma-driven OE vocabulary study
bridged to Bosworth-Toller definitions.

## 8e. Slavic & Slovenian shelves

| | |
|---|---|
| **Category** | The Slavic axis (docs/slavic-survey.md): OCS gospel manuscripts, the oldest Slovene text, Early Modern Slovenian print |
| **Language** | Old Church Slavonic (`chu`), Slovenian incl. its historical stages (`sl`), plus the Freising translation layers (`lat`, `eng`, `ger`, `ita`, `pol`) |
| **Period** | ~1000 CE (Freising Manuscripts) through 1899 (IMP print) |
| **Size** | `ccmh`: 19 docs / 28,786 passages — four gospel codices in Helsinki-ASCII transliteration (Zographensis, Marianus, **Assemanianus**, **Savvina kniga**), CC BY → `attribution`. `freising`: 27 docs / 2,037 lines — the Brižinski spomeniki in three aligned transcription layers + five modern translations, CC BY-ND → `research_private` (the first MCP-default-excluded source). `goo300k`: 89 docs / 8,397 passages — **gold-annotated** Early Modern Slovenian (1584–1899), the `sl` gold-lemma shelf (214k lemma rows). `imp`: 658 docs / 404,897 passages — the silver-annotated IMP print corpus, the library's fourth-largest shelf by passages (the EDH inscriptions, §8g, edge past it by ~1,400) |
| **Metadata** | CCMH: folio-line citations, hyphen-split words searchable whole; freising: per-layer parallel citation; goo300k/imp: CE year in the urn (`…:sigil-1584`) feeding the date axis (§9) — all 747 Slovene docs dated |

The four CCMH codices join the alignment hub (witnesses 10–13 of the NT)
and are the substrate of `align REF --collate` — a raw-token apparatus per
(language, script) group, the Helsinki-ASCII codices collated against each
other, the Cyrillic Marianus beside them honestly uncollated (the fold
cannot bridge the two transcription systems). Wiktionary-OCS and the
reconstruction shelves (§8c) complete the axis: богъ → \*bogъ → PIE.

**Research uses:** OCS textual criticism with a live apparatus; Slavic
diachrony continued past the treebanks (§6) into Early Modern print;
diachronic Slovene lexis over three centuries (`vocab --by-century`); the
Freising Manuscripts beside their OCS near-contemporaries.

## 8f. Coptic (Coptic Scriptorium)

| | |
|---|---|
| **Category** | Literary Coptic: the complete Sahidic and Bohairic New Testaments, monastic and patristic prose, hagiography, apophthegmata — with gold lemmas |
| **Language** | Coptic (`cop`), Sahidic and Bohairic dialects |
| **Period** | Roughly 3rd–10th c. CE, the Christian-Egypt corpus |
| **Size** | 482 docs / 74,169 passages — 482 of the 483 upstream corpora aboard (P18-1 coverage pass; the one remainder is an honest quarantine) |
| **Source** | `coptic-scriptorium` (Coptic Scriptorium, release v6.2.0, TT parser family), license: CC BY per document with source class `nc` (most-restrictive-wins) |
| **Metadata** | Upstream **gold lemmatization** — **233,020 `cop` lemma rows**, gold-lemma language **#15**; language-of-origin loan tags (the Greek layer inside Coptic); Wikification entities; manuscript-date axis rows (340 dated documents) |

Synced and flipped by the owner 2026-07-13 (the first sync attempt's unzip
failure re-run clean; P18-1 then lifted coverage from the initial 188
documents to 482). The Sahidic and Bohairic NTs attest in the alignment
hub as witnesses #14 and #15 (§8b), and `cop` — previously the library's
largest language with zero tooling — now joins `search --lemma`, `vocab`,
and the loan-layer questions the etym shelf asks.

**Research uses:** Coptic philology with gold lemma search; Sahidic ↔
Bohairic dialect comparison over the same verses (the hub renders both);
the Greek-loan stratum of Coptic as data; continuity with the 2,047
documentary Coptic papyri (§4) across the literary/documentary line.

## 8g. Latin inscriptions (EDH)

| | |
|---|---|
| **Category** | The third documentary genre: epitaphs, dedications, honorific and building inscriptions, milestones, instrumentum — the Roman epigraphic habit |
| **Language** | Latin (`lat`, 80,561 docs), Greek (`grc`, 1,290 — the bilinguals), plus 5 `und` (exotic-language residue, coded honestly) |
| **Period** | Roman Republic through Late Antiquity, empire-wide — provinces from Britannia to Arabia |
| **Size** | 81,856 docs / 406,281 passages — the largest shelf by documents (48% of the library) |
| **Source** | `edh` (Epigraphic Database Heidelberg), license: `attribution` (CC BY-SA 4.0); **`sync_policy: frozen`** — upstream archived 2021, this is a one-shot preservation snapshot (27 quarantines, triaged at gate 18: 26 lb-less inscriptions carried to P19, 1 malformed upstream XML, all baseline-anchored) |
| **Metadata** | The library's first **genre facets** (migration 009): `document_facets` live at **256,518 rows** (genre/province/material/object_type, `?`-certainty preserved in `raw`) behind `search --type/--province/--material`; **81,416 dated documents** on the axis (§9); persons prosopography in `metadata_json`; Leiden ⟦…⟧ rendering for every `del`; `fuzzy_index: true` |

Synced and flipped by the owner 2026-07-13. Inscriptions beside papyri
(§4) and tablets (§8) complete the documentary triangle, and the facet
axes make the epigraphic habit queryable: `search --type epitaph
--province Britannia --material marble` composes with the date/place
filters.

**Research uses:** Latin epigraphy proper (formulae, titulature, careers);
provincial and social history by facet (genre × province × material);
onomastics and prosopography at empire scale; the epigraphic habit as a
quantitative object; fragment search (`--fuzzy`) over damaged stones.

## 8h. Incoming shelves — Phase 18 adapters, registered, awaiting first syncs

Three Phase-18 deliverables are **shipped in code and registered
`enabled: false`**; none is a live shelf — they hold **no live rows**, and
every number below is a projection from the staged upstream data, not a
catalog count:

- **`iecor`** — IE-CoR (lexibank/iecor v1.2, CC BY 4.0, sha-pinned
  immutable Zenodo DOI): the expert-curated Indo-European cognacy matrix
  as a dictionary shelf — 4,981 cognate-set entries under the collective
  `ine` tag / 26,325 reflex rows (2,308 loan-flagged, feeding `borrowed`)
  projected, 1,799 of those edges landing on held gold lemmas; ~144
  language notes accrete into the ledger (the `nabu language` card layer's
  first programmatic writer). An independent third etymological witness
  beside kaikki and MW.
- **`liv`** — LIV-LOD (CIRCSE/LiLa, CC BY-SA 4.0 with publisher
  permission): 305 PIE verbal etymons with verbal stem types in the entry
  bodies / ~385 Latin reflex edges projected; first user of the new
  lila-ttl (Turtle) parser family.
- **`edl`** — de Vaan, *Etymological Dictionary of Latin* (CIRCSE/LiLa LOD
  skeleton, CC BY-NC-SA → `nc`, MCP-default-served with its label, never
  redistributed): 2,860 etymons / ~2,653 reflex edges across two shelves
  projected — the lat → Proto-Italic → PIE Leiden chains beside kaikki's.

## 9. Library-wide capabilities

- **Full-text search** with per-language folding (Greek final-sigma and
  diacritics, Latin u/v i/j, Old English æ/þ/ð, Slovene long-s, cuneiform
  determinative stripping, generic diacritic folding for IAST Sanskrit) —
  `bin/nabu search`, FTS5 under the hood.
- **Lemma search** (`search --lemma`) over the treebank shelf (§6), the
  ORACC gold layer (§8), goo300k (§8e), and Coptic Scriptorium (§8f) —
  **15 languages**;
  ranking-independent `urn:` filtering; hits carry dictionary glosses where
  the reference shelf (§8c) knows the lemma. **Morphology facets**
  (`--morph case=dat,number=pl`, P13-6) filter by gold morphology — one UD
  vocabulary façade over UD feats and PROIEL positional tags.
- **Proximity search** (`search A --near B [--window N]`, P14-8): TLG-style
  collocation probing, FTS5 NEAR over the folded forms, lemma-aware (the
  anchor expands to attested surface forms).
- **Fragment search** (`search --fuzzy FRAGMENT`, P16-4): substring
  matching anywhere in a passage, mid-word included — `']μηνιν αει['`
  typed straight off a damaged edition (brackets stripped, then the usual
  per-language folding). Character-trigram index scoped to the documentary
  shelves (`fuzzy_index: true` on papyri-ddbdp + oracc + edh — corpus-wide
  would cost ~15×). **Live in production**: **1,712,772 passages indexed**
  (fulltext.sqlite3 at 2.3 GB with the index aboard) — EDH joined the
  indexed scope at its 2026-07-13 sync (§8g) — and the BGU 6.1470 mid-word
  Odyssey demo runs against the real index.
- **Date/place axis** (P15-2, extended P16-3 and P17-2): `document_axes`
  (migration 008) dates and places **164,989 documents live** — EDH
  inscription dates (81,416, the largest contributor since that shelf's
  2026-07-13 sync), HGV for the papyri (60,923), ORACC catalogue/period/
  regnal dates (21,558), the Slovene goo300k/IMP year-suffixed urns (747),
  Coptic manuscript dates (340), and TOROT chronicle AM annals.
  `search --from/--to/--century/--place` scope by signed historical year
  (negative = BCE, no year 0) and provenance; `show` prints the axis line
  ("date: 292 CE · Oxyrhynchos"); `--century -7` reaches the Assyrian
  letters.
- **Document facets** (P17-2, migration 009): `document_facets`
  (genre/province/material/object_type, `?`-certainty preserved in `raw`)
  with `search --type/--province/--material` composing with the date/place
  filters. **Live at 256,518 rows** since the EDH sync + rebuild (§8g).
- **Alignment hub** (`align REF`, MCP `nabu_align`): one citation rendered
  across every witness of a registered work (`config/alignments.yml`) —
  the parallel NT (**fifteen registered witnesses**, §8b) and OT (Septuagint ↔
  Vulgate ↔ English); registry-driven, rebuild-safe, per-witness license
  labels. **Collation** (`align REF --collate [--base LABEL]`, P15-4) diffs
  the witnesses into a compact apparatus per (language, script) group,
  cross-script witnesses rendered undiffed and labelled honestly.
- **Intertext** (`nabu parallels URN`, MCP `nabu_parallels`, P15-1):
  passage-anchored quotation/echo discovery — query-time 4-gram phrase
  probes over the existing FTS index (zero new schema), rarity-weighted,
  elision-folded (Matthew 4:4 finds LXX Deuteronomy 8:3); gold-lemmatized
  anchors also get rare-lemma "echoes". `--batch SCOPE` (P16-1) mines a
  whole source or urn prefix and persists the hits as journal edges.
- **Formula mining** (`nabu formulas SCOPE`, P15-5): the same gram
  machinery pointed inward — repeated formulas within a corpus slice,
  ranked by count × length (Homer's ὣς ἔφαθ' 72×; `Beowulf maþelode`;
  `saga hwæt ic hatte`). `--batch SCOPE` (P16-2) persists each formula as
  a star of edges (hub = first locus, the gram riding each edge's detail).
- **The links graph** (`nabu links URN`, MCP `nabu_links`, P16-1/P16-2):
  the mined cross-reference graph read back — every batch-produced edge
  touching a urn, grouped by kind (parallel, formula, cognate), each with
  native evidence and a provenance footer naming the producer run (scope,
  params, code version, date). Edges live in their own journal
  (`db/links.sqlite3`, the third data temperature — architecture §15), so
  they survive `nabu rebuild` untouched; `show` grows a one-line
  `linked:` footer when edges exist. Seeded so far: **5,089 parallel**
  edges (Matthew anchors), **395 formula** edges (ASPR refrains as stars),
  and **360 cognate** edges (NT got×chu, per-edge meet detail).
- **Dictionary lookup** (`define LEMMA`, MCP `nabu_define`): §8c —
  including `define *proto-form` on the reconstruction shelves.
- **Etymology walk** (`nabu etym LEMMA`, MCP `nabu_etym`, P14): attested
  lemma → reconstruction(s) → the proto chain, with cognates and corpus
  attestation counts. The P17-3 multi-hop closure (chains through the four
  intermediate proto shelves) and the `borrowed` flag with "(loan)"
  rendering are **live**; the IE-CoR/LIV/EDL adapters (§8h) will add
  independent expert-curated witnesses at their first syncs.
- **Cognates in parallel** (`nabu cognates TARGET`, MCP `nabu_cognates`,
  P15-3): the hub × reflex-crosswalk join — verses where witnesses in ≥2
  languages use reflexes of the same root (got salt ~ chu соль at \*sḗh₂l;
  ~300 NT verses / 30 roots for got×chu, sub-second), each hit naming its
  meet shelf (a gem-pro meet for a Slavic word reads as a borrowing).
  `--batch WORK` (P16-2, journal migration 002) persists the whole-work
  map as cognate edges, the meet (`ref · root [shelf]`) riding each edge.
- **Vocabulary profiling** (`nabu vocab URN`, P14-3): lemma-frequency
  profile against the gold corpus — distinctive vocabulary by log-odds,
  hapax legomena; `--by-century` (P15-2) plots the dated corpus, or a
  word's diachrony, across centuries.
- **Language cards** (`nabu language CODE`, P18-4): the desk reference for
  every code the library surfaces — the 30 corpus languages and the
  **803-code** Wiktionary etymology universe the `etym` cognate lists
  expose (`gkm`, `zle-ort`, `zlw-opl`…). One card: name, family, curated
  context, live holdings (zero fields suppressed); unknown codes miss
  honestly with a family hint; ~0.2 s after migrations 012/013. Three data
  temperatures: a derived names census in the catalog (**currently empty —
  it fills at the owner's wiktionary parse-only resyncs; health surfaces
  the gap**), accumulated notes in the ledger (append-only, provenanced —
  the 183-entry curated seed from `config/languages.yml` is loaded live
  via `--seed`), and the live-count joins.
- **Starter shelf** (`nabu quickstart`, P18-2): the curated first-run set
  — sblgnt + proiel + iswoc + lexica, 693 MB measured, minutes to sync
  through the ordinary fetch → load → index path — ending with the first
  three commands (seven-witness `align`, lemma search, `define`).
  Idempotent; one source's failure never stops the rest; `--list` prints
  the set without syncing.
- **`--long` everywhere** (P15-8, house rule): every truncated list —
  vocab hapaxes, etym reflexes, align ranges, parallels evidence — has the
  same escape hatch.
- **Discovery accounting** (P11-7): every sync prints
  `discovery: N selected · M skipped-by-rule · K unrecognized` — silent
  ingestion gaps are structurally visible.
- **Citation-native retrieval**: `show <urn>` with range support
  (`:1.1-1.32`), suffix display by default, `--full-urn` for scripts.
- **Concordance** (`concord`): KWIC lines with fold-aware matching that maps
  hits back to pristine (accented) text.
- **Parallel display** (`show --parallel`): §7.
- **MCP server** (**10 read-only tools**: `nabu_search`, `nabu_show`,
  `nabu_concord`, `nabu_align`, `nabu_define`, `nabu_etym`,
  `nabu_parallels`, `nabu_cognates`, `nabu_links`, `nabu_status` — see
  `docs/mcp.md`): exposes the library to Claude and other MCP
  clients. Every passage carries `license_class` + `source` so quoting
  decisions are informed. All licensed shelves including `nc` are served;
  `research_private`/`restricted` are excluded by default with per-call
  `include_restricted: true` opt-in — the freising shelf (BY-ND → 27
  `research_private` documents, §8e) is the first source behind that gate.
- **Protection stack**: upstream deletions are attic'd, never propagated
  (`retired_upstream` documents stay searchable); content-hash ledger
  (`db/history.sqlite3`) survives rebuilds; rsync backup to mounted volume +
  restore drill (`rake ops:drill`) proves the collection is reconstructable.
- **Health**: trend rules (spike/collapse/creep/stale), golden-query replay
  (13 goldens), remote drift + license-baseline probes — with honest drift
  vocabulary (P15-7: `up=unpinned` when no baseline pin exists, never a
  fake "ok"; `health --backfill-pins` seeds pins from the ledger; P16-0:
  the license column stays silent on sources it never checked). A
  `license_watch:` registry key (P16-5) lets `health --remote` watch a
  source's upstream license page for changes — candidates are recorded
  commented-out in `config/sources.yml`, none enabled yet (owner decision).
  P18-7 folds the mechanical **postcondition invariants** into every
  `health` run: failed-run and partial-load surfacing, flag-vs-artifact
  and enabled-vs-populated mismatches, pending migrations, and a
  **quarantine baseline** in the ledger so only the delta from the audited
  anchor alarms (the EDH 27 are anchored; the standing papyri stubs go
  quiet). Its first contact with the live library correctly surfaced the
  two real pending items — among them the empty language-names census
  awaiting the wiktionary resyncs. An optional `sync --review CMD` hook
  (off by default) pipes each sync summary to an external AI reviewer.
- **Licensing split**: `attribution` shelf (Perseus ×2, First1K, papyri,
  EDH — ~99% of documents) is redistributable with credit; `nc` shelf
  (GRETIL, treebanks, MW, Coptic Scriptorium's stricter class) is
  non-commercial research use — fine for private/AI-assisted work, not for
  republishing. Both are served everywhere (CLI and MCP) with per-passage
  license labels.

## 10. Review plan

This document goes stale the moment a sync or a phase lands. Standing plan:

1. **Every phase gate** (before the PR): refresh the header totals and any
   table a packet touched; new source = new section. This is part of the
   gate's README-truthfulness pass — the orchestrator owns it. The public
   site (`site/`, P17-9) is refreshed in the same pass — its numbers are
   COPIED from this file and README with their as-of dates, never
   re-derived (contract: site/MAINTENANCE.md). Every gate also adds a
   dated News entry (`site/news/_posts/`, P19-3) distilled from the gate's
   worklog line; a gate that cuts a tagged release additionally runs the
   release rail (ops §12: CITATION.cff bump → tag → GitHub release →
   Zenodo DOI).
2. **After every owner-fired real sync**: re-read `bin/nabu status` and the
   per-source counts; update sizes if drift >1%. Cheap — one query per table.
3. **Quarterly full review** (next due **2026-10-08**): re-verify every
   number from the live db, re-examine the "research uses" claims against
   what actually got used (MCP query logs are a signal once they exist),
   prune sections describing capabilities that changed, cross-check against
   docs/improvements.md so the two documents don't diverge on what's planned
   vs. shipped.
4. **Trigger-based**: a license-baseline probe alarm (health §) or a
   quarantine-count change on any source obliges an immediate spot-update of
   the affected section.

Numbers are always read from the live catalog read-only; this file never
becomes the source of truth — it's the map, the catalog is the territory.
