# The Library — content review

**As of 2026-07-12** (post Phase 14, branch phase-14). Live totals:
**84,449 documents / 3,780,482 passages** across all 24 sources, plus
**248,616 dictionary entries** on the reference shelf (now including the
three reconstruction dictionaries), and **2,619,049 gold lemma rows in 14
languages**. The code-per-language map lives in
[languages.md](languages.md).

This is a living document. Numbers are read from the live catalog
(`sqlite3 -readonly db/catalog.sqlite3`), not estimated. See §10 for the
review cadence that keeps it truthful.

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
| **Size** | 61,389 docs / 921,248 passages (94% of all documents in the library) |
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
| **Language** | Sanskrit in IAST romanization (`san-Latn`, 770 docs), plus stray Tibetan-transliteration, Tamil and English items |
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
| **Language** | Latin (`lat`), Greek (`grc`), Gothic (`got`), Classical Armenian (`xcl`), Old Church Slavonic (`chu`), Old East Slavic (`orv`), Vedic Sanskrit (`san`) |
| **Period** | 5th c. BCE (Herodotus) through 17th c. CE (Avvakum) |
| **Size** | 70 docs / 170,279 passages across three sources: `proiel` (12 docs / 51,321), `torot` (40 / 33,085), `ud` (18 / 85,873) |
| **Sources** | PROIEL (frozen release), TOROT (Tromsø OCS/OES), ISWOC (Old English — §8d), Universal Dependencies (six treebanks incl. Old East Slavic birchbark letters + Middle Russian RNC — those two CC BY-SA/`attribution` via per-document override); PROIEL/TOROT/ISWOC/legacy-UD license: `nc` |
| **Metadata** | The treebank half of the lemma layer: `passage_lemmas` totals **1,917,694 rows in 12 languages** (lat 583k, grc 379k, orv 351k, san 190k, chu 123k, got 99k, xcl 18k from the treebanks; sux 128k, akk 45k + Hurrian/Ugaritic/Hittite scatter from ORACC gold), searchable via `search lemma:` with per-language folding and suppletive-form support (affero → attulimus) |

Three families: PROIEL's parallel New Testament (Greek original + Latin
Vulgate + Gothic Wulfila + Classical Armenian + OCS Codex Marianus — five
versions of the same text, morphologically annotated) plus classical prose
(Herodotus, Caesar, Cicero); TOROT's Old East Slavic and OCS shelf (birchbark
letters, chronicles including the Kiev Chronicle, Domostroj, Avvakum,
Afanasij Nikitin); UD treebanks adding Thomas Aquinas (ITTB, the largest
Latin lemma pool) and Vedic Sanskrit.

**Research uses:** any lemma-based query (find every inflected occurrence of
a word regardless of form); historical/comparative linguistics across the
five-way parallel NT — the single best alignment laboratory in the library;
Slavic diachrony from OCS to Middle Russian; morphology-driven stylistics;
training/evaluation data if the local inference cluster takes on tagging
(improvements §3.1 plans to project lemmas onto the other 90% of the corpus).

## 7. Aligned English translations (cross-cutting layer)

| | |
|---|---|
| **Category** | Not a source — an alignment capability spanning §§1–3 |
| **Size** | 873 English editions / ~238,000 passages |
| **Coverage** | perseus-greek 650, perseus-latin 181, first1k-greek 41 (+1 GRETIL stray) |

The highest-numbered English edition per work is auto-selected; `show
--parallel` renders original and translation span-grouped, with coverage
labels when the translation's citation grain is coarser than the original
(`eng [:1.1 — covers :1.1–:1.32]`).

**Research uses:** makes the Greek/Latin shelves readable to non-specialists;
translation-studies comparisons; quick orientation before committing to a
close reading; teaching materials.

---

## 8. Cuneiform (ORACC)

| | |
|---|---|
| **Category** | Tablets and inscriptions: administrative/economic records, royal inscriptions, state letters, lexical lists |
| **Language** | Sumerian (`sux`, 5,160 docs), Akkadian (`akk`, 1,101), proto-cuneiform (`qpc`, 601), plus a scatter of Hittite, Hurrian, Ugaritic, Aramaic from the lexical lists |
| **Period** | Proto-cuneiform archaic tablets (late 4th millennium BCE!) through the Neo-Assyrian empire (7th c. BCE) |
| **Size** | 6,876 docs / 191,712 passages across five projects: rimanum (Old Babylonian archive), etcsri (Ur III royal inscriptions), saao-saa01 (Sargon II state letters), rinap1 (Tiglath-pileser III inscriptions), dcclt (lexical lists) |
| **Source** | `oracc` (Open Richly Annotated Cuneiform Corpus), license: **CC0/public domain** (read per-project from upstream metadata, never hardcoded) |
| **Metadata** | One passage per tablet line (`o.1`, `r.5` — the citable unit of Assyriology); transliteration as text; upstream **gold lemmatization** (citation form, normalization, English guide word, POS, per-grapheme logogram language) in annotations and `passage_lemmas` — 173k Akkadian/Sumerian lemma rows searchable today; translit folding strips determinatives/sign-joins for search |

The founding dream: Nabu's own tablets. Fetched as per-project zips over
HTTP (the first non-git source; full attic/retention parity, TLS chain
vendor-fixed) from a menu of 144 public projects.

**Research uses:** Assyriology proper (ration lists, year-names, royal
titulary, the Sargon II state correspondence); gold-lemmatized
Akkadian/Sumerian as the only professionally lemmatized shelves besides the
treebanks; comparative "epigraphic habit" studies alongside the papyri;
lexical-list traditions (dcclt) as the ancient world's own dictionaries —
including the multilingual lists that carry Hittite, Hurrian and Ugaritic
column entries.

## 8b. Biblical editions

| | |
|---|---|
| **Category** | Scripture editions serving the alignment hub (§9) |
| **Language** | Latin (`lat`), Greek (`grc`) — English witness queued (P11-8) |
| **Size** | `vulgate`: 73 books / 35,809 verses (the complete Clementine canon, public domain). `sblgnt`: 27 books / 7,939 verses (SBL Greek NT, CC BY 4.0). LXX: no separate source — Swete's Septuagint lives in First1K (§2) and is hub-wired |
| **Metadata** | Native book.chapter.verse citations (`urn:nabu:vulgate:jon:2.1`); every verse a hub-alignable ref |

With these two, `align MARK 2.3` renders up to seven witnesses (Greek NT,
Vulgate, Gothic, Armenian, OCS, SBLGNT, Clementine) and `align "GEN 1.1"`
opens the OT axis (Septuagint ↔ Vulgate). Rahlfs' LXX was honestly blocked
on CATSS license terms — recorded in 02-sources.

**Research uses:** textual criticism across traditions; Vulgate as the
bridge between the classical Latin shelf and medieval reception; the NT as
the densest multi-language alignment laboratory in the library.

## 8c. Reference shelf (dictionaries)

| | |
|---|---|
| **Category** | Scholarly lexica — entries, not passages (own tables, own `nabu define` surface) |
| **Size** | **168,133 entries**: LSJ (Greek, 116,497) + Lewis & Short (Latin, 51,636), license CC BY-SA 4.0 (`attribution`) |
| **Metadata** | Folded-headword keying (diacritic-insensitive lookup); betacode decoded; entry citations parsed and **resolved to in-catalog passages** where the cited work exists (μῆνις → Il. 1.1 as a live urn); glosses surface in `search --lemma` output |

`nabu define λόγος` / `define virtus`, and MCP `nabu_define` for
AI-assisted reading. Bosworth-Toller (Old English, CC BY 4.0) is the
designed next occupant per the OE survey.

**Research uses:** the philologist's desk loop (passage → lemma →
definition → cited parallel passage) closed inside one tool; lexicographic
studies over the full entry set.

## 8d. Old English

| | |
|---|---|
| **Category** | The OE axis (docs/oe-survey.md): poetry corpus + gold treebank + (queued) dictionary |
| **Language** | Old English (`ang`), ca. 700–1150, West-Saxon and Anglian dialects |
| **Size** | `aspr`: 349 poems / 30,550 lines — the complete six-volume Anglo-Saxon Poetic Records (Beowulf, Exeter Book, Junius, Vercelli, Paris Psalter, Minor Poems), CC BY-SA → `attribution`. `iswoc`: 5 prose+gospel texts / 2,536 gold-annotated sentences (Ælfric's Lives, Apollonius, Chronicles, Orosius, West-Saxon Gospels), CC BY-NC-SA → `nc` |
| **Metadata** | ASPR: canonical printed line numbers as citations (`urn:nabu:aspr:A4.1:1` = Beowulf line 1), Cameron/DOE record slugs; ISWOC: PROIEL-family gold lemma+morphology (24,827 `ang` lemma rows), verse-cited Gospel of Mark = **alignment-hub witness #9** (`align MARK 2.3` now renders the West-Saxon) |

All three OE sources live (synced + flipped 2026-07-11); Bosworth-Toller
holds 62,815 entries — `define --lang ang` with æ→ae/þ,ð→th folding works.

### Incoming shelf (Phase 13, shipped awaiting owner syncs)

Seven sources registered `enabled: false`: **ccmh** (4 OCS gospel
manuscripts incl. Assemanianus + Savvina kniga, CC BY), **UD Ruthenian**
(rides the next `sync ud`), **28 new ORACC projects** (full SAA + riao/
ribo/blms/dcclt subprojects, ~159 MB) plus the **SAA English translation
crawl** (~250 MB stage 1 — `--parallel` for tablets), **goo300k** (gold
Early Modern Slovenian, 1584–1899) + **imp** (17.7M tokens, silver),
**wiktionary-cu** (4.6k OCS Wiktionary entries with Proto-Slavic/PIE
etymologies kept), and **freising** (the Brižinski spomeniki, ~1000 CE,
BY-ND → research_private — the first MCP-default-excluded source).

**Research uses:** OE philology with canonical citability; comparative
Germanic (Gothic ↔ OE ↔ ON gap visible); the nine-witness Mark as a
Germanic-inclusive alignment laboratory; lemma-driven OE vocabulary study
bridged to definitions once Bosworth-Toller loads.

## 9. Library-wide capabilities

- **Full-text search** with per-language folding (Greek final-sigma and
  diacritics, Latin u/v i/j, generic diacritic folding for IAST Sanskrit) —
  `bin/nabu search`, FTS5 under the hood.
- **Lemma search** (`search lemma:…`) over the treebank shelf (§6) AND the
  ORACC gold layer (§8) — 12 languages; ranking-independent `urn:`
  filtering; hits carry dictionary glosses where the reference shelf (§8c)
  knows the lemma.
- **Alignment hub** (`align REF`, MCP `nabu_align`): one citation rendered
  across every witness of a registered work (`config/alignments.yml`) —
  the parallel NT (up to seven witnesses) and OT (Septuagint ↔ Vulgate);
  registry-driven, rebuild-safe, per-witness license labels.
- **Dictionary lookup** (`define LEMMA`, MCP `nabu_define`): §8c.
- **Discovery accounting** (P11-7): every sync prints
  `discovery: N selected · M skipped-by-rule · K unrecognized` — silent
  ingestion gaps are structurally visible.
- **Citation-native retrieval**: `show <urn>` with range support
  (`:1.1-1.32`), suffix display by default, `--full-urn` for scripts.
- **Concordance** (`concord`): KWIC lines with fold-aware matching that maps
  hits back to pristine (accented) text.
- **Parallel display** (`show --parallel`): §7.
- **MCP server** (6 read-only tools: `nabu_search`, `nabu_show`,
  `nabu_concord`, `nabu_align`, `nabu_define`, `nabu_status` — see
  `docs/mcp.md`): exposes the library to Claude and other MCP
  clients. Every passage carries `license_class` + `source` so quoting
  decisions are informed. All licensed shelves including `nc` are served;
  only `research_private`/`restricted` (currently zero documents — a
  forward-looking privacy gate for the future ad-hoc pipeline) are excluded
  by default, with per-call `include_restricted: true` opt-in.
- **Protection stack**: upstream deletions are attic'd, never propagated
  (`retired_upstream` documents stay searchable); content-hash ledger
  (`db/history.sqlite3`) survives rebuilds; rsync backup to mounted volume +
  restore drill (`rake ops:drill`) proves the collection is reconstructable.
- **Health**: trend rules (spike/collapse/creep/stale), golden-query replay
  (13 goldens), remote drift + license-baseline probes.
- **Licensing split**: `attribution` shelf (Perseus ×2, First1K, papyri —
  ~99% of documents) is redistributable with credit; `nc` shelf (GRETIL,
  treebanks) is non-commercial research use — fine for private/AI-assisted
  work, not for republishing. Both are served everywhere (CLI and MCP) with
  per-passage license labels.

## 10. Review plan

This document goes stale the moment a sync or a phase lands. Standing plan:

1. **Every phase gate** (before the PR): refresh the header totals and any
   table a packet touched; new source = new section. This is part of the
   gate's README-truthfulness pass — the orchestrator owns it.
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
