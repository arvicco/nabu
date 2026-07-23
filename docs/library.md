# The Library — content review

**As of 2026-07-23** (post the P42 full rebuild — the first clean
derivation of the post-Arabic library; v1.2.0 cut the day before). Live
totals: **810,180 documents / 62,789,087 passages and 1,310,786
dictionary entries** across the **89 registry rows** — 83 corpus sources + 4 local
shelves + 2 feature modules, every corpus source enabled (OpenITI's
registry flip rides the P42 gate). The rebuild reconciled the
incrementally-grown catalog against clean derivation at −74 documents /
−18,896 passages (0.03%): re-parse quarantines under current parser
strictness (papyri +9 flagged by the drift monitor) and four rundata
URN collisions; per-source counts are byte-identical across the two
most recent full rebuilds. **Classical Arabic (`ara`, §8x) is now the largest language at 33.3M
passages** — the OpenITI load of 2026-07-22 evening — ahead of Literary
Chinese (13.2M); Persian (`fas`, 1.3M), Japanese (`jpn`, §8v) and
Middle High German (`gmh`, §8w) landed the same 48 hours. The reference shelf spans **56 dictionary
shelves** (§8c, §8h, §8j, §8k, §8m, §8o, §8q, §8s, §8t). The lemma
layer, censused fresh this date: **16,240,531 gold rows in 28
languages** — the Germanic wave added `gmh` (2.10M rows, instantly the
third-largest gold pool), `non`, `osx`, and, with the owner's same-day
`sync ud`, `is` (IcePaHC, 812K rows, straight in at #4) and `lzh`'s
first gold lane — plus **8,244,309 silver
rows in 8** (the CDLI/TLHdig/Diorisis honest tier — machine-suggested or
upstream-undisambiguated, always labelled). The four canonical-memory shelves (§8i) hold the owner's private
curation and acquisitions — their counts and contents stay out of public
documentation by rule. The code-per-language map lives in [languages.md](languages.md).

This is a living document. Numbers are read from the live catalog, not
estimated — via a `readonly: true` Sequel/sqlite3 session (the WAL-safe
read-only convention, ops §10; the `sqlite3` CLI now fails to open the
27 GB catalog, so the Ruby gem is the read path). See §10 for the review
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
| **Language** | Greek (`grc`, 57,912 docs), Coptic (`cop`, 2,063), Latin (`lat`, 1,425), Arabic (`ar`, 12), Demotic (`egy-Egyd`, 2) |
| **Period** | Ptolemaic to early Islamic Egypt — c. 300 BCE to 8th c. CE |
| **Size** | 61,414 docs / 921,611 passages (the largest shelf by passages; largest by documents until the EDH inscriptions arrived — §8g; counts as of 2026-07-17 — per-language split above from the 2026-07-14 resync) |
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
| **Language** | Latin (`lat`), Greek (`grc`), Gothic (`got`), Classical Armenian (`xcl`), Old Church Slavonic (`chu`), Old East Slavic (`orv`), Vedic Sanskrit (`san`), Old English (`ang` — ISWOC, §8d), Old Irish (`sga` — the P25-2 glosses pair, §8l) |
| **Period** | 5th c. BCE (Herodotus) through 17th c. CE (Avvakum) |
| **Size** | 75 docs / 175,742 passages across three sources: `proiel` (12 docs / 51,321), `torot` (40 / 33,085), `ud` (23 / 91,336) — plus `iswoc` (5 / 2,536, §8d) in the same family |
| **Sources** | PROIEL (frozen release), TOROT (Tromsø OCS/OES), ISWOC (Old English — §8d), Universal Dependencies (nine treebanks incl. Old East Slavic birchbark letters, Middle Russian RNC, Ruthenian, and — since the 2026-07-17 sync — the two Old Irish glosses treebanks DipSGG/DipWBG; birchbark/RNC/Ruthenian/DipWBG CC BY-SA/`attribution` via per-document override); PROIEL/TOROT/ISWOC/legacy-UD license: `nc` |
| **Metadata** | The gold lemma layer: `passage_lemmas` totals **12,597,062 rows in 23 languages** (post the settled full rebuild). The pools, by size: san 5.54M and sux 2.97M lead (DCS + ORACC/ETCSL), then egy 799k (§8o), lat 621k, grc 563k, orv 455k, akk 363k, hbo 277k (§8q), cop 233k (§8f), sl 214k (§8e), chu 130k, ojp 123k (§8s, ONCOJ), sga 113k (§8l, CorPH), got 99k, bul 42k, ang 25k, xcl 18k, with peo/arc/hit/uga/elx/xhu the small gold tails. Searchable via `search --lemma` with per-language folding and suppletive-form support (affero → attulimus) |

Three families: PROIEL's parallel New Testament (Greek original + Latin
Vulgate + Gothic Wulfila + Classical Armenian + OCS Codex Marianus — five
versions of the same text, morphologically annotated) plus classical prose
(Herodotus, Caesar, Cicero); TOROT's Old East Slavic and OCS shelf (birchbark
letters, chronicles including the Kiev Chronicle, Domostroj, Avvakum,
Afanasij Nikitin); UD treebanks adding Thomas Aquinas (ITTB, the largest
Latin lemma pool), Vedic Sanskrit, the Ruthenian (prosta mova) treebank
riding under `orv`, and — since the 2026-07-17 sync — the two Old Irish
glosses treebanks (St Gall Priscian DipSGG, Würzburg DipWBG; test-set-only
conversions, the UD side of the Celtic axis — §8l).

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
| **Language** | Latin (`lat`), Greek (`grc`), English (`eng`), Biblical Hebrew (`hbo`) |
| **Size** | `vulgate`: 73 books / 35,809 verses (the complete Clementine canon, public domain). `sblgnt`: 27 books / 7,939 verses (SBL Greek NT, CC BY 4.0). `oshb`: 39 books / 23,213 verses (Open Scriptures Hebrew Bible, synced live 2026-07-18 — the complete Westminster Leningrad Codex with OSHM morphology and augmented-Strong's lemmas; text public domain, morphology CC BY 4.0). `eng-web`: 84 books / 37,624 verses (World English Bible, public domain — the readable English witness, P11-8). LXX: no separate source — Swete's Septuagint lives in First1K (§2) and is hub-wired |
| **Metadata** | Native book.chapter.verse citations (`urn:nabu:vulgate:jon:2.1`, `urn:nabu:oshb:gen:1.1`); every verse a hub-alignable ref. OSHB verses carry per-word morphology and both ketiv/qere readings (the *ketiv* in the stored text, the *qere* riding the token's annotations — the `reading` display mode shows the qere, docs/display.md); `hbo` text is stored byte-verbatim under the NFC exemption (Masoretic mark order is not NFC-stable — owner ruling 2026-07-18, architecture §3) |

With these aboard, the NT hub registers **fifteen witnesses** (Greek NT,
Vulgate, Gothic, Armenian, PROIEL Marianus, West-Saxon Gospels, SBLGNT,
Clementine, WEB English, the four CCMH OCS codices — §8e — and, since the
2026-07-13 Coptic sync, the Sahidic and Bohairic NT — §8f); `align "MARK
2.3"` attests fourteen of them (per-witness verse coverage stays honestly
fragmentary), and `align "GEN 1.1"` opens the OT axis — since the
2026-07-18 `oshb` sync a **four-legged** one (Masoretic Hebrew ↔
Septuagint ↔ Vulgate ↔ English).
Rahlfs' LXX was honestly blocked on CATSS license terms — recorded in
02-sources.

**Research uses:** textual criticism across traditions; Vulgate as the
bridge between the classical Latin shelf and medieval reception; the NT as
the densest multi-language alignment laboratory in the library.

## 8c. Reference shelf (dictionaries)

| | |
|---|---|
| **Category** | Scholarly lexica and reconstruction dictionaries — entries, not passages (own tables, own `nabu define` / `nabu etym` surfaces) |
| **Size** | **633,137 entries** across twenty-seven dictionary shelves: `lexica` — LSJ (Greek, 116,497) + Lewis & Short (Latin, 51,636) — plus **`bosworth-toller`** (Old English, 62,815, CC BY 4.0) + **`mw`** Monier-Williams (Sanskrit, 193,890, `nc`) + Wiktionary OCS (`wiktionary-cu`, 4,615) + the `wiktionary-recon` shelves (28,736: the seven reconstruction shelves — Proto-Germanic 5,717, Proto-West Germanic 5,551, Proto-Slavic 5,431, PIE 1,905, Proto-Indo-Iranian 799, Proto-Italic 745, Proto-Balto-Slavic 491 — plus the three attested-Celtic extracts sga/mga/wlm, §8l) + the etymological witnesses synced 2026-07-14 (**IE-CoR** 4,981 cognate sets, **LIV** 305 verbal etymons, **de Vaan EDL** 2,860 etymons across two shelves — §8h) + the five **StarLing** bases (`starling`, 27,397 — §8j) + the three Slovenian historical dictionaries (`sl-lexica`, 139,405 — §8k) |
| **Metadata** | Folded-headword keying (diacritic-insensitive lookup, incl. æ/þ/ð→ae/th for Old English); betacode decoded; entry citations parsed and **resolved to in-catalog passages** where the cited work exists (μῆνις → Il. 1.1 as a live urn); glosses surface in `search --lemma` output; the reconstruction entries carry machine-readable **descendant trees** joined to attested gold lemmas (`dictionary_reflexes`) |

`nabu define λόγος` / `define virtus` / `define aethele --lang ang`, and
MCP `nabu_define` for AI-assisted reading. A leading `*` (`define *bogъ`)
scopes to the reconstruction shelves; `nabu etym` walks an attested lemma
up the proto-to-proto chain, and `nabu cognates` crosses that crosswalk
with the alignment hub (§9) — the comparativist loop closed on live data.
All of the Phase 16–17 extensions are **live** since the 2026-07-13 owner
syncs + rebuild, and the Phase-18 third-witness tier joined them at the
owner's 2026-07-14 syncs: the reflex crosswalk (`dictionary_reflexes`) now
holds **1,036,224 edges** across thirteen shelves, including
wiktionary-cu's own descendants sections (2,210 edges, the P16-5 rider),
Monier-Williams' Gk./Lat./Goth. comparanda (3,250 edges — a second etym
witness beside kaikki), and the new witnesses' 29,352 edges (§8h). The
P17-3 **multi-hop closure** (PIE \*per- → PBS → \*pьrstъ → chu/orv in one
walk) and the migration-010 **`borrowed`** flag with per-edge "(loan)"
rendering in `etym`/`cognates` are equally live. MW lookup rides the
SLP1↔IAST transcode (`define amsa` reaches aṃśa/aṃsa), with citation tiers
resolving RV./BhP. references to GRETIL urns at verse grain.

**Research uses:** the philologist's desk loop (passage → lemma →
definition → cited parallel passage) closed inside one tool; lexicographic
studies over the full entry set; comparative etymology from attested OCS,
Gothic, or Old English forms to their reconstructed roots and back down to
cognates the corpus actually attests.

## 8d. Old English

| | |
|---|---|
| **Category** | The OE axis (.docs/surveys/oe-survey.md — gitignored planning material): poetry corpus + gold treebank + dictionary (§8c) |
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
| **Category** | The Slavic axis (.docs/surveys/slavic-survey.md): OCS gospel manuscripts, the oldest Slovene text, Early Modern Slovenian print, pre-standardized Balkan Slavic |
| **Language** | Old Church Slavonic (`chu`), Bulgarian on the Church-Slavonic→Bulgarian continuum (`bul`), Slovenian incl. its historical stages (`sl`), plus the Freising translation layers (`lat`, `eng`, `ger`, `ita`, `pol`) and the damaskini English siblings |
| **Period** | ~1000 CE (Freising Manuscripts) through 1899 (IMP print) |
| **Size** | `ccmh`: 19 docs / 28,786 passages — four gospel codices in Helsinki-ASCII transliteration (Zographensis, Marianus, **Assemanianus**, **Savvina kniga**), CC BY → `attribution`. `freising`: 27 docs / 2,037 lines — the Brižinski spomeniki in three aligned transcription layers + five modern translations, CC BY-ND → `research_private` (the first MCP-default-excluded source). `goo300k`: 89 docs / 8,397 passages — **gold-annotated** Early Modern Slovenian (1584–1899), the `sl` gold-lemma shelf (214k lemma rows). `imp`: 658 docs / 404,897 passages — the silver-annotated IMP print corpus, the library's fourth-largest shelf by passages (the EDH inscriptions, §8g, edge past it by ~1,400). `damaskini`: 46 docs / 12,072 passages — 23 gold-annotated Balkan Slavic witnesses, 15th–19th c., plus their 23 English sibling translations (synced live 2026-07-17) |
| **Metadata** | CCMH: folio-line citations, hyphen-split words searchable whole; freising: per-layer parallel citation; goo300k/imp: CE year in the urn (`…:sigil-1584`) feeding the timeline (§9) — all 747 Slovene docs dated; damaskini: gold lemma + MULTEXT-East MSD, Norm/Origin document facets, TSV-header dates and places on the timeline |

The four CCMH codices join the alignment hub (witnesses 10–13 of the NT)
and are the substrate of `align REF --collate` — a raw-token apparatus per
(language, script) group, the Helsinki-ASCII codices collated against each
other, the Cyrillic Marianus beside them honestly uncollated (the fold
cannot bridge the two transcription systems). Wiktionary-OCS and the
reconstruction shelves (§8c) complete the axis: богъ → \*bogъ → PIE.

The `damaskini` shelf (Annotated Corpus of Pre-Standardized Balkan Slavic
Literature 1.1, CLARIN.SI, CC BY-SA → `attribution`; synced live
2026-07-17) opens the axis's southern continuation: 23 gold-annotated
damaskini and related witnesses of the 15th–19th c.
Church-Slavonic→Bulgarian continuum — among them ~10 independent
witnesses of Euthymius of Tarnovo's *Life of St. Petka* — each with a
full English sibling translation (`show --parallel` works), classified
honestly by the corpus's own Norm scheme (`chu` ×3 / `bul` ×20, the
deposit's own "Bulgarian" usage quoted in 02-sources row 60), with
dialectal Origin riding as document facets and the TSV-header dates
(1536–1860) on the timeline.

**Research uses:** OCS textual criticism with a live apparatus; Slavic
diachrony continued past the treebanks (§6) into Early Modern print *and*
down the Balkan vernacular line; multi-witness collation of the St. Petka
tradition; diachronic Slovene lexis over three centuries
(`vocab --by-century`); the Freising Manuscripts beside their OCS
near-contemporaries.

## 8f. Coptic (Coptic Scriptorium)

| | |
|---|---|
| **Category** | Literary Coptic: the complete Sahidic and Bohairic New Testaments, monastic and patristic prose, hagiography, apophthegmata — with gold lemmas |
| **Language** | Coptic (`cop`), Sahidic and Bohairic dialects |
| **Period** | Roughly 3rd–10th c. CE, the Christian-Egypt corpus |
| **Size** | 482 docs / 74,169 passages — 482 of the 483 upstream corpora aboard (P18-1 coverage pass; the one remainder is an honest quarantine) |
| **Source** | `coptic-scriptorium` (Coptic Scriptorium, release v6.2.0, TT parser family), license: CC BY per document with source class `nc` (most-restrictive-wins) |
| **Metadata** | Upstream **gold lemmatization** — **233,020 `cop` lemma rows**, gold-lemma language **#15**; language-of-origin loan tags (the Greek layer inside Coptic); Wikification entities; manuscript-timeline rows (340 dated documents) |

Synced and flipped by the owner 2026-07-13 (the first sync attempt's unzip
failure re-run clean; P18-1 then lifted coverage from the initial 188
documents to 482). The Sahidic and Bohairic NTs attest in the alignment
hub as witnesses #14 and #15 (§8b), and `cop` — previously the library's
largest language with zero tooling — now joins `search --lemma`, `vocab`,
and the loan-layer questions the etym shelf asks.

**Research uses:** Coptic philology with gold lemma search; Sahidic ↔
Bohairic dialect comparison over the same verses (the hub renders both);
the Greek-loan stratum of Coptic as data; continuity with the 2,063
documentary Coptic papyri (§4) across the literary/documentary line.

## 8g. Latin inscriptions (EDH)

| | |
|---|---|
| **Category** | The third documentary genre: epitaphs, dedications, honorific and building inscriptions, milestones, instrumentum — the Roman epigraphic habit |
| **Language** | Latin (`lat`, 80,561 docs), Greek (`grc`, 1,290 — the bilinguals), plus 5 `und` (exotic-language residue, coded honestly; split as of the 2026-07-14 census — the P23-3c quarantine-recovery re-parse added 25 docs since) |
| **Period** | Roman Republic through Late Antiquity, empire-wide — provinces from Britannia to Arabia |
| **Size** | 81,881 docs / 406,306 passages — the largest shelf by documents (48% of the library; counts as of 2026-07-17) |
| **Source** | `edh` (Epigraphic Database Heidelberg), license: `attribution` (CC BY-SA 4.0); **`sync_policy: frozen`** — upstream archived 2021, this is a one-shot preservation snapshot (27 quarantines, triaged at gate 18: 26 lb-less inscriptions carried to P19, 1 malformed upstream XML, all baseline-anchored) |
| **Metadata** | The library's first **genre facets** (migration 009): `document_facets` live at **256,518 rows** (genre/province/material/object_type, `?`-certainty preserved in `raw`) behind `search --type/--province/--material`; **81,416 dated documents** on the timeline (§9); persons prosopography in `metadata_json`; Leiden ⟦…⟧ rendering for every `del`; `fuzzy_index: true` |

Synced and flipped by the owner 2026-07-13. Inscriptions beside papyri
(§4) and tablets (§8) complete the documentary triangle, and the facet
axes make the epigraphic habit queryable: `search --type epitaph
--province Britannia --material marble` composes with the date/place
filters.

**Research uses:** Latin epigraphy proper (formulae, titulature, careers);
provincial and social history by facet (genre × province × material);
onomastics and prosopography at empire scale; the epigraphic habit as a
quantitative object; fragment search (`--fuzzy`) over damaged stones.

## 8h. The etymological witnesses — IE-CoR, LIV, EDL (synced live 2026-07-14)

The three Phase-18 adapters were synced and flipped live by the owner on
2026-07-14; every number below is a live catalog count:

- **`iecor`** — IE-CoR (lexibank/iecor v1.2, CC BY 4.0, sha-pinned
  immutable Zenodo DOI): the expert-curated Indo-European cognacy matrix
  as a dictionary shelf — **4,981 cognate-set entries** under the
  collective `ine` tag / **26,325 reflex rows** (2,308 loan-flagged,
  feeding `borrowed`); 143 language notes accreted as `iecor` sections in
  the local-language dossiers (§8i) — the dossier shelf's first
  programmatic writer. An independent third etymological witness beside
  kaikki and MW: `etym срьдьцє` now reaches \*k̑erd- on the IE-CoR card
  with grc καρδία ~ lat cor ~ got hairto and live attestation counts.
- **`liv`** — LIV-LOD (CIRCSE/LiLa, CC BY-SA 4.0 with publisher
  permission): **305 PIE verbal etymons** with verbal stem types in the
  entry bodies / **374 reflex edges**; first user of the lila-ttl
  (Turtle) parser family.
- **`edl`** — de Vaan, *Etymological Dictionary of Latin* (CIRCSE/LiLa LOD
  skeleton, CC BY-NC-SA → `nc`, MCP-default-served with its label, never
  redistributed): **2,860 etymons across two shelves** (`edl-ine-pro`
  1,394 + `edl-itc-pro` 1,466) / **2,653 reflex edges** — the lat →
  Proto-Italic → PIE Leiden chains beside kaikki's.

## 8j. The StarLing etymological bases (`starling`, synced live 2026-07-17)

| | |
|---|---|
| **Category** | The Moscow-school etymological databases (StarLing / Tower of Babel, starlingdb.org) as five dictionary shelves — the Pokorny family complete |
| **Size** | **27,397 entries**: `starling-pokorny` — Pokorny's *Indogermanisches Etymologisches Wörterbuch*, all 2,222 roots with full Material/References apparatus; `starling-piet` — Nikolayev's Walde-Pokorny-based PIE database, 3,291 etymologies with per-branch reflex columns; `starling-vasmer` (`rus`) — Vasmer's etymological dictionary of Russian, Trubachev edition, 18,239 entries; `starling-germet` (`gem-pro`) — the Common Germanic database, 1,994 etymologies; `starling-baltet` (`bat-pro`) — the Baltic database, 1,651 |
| **Source** | One 6.2 MB `IE.exe` package, decoded by the table-driven `starling-dbf` parser family (dBase III + StarLing font-shift encoding, byte meanings from the vendored official tables, never guessed) |
| **License** | `attribution` — a written grant (G. Starostin, 2026-07-15: "free for anybody to use for any purposes as long as the source is properly acknowledged"), with per-base compiler credit carried verbatim in the manifest and rendered on every `define`/`etym`/MCP surface, and the compiler's caveat (individual reconstructions, not always the consensus view) riding with it |

The piet/germet/baltet reflex columns mint reflex rows (germet's Gothic
and Old English columns join the gold-attestation counts), the
pokorny⇄piet crosslinks are preserved both ways, and `define сигать`
reaches the Vasmer article — with `etym` falling back to the same lookup
when the reconstruction crosswalk has no path (the P24-2 coordination).

**Research uses:** the classical Pokorny apparatus beside the modern
witnesses (IE-CoR, LIV, de Vaan — §8h) on one desk; Vasmer as the Slavic
etymological reference the axis lacked; branch-level Germanic and Baltic
comparanda joined to attested corpus forms.

## 8k. Slovenian historical dictionaries (`sl-lexica`, synced live 2026-07-17)

| | |
|---|---|
| **Category** | The Slovenian historical dictionary shelf (ZRC SAZU via CLARIN.SI), three dictionaries on one source |
| **Size** | **139,405 entries**: `pletersnik` — Pleteršnik's *Slovensko-nemški slovar* (1894–95), 103,185 entries, THE reference dictionary of older Slovenian with toneme-accented headwords and German glosses; `jsv` — the dictionary of Janez Svetokriški's Baroque sermon lexis (1691–1707), 8,461 entries with verbatim Bohorič-orthography attestation quotes; `besedje16` — the complete word inventory of 1550–1603 Slovenian print, 27,759 entries with per-word attestation sigla of the editions |
| **License** | All three CC BY 4.0 verbatim → `attribution` (frozen CLARIN.SI deposits; parser family `zrc-xml`) |

Headwords are keyed on the unaccented form, so `define abeceda` lands on
the toneme entry `abecę̑da`, and — the point of the shelf — Pleteršnik's
headwords match goo300k's modernized gold lemmas (§8e): the
gold-lemma→dictionary loop that LSJ closed for Greek now closes for `sl`.
Besedje16's sigla (TA 1550, DB 1584…) name the very editions goo300k/IMP
hold as documents.

**Research uses:** diachronic Slovene lexicography 1550–1899 on one desk;
gloss-carrying `sl` lemma search; earliest-attestation questions at word
grain; Baroque sermon lexis with in-context quotations.

## 8l. The Celtic axis (`corph`, `riig`, `ogham`; synced live 2026-07-17)

| | |
|---|---|
| **Category** | The library's newest language axis (.docs/surveys/celtic-survey.md): Early Irish gold annotation, Gaulish and Primitive Irish epigraphy, plus dictionary and treebank riders |
| **Language** | Old/Early Irish (`sga`), Gaulish (`xtg`, Gallo-Greek and Gallo-Latin scripts), Primitive Irish (`pgl`, real Ogham codepoints), with Latin companions and Pictish/Old Norse rarities coded honestly |
| **Size** | `corph`: 76 docs / 17,942 passages — CorPH / Corpus PalaeoHibernicum (ERC ChronHib, Maynooth; MIT → `attribution`): 7th–10th-c. texts (Annals of Ulster, Vita Columbae, Blathmac, the Milan/St Gall/Würzburg gloss corpora, law, poetry, computus) with 136,559 gold-lemmatized tokens — **the first `sga` gold lemmas**. `riig`: 477 docs / 1,323 passages — RIIG (ANR, Ausonius/Bordeaux; CC BY 4.0 in-file → `attribution`): 428 Gaulish inscriptions with per-editor readings, morphosyntax, dated findspots, and French sibling translations. `ogham`: 834 docs / 1,053 passages — OG(H)AM / Ogham in 3D v2.0 (DIAS/Maynooth): ~500 ogham stones in real Ogham codepoints with transliteration/roman sibling layers; **license conflict held at the restrictive reading → `nc`** (site says BY-NC-SA, in-file records say CC BY 4.0; clarification email pending, relabel on reply) |
| **Metadata** | CorPH: per-token language and dil.ie headword keys (→ links-journal reference edges — the eDIL bridge), ChronHib text dates on the timeline; RIIG: signed-year `origDate` + WGS84 findspots on the timeline, RIG print-corpus concordance as reference edges; ogham: dil.ie word links, logainm.ie place ids, CIIC/CISP concordances |

The axis's riders land elsewhere in the library: the three attested-Celtic
kaikki extracts (`wiktionary-sga`/`-mga`/`-wlm`, 8,097 entries on the
`wiktionary-recon` source — §8c) and the two Old Irish UD glosses
treebanks (§6). Together they light Proto-Celtic reflex attestations, the
piet CELT column's context, and IE-CoR's `sga` variety.

**Research uses:** Early Irish philology with gold lemma search; the
Continental Celtic epigraphic record beside the insular one (RIIG's
Segomaros dedication against the Kerry stones); ogham palaeography with
layer-aligned transliterations; Celtic comparanda joined to the
reconstruction shelves.

## 8m. The Indic expansion (`dcs`, `sarit`, `suttacentral`; synced live 2026-07-18)

| | |
|---|---|
| **Category** | Three shelves that widen the Indic axis beyond GRETIL (§5): gold-lemmatized Sanskrit, scholarly TEI editions, and the Pali Tipiṭaka |
| **Language** | Sanskrit (`san` — Devanagari and IAST surfaces, both reachable from IAST queries via the Deva→IAST search fold), Pali (`pli`, roman script) plus the Patna Dhammapada's Prakrit (`pra`), with aligned English siblings on `suttacentral` |
| **Size** | `dcs`: 15,741 docs / 753,093 passages — Digital Corpus of Sanskrit (Hellwig; CC BY 4.0 → `attribution`): 270 texts in gold chapter files, ~5.46M words with human-verified sandhi splitting, lemmatization and morphology — **the first gold Sanskrit occupant of the lemma index** (deliberately unmerged with `ud/sanskrit-vedic`'s same-material treebanks: two honest witnesses at different grains). `sarit`: 78 docs / 345,601 passages — SARIT scholarly TEI editions (censused per-file: BY-SA + one MIT, zero NC → `attribution`): ~60 works GRETIL lacks, incl. a complete **Mahābhārata in the Southern Recension** (Kumbakonam — not the vulgate MW cites, so no MW joins promised on it); 5 quarantines = the documented parse floor. `suttacentral`: 12,022 docs / 654,974 passages — SuttaCentral bilara-data (license read per publication from the repo's own records: overwhelmingly CC0): the whole Tipiṭaka in roman-script Pali (Mahāsaṅgīti) with translator-picked English siblings riding the same segment ids (the ORACC precedent) |
| **Metadata** | DCS: per-token gold lemmas and morphology feeding `search --lemma` and `define`'s attested counts; SARIT: 41/83 files carry a native Devanagari surface, kept canonical while the search layer folds; SuttaCentral: segment-id citations (`urn:nabu:suttacentral:mn1:1.1`) with `--parallel` English |

Together with GRETIL these put the Sanskrit shelf past **1.8M passages**
with three independent witnesses of the tradition — a breadth corpus (§5),
a gold-annotation corpus, and critical editions — plus the canon of a
second Indic language beside them.

**Research uses:** lemma-true Sanskrit search at scale (gold counts,
never guesses); commentary and recension comparison (Southern vs. vulgate
Mahābhārata); Pali–Sanskrit comparative work in one library; Buddhist
studies with segment-aligned translations.

## 8n. The Greek silver layer (`diorisis`, synced live 2026-07-18)

| | |
|---|---|
| **Category** | Lemmatized second editions of the Greek canon — the library's **first silver source** (P26-0 tier contract: machine-produced annotation, every count labeled `[silver]`, never presented as gold attestation) |
| **Language** | Ancient Greek (`grc`), Homer to early Byzantium |
| **Size** | 764 docs / 502,865 passages — the Diorisis Ancient Greek Corpus (Vatri & McGillivray 2018, sha256-pinned figshare artifact; in-file CC BY-SA → `attribution`): ~10.2M words tokenized, lemmatized and morphologically analyzed. 53 Septuagint files (Rahlfs lineage, CATSS-encumbered) are excluded by rule at discovery — the skip is censused in every sync line |
| **Metadata** | Per-token automatic lemmas and morphology; 806/809 works are provenance-distinct second editions of texts already held (742 Perseus, 102 First1K) — deliberately unmerged witnesses; the value is the lemma layer at scale |

**Research uses:** lemma search across the whole Greek canon where the
gold treebanks (§6) cover only samples; frequency and collocation studies
at corpus scale with honest `[silver]` labels; edition-vs-edition checks
against the Perseus/First1K copies of the same works.

## 8o. The Egyptian axis (`aes`, `aed`, `tla-hf`, `ccl`; synced live 2026-07-18)

| | |
|---|---|
| **Category** | Three millennia of Egyptian in one axis: the TLA/BBAW corpus snapshot, its dictionary, the official demotic/Late Egyptian freshness channel, and the Coptic lexicon bridge |
| **Language** | Egyptian in Unicode transliteration (`egy`, Old Kingdom through Roman), with aligned German (`ger`/`deu`) translation siblings; Coptic (`cop`) on the dictionary end |
| **Size** | `aes`: 13,026 texts / 101,793 sentences (+ 12,985 `-de` siblings) — Pyramid Texts, Book of the Dead, Amarna, Sinuhe and the sawlit literary canon, medical papyri, letters, tomb and rock inscriptions across 16 subcorpora, ≈779k gold lemma tokens (CC BY-SA 4.0). `aed`: 35,052 dictionary entries whose ids ARE the corpus's lemma ids — `define` resolves an AES lemma directly. `tla-hf`: 13,383 demotic + 3,606 Late Egyptian sentences (the only bulk demotic anywhere; corpus v18/v19, 2023–24) with German on every sentence. `ccl`: the Comprehensive Coptic Lexicon (11,284 entries, CC BY-SA) + the ORAEC CC0 crosswalk minting `etymology` edges — the 3,000-year lemma chain (ⲕⲁϩ ← qꜣḥ ← qh) |
| **Metadata** | Gold lemmatization throughout `aes` (`search --lemma nfr`); hieroglyphs/MdC/Gardiner encodings riding token annotations; conventional Egyptological period envelopes + findspots on the timeline; the AED root network (`show urn:nabu:dict:aed:tla866216` walks *nfr*'s 56 derivatives) |

**Research uses:** Egyptology with lemma-true search from the Pyramid
Texts to demotic contracts; dictionary-resolved reading of any sentence
(`show --parallel ger`); the egy↔cop diachronic bridge once `ccl` syncs
(Refubium outage pending); daily-life corpora (medicine, letters, beer
accounting) through the German layer.

## 8p. Pre-Roman Italy & Sicily (`open-etruscan`, `larth-etp`, `ceipom`, `itant`, `sabellic-loans`, `lexlep`, `lexlep-words`, `tir`, `isicily`; synced live 2026-07-18)

| | |
|---|---|
| **Category** | The whole pre-Roman epigraphic map of Italy and Sicily — seven fragmentary languages, most of them in their only machine-readable form |
| **Language** | Etruscan (`ett`), Oscan (`osc`), Umbrian (`xum`), Faliscan (`xfa`), Venetic (`xve`), Messapic (`cms`), South Picene (`spx`), archaic Latin, Lepontic/Cisalpine Gaulish (`xlp`/`xcg`), Raetic (`xrr`), Sicel (`scx`), Elymian (`xly`), Sicilian Punic and Mamertine Oscan |
| **Size** | `open-etruscan`: 8,047 docs — 6,248 Etruscan inscriptions + English siblings (CC BY, with the ETP scholarly glossary `larth-etp`, 1,122 entries). `ceipom`: 3,871 texts / 5,303 sentences — the lemmatized, dated, geolocated pre-Roman-Italy database incl. the Fibula Praenestina, Duenos and the complete Iguvine Tables (CC BY-SA). `itant`: 1,160 docs — 501 Oscan + 9 Lepontic critical editions with English/Italian siblings (nc). `sabellic-loans`: 85 curated Latin←Sabellic loan entries (`etym pompeii`). `lexlep`/`lexlep-words`: 494 Cisalpine inscriptions + the 627-word Lepontic lexicon (nc, relabel email pending). `tir`: 389 Raetic inscriptions — the corpus of record (nc, same email). `isicily`: 5,074 docs / 15,369 passages of Sicilian epigraphy across all languages (CC BY) |
| **Metadata** | Signed-year datings and findspots feeding the timeline at the next rebuild; script facets (eight native alphabets); Trismegistos/Imagines Italicae/EDH concordance edges; per-token lemmas and `Classical_Latin_equivalent` bridges on `ceipom`; morphemic analyses on the Lepontic lexicon |

**Research uses:** comparative Italic philology beside the Latin shelves;
Etruscan reading with a dictionary (`define avil`); loan-flagged
etymological chains from Rome's neighbors (`etym rufus`); epigraphic
habit studies across alphabets and centuries; the Sicilian fragmentary
languages (Sicel, Elymian) in their only digital home.

## 8q. The Hebrew shelf (`hebrew-lexicon`, `sdbh`, `sefaria`, `bhsa`, `dss`, `iip`; synced live 2026-07-18, flipped 2026-07-19)

| | |
|---|---|
| **Category** | The Hebrew Bible and Second Temple axis around the P26-3 Masoretic shelf (`oshb`, §8b): two dictionaries, the Aramaic column, the syntax witness, the Scrolls, and the epigraphy |
| **Language** | Biblical Hebrew (`hbo`) and Aramaic (`arc`) — both byte-verbatim under the NFC exemption — plus the epigraphic mix (Greek/Latin/Phoenician/Syriac on `iip`) |
| **Size** | `hebrew-lexicon`: 21,144 entries in two shelves — 9,299 augmented-Strong entries (the exact ids OSHB lemmas carry: `define` resolves any OSHB lemma directly, 100.000% join) + the 11,845-entry BDB outline with print-page anchors. `sdbh`: 7,932 UBS semantic-dictionary entries with domains and 260,813 verse-level scripture refs (CC BY-SA). `sefaria`: 103 Targum documents / 57,095 passages (Onkelos, Jonathan, the Writings targums — per-version license gate; unlicensed versions excluded by rule). `bhsa`: 39 books / 23,213 verses with full ETCBC clause/phrase syntax, ketiv-qere hybrid and per-lexeme glosses (nc). `dss`: 1,001 scrolls / 500,995 words / 1.43M signs — Abegg's transcriptions under his own CC BY-NC grant, text-critical flags intact. `iip`: 5,499 inscriptions of Israel/Palestine, ~500 BCE–640 CE, densely dated (nc) |
| **Metadata** | The `ot` alignment hub runs six-legged (MT ×2 ↔ LXX ↔ Vulgate ↔ English ↔ Onkelos — `align "GEN 1.1"`); BHSA constituency spans are the library's first syntax annotations; DSS clusters carry correction/erasure/reconstruction degrees verbatim; IIP's timeline lights at rebuild |

**Research uses:** Masoretic philology with a real dictionary chain
(lemma → augmented Strong's → BDB page); semantic-domain study over the
whole Tanakh; Targum-beside-MT reading; clause-level syntax queries; the
Scrolls beside the codices for textual criticism; the epigraphic record
of the same land and centuries. Rabbinic literature proper is a future
campaign — the Targums are its first bridgehead.

## 8r. The Ancient Near East (`tlhdig`, `cdli`, `ebl`, `cuc`, `peshitta`, `syriac-corpus`, `etcsl` + the `oracc`/`ud` expansions; synced live 2026-07-19, flipped 2026-07-19)

| | |
|---|---|
| **Category** | The cuneiform world beyond ORACC, plus the Iranian flank and the Syriac millennium — Phase 31 |
| **Language** | Hittite (`hit`) at corpus scale, Sumerian/Akkadian mass (`sux`/`akk`), Ugaritic (`uga`, new axis language), Classical Syriac (`syc`), Old Persian (`peo`) and Elamite (`elx`) via the Achaemenid trilinguals, Eblaite (`xeb`), proto-cuneiform (`qpc`) and proto-Elamite at CDLI |
| **Size** | `tlhdig`: 23,486 Hittite manuscripts / 402,195 lines — >98% of published fragments, candidate morphology at silver (72.6% disambiguated mints lemmas). `cdli`: 353,156 artifacts / 2,186,961 passages — 135,201 C-ATF transliterations + the whole catalog as metadata-only documents with period/provenience/collection axes. `ebl`: 23,288 Fragmentarium fragments / 325,728 lines with inline English, 79.9% carrying CDLI cross-links (nc pending the license-discrepancy email). `oracc` grew 33→38 projects to 104,722 docs / 1,588,133 passages (ario + the four ePSD2 corpora incl. the Ur III administrative mass). `cuc`: 279 KTU tablets / 27,770 words with a per-sign cuneiform lane (nc). `peshitta`: 65 books / 31,341 verses (nc). `syriac-corpus`: 632 TEI documents / 134,726 passages (CC BY per file). `etcsl`: 775 documents / 42,577 passages — 394 hand-lemmatized composites + 381 English prose siblings (nc). `ud` grew to 12 treebanks (+HitTB gold Hittite, +the two Perseus conversions) |
| **Metadata** | The `ot` hub runs seven-legged (the Peshitta the Syriac leg, versification measured Masoretic); the CDLI timeline (329,948 period-parsed rows) stretches the library from Uruk IV to the Achaemenids; eBL→CDLI and ETCSL↔ePSD2 reference edges cross-link the shelf; the starling Anatolian reflex columns light against TLHdig (205/306 HITT keys join) |

**Research uses:** Hittitology at fragment scale with honest silver
labelling; Assyriology across the whole catalogued artifact space —
proto-cuneiform and proto-Elamite have their only machine-readable home
here; Sumerian literature in two deliberately unmerged scholarly
editions; Ugaritic epic beside the Hebrew shelf; the Peshitta beside six
other OT witnesses; a millennium of Syriac prose. The two silver-tier
corpora never contaminate gold lemma search — `--gold-only` excludes
them, and every hit carries its tier label.

## 8s. The Sino axis (`oncoj`, `oncoj-lexicon`, `baxter-sagart`, `tshet-uinh`, `unihan`, `edrdg`, `hdic` + the `ud`/`wiktionary-recon`/`suttacentral` expansions; flipped live in the full rebuild 2026-07-20 — `hdic` alone still held disabled pending the LICENSE-file ruling)

| | |
|---|---|
| **Category** | Classical Chinese through historic Japanese — Phase 32, the owner's Far Eastern axis |
| **Language** | Literary Chinese (`lzh`), Old/Middle Chinese reconstruction lanes (`och`/`ltc`), Old Japanese (`ojp`), with modern `jpn` reading/gloss backstops |
| **Size** | `ud` +2 treebanks: UD_Classical_Chinese-Kyoto (86,239 gold sentences / 433,169 tokens — Analects, Mencius, Liji, Chuci, Tang poetry) + TueCL. `suttacentral` +326 docs: the 272 Taishō Āgama roots already held (scope flip, zero fetch) + 54 Patton English siblings, CC0 verbatim — plus the parallels graph as ~195k reference edges (4,788 both-ends-minted today; the pli↔lzh axis). `oncoj`: 4,991 texts — the complete Man'yōšū and all OJ poetry, line grain, man'yōgana riding annotations (annotation CC BY 4.0). `oncoj-lexicon`: 5,868 ojp entries (99.8% of corpus token lemmas resolve). `baxter-sagart`: 4,959 rows → och+ltc lanes (CC BY via the wayback-preserved grant). `tshet-uinh`: the 廣韻 critical edition, 25,336 character-position entries (CC0), 校本 apparatus honest. `unihan`: 65,092 codepoints (Unicode License V3). `edrdg`: KANJIDIC2 + JMdict, 231k entries (CC BY-SA, nightly upstream). `hdic`: five Heian character-dictionary databases, 96,414 entries (BY-SA per file — LICENSE-file contradiction journaled, owner ruling pending). `wiktionary-recon` +2 extracts: ojp (532) + zh (323,840 — MC + dual OC reconstructions) |
| **Metadata** | The Sinoxenic bridge is character-keyed joins: KANJIDIC2→Unihan 99.5% by codepoint, HDIC→Unihan 95.9–99.9% per database; the Kyoto treebank is built on Kanripo texts (the P33 crosswalk); ETCSL-style two-witness honesty holds for B-S-beside-kaikki reconstruction systems |

**Research uses:** Classical Chinese with gold morphology; the Kālāma
Sutta beside its Madhyama-āgama parallel through the parallels graph;
the Man'yōšū lemma-searchable with its own lexicon; a character's
journey from Old Chinese reconstruction through Qieyun phonology to
its go-on/kan-on Japanese readings — the axis the bridge shelves exist
to serve. Kanripo (the 9,355-text Chinese library) and CBETA (the
Taishō canon) are the planned P33 continuations.

## 8t. The Chinese libraries (`kanripo`, `cbeta`, `tls`; flipped live in the full rebuild 2026-07-20 — `lzh` is now the library's largest language at 13.0M passages)

| | |
|---|---|
| **Category** | The Sino axis's bookshelf — Phase 33: the two great Chinese text libraries and the concept lexicon |
| **Language** | Literary Chinese (`lzh`) at library scale; Old Chinese (`och`) concept/word shelves |
| **Size** | `kanripo`: nabu's first many-repo source — waves 1+2 = KR1 classics + KR2 histories + KR3 masters + KR4 belles-lettres, 3,569 catalog ids / 3,512 repos / ~1.7 GB, catalog-driven shallow fetches with polite pacing and a resumable per-text ledger; editions are git branches (master = base edition); citation grain text:juan:leaf-side from the mandoku page anchors; org-level CC BY-SA grant (№25 CONFIRMED by the maintainer in writing 2026-07-20). `cbeta`: the Taishō (T, 2,471 files / 816 MB) + Xuzangjing (X, 1,236 / 645 MB) in CBETA's TEI — the Taishō citation (page-register-line) rides free from the lb milestones; CC BY-NC-SA per the canon-level gate, the four Category B corpora refused by rule; all 272 held lzh Āgamas map into T. `tls`: the Thesaurus Linguae Sericae concept net as two och dictionaries — 3,018 concepts + 20,163 word superEntries (100% concept-linked), membership inverted from the words dir; CC BY-SA (the README badge discrepancy recorded) |
| **Metadata** | Producer #8 links the Kyoto treebank to its Kanripo source texts (all 936 treebank documents carry KR-ids; 44% resolve at wave 1, 56% more at wave 2); KR5 shipped as wave 3 (P37-1: the witness-overlay parser; owner sync pending — see §8u); the TLS attestation lane SHIPPED (P34-4): 189K sense-level dictionary_citations resolving into kanripo at page/document grain — 80.2% of KR-shaped citations resolve at the settled census (2026-07-21), +5.6% more the day the KR5 sync lands |

**Research uses:** the Analects readable beside its gold treebank
annotation and its TLS concept net; the Taishō canon at scholarly
citation grain with the Āgama parallels pointing in; dynastic histories
and the literary anthologies at page grain — the open ctext.org
substitute, on the researcher's own disk.

## 8u. The character desk & the Sino instruments (`babelstone-ids`, `kradfile`, `kr-gaiji` + the KR5 Daozang wave; Phase 37, 2026-07-21 — shelves await the owner-fired first syncs)

| | |
|---|---|
| **Category** | The largest shelf gets its instruments: character-structure search, the variant fold, gaiji rendering, and the Daozang |
| **Language** | Literary Chinese (`lzh`), Old Chinese (`och`) headwords, Japanese kanji (`ja` desk data) |
| **Size** | `babelstone-ids`: Andrew West's Ideographic Description Sequences — 97,680 characters at Unicode 16.0, public-domain dedication verbatim in the file, one 3.1 MB fetch (supersedes the GPL-encumbered cjkvi-ids, ruled OUT). `kradfile`: the EDRDG component→kanji index (the file Jisho itself searches) — 6,355 kanji under the same CC BY-SA licence document as KANJIDIC2/JMdict. `kr-gaiji`: a feature-module row (no documents) — the Kanripo gaiji map censused whole: 5,254 refs / 1.75M occurrences, 972 refs (36.4% of occurrences) map to real codepoints and resolve in `--display reading`; the rest render an honest ⬚ with a counted footer. KR5 道 the Daozang: 1,663 catalog ids / 1,660 repos / ~84 MB join the kanripo `classes:` via the witness-overlay parser (DZJY repos transcribe the CK-KZ witness edition; its page anchors are the citable structure) |
| **Metadata** | `nabu char 棄` — the character card: radical + strokes (unihan kRS*), IDS decomposition, components, variants, readings from kun/on through Mandarin and Korean, and the diachronic column no dictionary site offers — Old Chinese (Baxter-Sagart), Qieyun (tshet-uinh), Heian lexicography (hdic), TLS senses with classical attestations, corpus counts. `search --radical N / --strokes A-B / --char-component 木` — explicit character-structure modes, never mixed into text search. The trad/simp/z variant fold (6,050 unihan-derived pairs, semantic variants refused) folds 說/説/说 to one search skeleton; the ~13M-passage lzh re-derive rides the owner's next incremental rebuild |

**Research uses:** a character looked up once and answered across four
millennia of use — structure, sound, and attestation on one card; simplified-
script queries reaching the traditional-script corpus; the Daozang at witness
page grain beside the Buddhist and Confucian canons.

## 8v. The Japanese reading desk (`aozora`; synced live 2026-07-21)

| | |
|---|---|
| **Category** | The Japanese public-domain library: Aozora Bunko's volunteer-digitized corpus — Meiji-and-later literature with a thin classical tail (Kojiki, Tosa Diary, Hōjōki as modern critical editions) |
| **Language** | Japanese (`jpn`; ~2,285 works preserve kyūjitai 旧字 orthography) |
| **Size** | **17,195 documents / 2,991,807 passages** (2026-07-22 census; the owner's first sync 2026-07-21 reported 16,004 works). Scope is D38-a: **public-domain text only** — discovery is index-driven, so the 488 in-copyright works are excluded before any file is opened |
| **Metadata** | Ruby readings (`｜base《reading》`) stripped to an annotation layer; JIS X 0213 gaiji resolved into the text where upstream names a codepoint, censused verbatim sentinels where it doesn't; 底本 colophon (source edition, transcribers) carried as document metadata; formatting commands ride annotations, never text |
| **License** | Aozora's 取り扱い規準 grant — free redistribution → class `open`; 底本 attribution carried |

**Research uses:** Meiji/Taishō literature searchable beside the classical
Chinese library it constantly quotes; kyūjitai works reachable from
modern-form queries (the `jpn` reform fold: 国 finds 國 — conventions §9);
ruby readings preserved as data for readings research rather than flattened
into the text.

## 8w. The Germanic wave (`menotec`, `helipad`, `rem`, `rundata` + IcePaHC via `ud`; synced live 2026-07-22)

Four new sources and one config treebank in one phase (P40) — the North
and continental West Germanic branches joining Gothic (PROIEL) and Old
English (ASPR, ISWOC, Bosworth-Toller) on the `germanic` desk. All counts
are the owner-verified first syncs of 2026-07-22.

| | |
|---|---|
| **Category** | Old Norwegian treebanks and the Poetic Edda; the Old Saxon *Heliand*; the Middle High German reference corpus; the Scandinavian runic corpus |
| **Languages** | Old Norse (`non`), Old Saxon (`osx`), Middle High German (`gmh`), Proto-Norse (`gmq-pro` — the Wiktionary proto-code convention; ISO has none), and Old Icelandic (`is`, IcePaHC via the `ud` row — live since the owner's same-day `sync ud`: 44,029 passages, 812K gold rows) |
| **Size** | `menotec`: **7 treebanks / 20,308 sentences** (Poetic Edda / Codex Regius, the Homily Book, King's Mirror, Landslov, Óláfs saga, Pamphilus, Strengleikar) — gold PROIEL-scheme morphology + syntax, served through the INESS session API. `helipad`: **1 document / 3,549 tree blocks** — the *Heliand* (MS C) with gold form-lemma pairs on every token, Penn-bracketing parsed, metre and codicology preserved. `rem`: **406 texts / 355,449 manuscript lines** of gold-annotated MHG (1050–1350) — `gmh` lands as the corpus's **third-largest gold-lemma pool (2.10M rows)** on day one. The 46 first-sync quarantines (all one class: duplicate folio.line refs in two-column codices and entry-wise restarts) were recovered the same day by the P40-r1 citation fix (`5ra.1` column refs + the `:b2` positional disambiguator). `rundata`: **30,643 lane-documents / 30,641 passages** — ~6,800 runic inscriptions in up to five text lanes each (transliteration primary; Old West Norse and runic-Swedish normalisations; English and Swedish translations); zero runic Unicode upstream — the scholarly transliteration IS the text, damage notation stored verbatim |
| **Licenses** | menotec CC BY-NC-SA → `nc`; helipad CC BY → `attribution`; rem CC BY-SA → `attribution`; rundata ODbL + DbCL → the new `odbl` class (D40-c) |

**Research uses:** the three Germanic branches on one desk — `align` the
Gothic and West-Saxon gospels beside the *Heliand* tradition, walk
`etym`'s `gem-pro`/`gmw-pro` chains down into four new gold-lemmatized
attested languages, and read the runestones with their normalisation and
translation lanes via `--parallel`; the runic damage legend is searchable
as stored.

## 8x. The Arabic phase (`openiti`; loaded 2026-07-22, flip at the P41 gate)

| | |
|---|---|
| **Category** | The premodern Islamicate library whole: Quran and hadith, history and biography, fiqh, kalām and falsafa, the dīwāns and adab — with the Persian shelf riding the same release |
| **Languages** | Classical Arabic (`ara`, 33,294,039 passages — the corpus's largest language) and Persian (`fas`, 1,337,472; Ḥāfiẓ, Niẓāmī, ʿAṭṭār, Ibn Sīnā) |
| **Size** | **9,079 documents / 34,631,499 passages** — the D41-e first wave (primary versions + all Persian); 4,568 secondary editions + 433 manuscript documents censused skip-by-rule; 27 malformed upstream files quarantined (0.3%, baselined) |
| **Metadata** | One document per OpenITI text version (urn:nabu:openiti:<URI>); passages cited <volume>.<page>.<n>; section headers searchable as their own passages; verse hemistichs preserved as annotations; AH death-year termini feed the timeline at the next incremental rebuild |
| **License** | CC BY-NC-SA 4.0 → `nc` (MCP-excluded, never redistributed) — the grant rests entirely on the Zenodo record metadata; recorded loudly |

**Research uses:** the largest openly licensed historical corpus in
existence, locally searchable: the Arabic-script fold strips tashkeel
and bridges the Persian keyboard (ی/ي, ک/ك — Arabic-typed queries find
Ḥāfiẓ and vice versa); a millennium of authors lands on the date axis
once the timeline derives; unannotated by design — full-text and the
timeline are the instruments.

## 8i. The local shelves — canonical memory (architecture §16)

Phase 19 gave the canonical layer a doctrine for data that is **authored
or acquired, not downloaded** — local shelves with `sync_policy: local`
(no upstream, no network — `sync --all` never touches them), written only
through their sanctioned gateways. Phases 20–24 grew the family to four:

- **`local-language`** — the language-dossier shelf, **live**: one
  Markdown file per code under `canonical/local-language/` (YAML front
  matter for name/family/extras, free prose as curated context,
  provenance-headed accretion sections per witness). The owner-fired
  migration is complete — one dossier per curated code deriving the
  catalog's `language_records` (name/family/context lanes plus the
  IE-CoR witness sections), and the `config/languages.yml` ledger seed is
  retired: the dossiers are now the single home of language curation.
  Edit a dossier in any editor, `nabu sync local-language` re-derives the
  card. `nabu ingest --shelf language CODE` scaffolds a new one.
- **`local-library`** — the owner's own shelf: PDFs, scans, offprints,
  and articles as manifest-catalogued collections, page-grain text
  extraction (mutool) where a text layer exists, `research_private` by
  default — catalogued and searchable locally, never served over MCP
  without per-call opt-in, never redistributed. `related:` manifest lines
  are derived into the links journal as `kind=reference` edges. In use
  since the first ingests, mixed `research_private`/`nc`/`open` per item
  (counts private by rule). `nabu ingest`
  (ops §13) is the front door — and since P20-0 it **takes http(s) URLs**
  too, downloading first (redirects followed, atomic staging, the given
  URL recorded in the manifest's `source_url:` lane), with metadata
  candidates derived mechanically and confirmed interactively,
  AI-assisted (`--assist`), or scripted (`--yes`).
- **`local-source`** — the shelf-dossier shelf (P24-0), **live**: one
  Markdown + YAML dossier per registered source under
  `canonical/local-source/` — the curated 1–3-sentence content
  description served on `nabu list` cards and MCP `nabu_status`, plus
  themes, key-work urns, and accretion sections. One dossier per
  registered source, seeded
  by `nabu list --export-source-dossiers` and owner-edited thereafter;
  `rake site:check` gate-checks dossier-vs-library.md mention drift
  (never generates). Written only through `Nabu::SourceShelf`.
- **`local-notes`** — the owner-annotation shelf (P24-1), registered and
  **empty until the first `nabu note`**: scholia of one's own on ANY urn
  the corpus knows (documents, passages, ranges, dictionary entries),
  one YAML topic file per grouping, appended through `nabu note URN
  "TEXT"` (resolution-checked; `--force` for deliberately dangling notes
  on planned material). Notes render on `show`/`define`/`links` footers
  and are MCP-served by default, withheld wherever their target document
  is withheld.

## 9. Library-wide capabilities

- **Full-text search** with per-language folding (Greek final-sigma and
  diacritics, Latin u/v i/j, Old English æ/þ/ð, Slovene long-s, cuneiform
  determinative stripping, generic diacritic folding for IAST Sanskrit) —
  `bin/nabu search`, FTS5 under the hood.
- **Lemma search** (`search --lemma`) over the treebank shelf (§6), the
  ORACC gold layer (§8), goo300k (§8e), damaskini (§8e), Coptic
  Scriptorium (§8f), and CorPH (§8l) — **17 languages** since the
  2026-07-17 syncs (Old Irish and Bulgarian the newcomers);
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
  would cost ~15×). **Live in production**: **1,713,135 passages indexed**
  (fulltext.sqlite3 at 2.3 GB with the index aboard) — EDH joined the
  indexed scope at its 2026-07-13 sync (§8g) — and the BGU 6.1470 mid-word
  Odyssey demo runs against the real index.
- **Timeline** (P15-2, extended P16-3 and P17-2): `document_axes`
  (migration 008) holds **165,334 dated/placed records covering 163,821
  documents live** — EDH inscription dates (81,416, the largest
  contributor since that shelf's 2026-07-13 sync), HGV for the papyri
  (60,923 records), ORACC catalogue/period/regnal dates (21,558), the
  Slovene goo300k/IMP year-suffixed urns (747), Coptic manuscript dates
  (340), and TOROT chronicle AM annals (350 records over 5 chronicles).
  `search --from/--to/--century/--place` scope by signed historical year
  (negative = BCE, no year 0) and provenance; `show` prints the timeline line
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
  and **360 cognate** edges (NT got×chu, per-edge meet detail). A fourth
  kind, **reference** (local-library `related:` manifest lines, P19-4),
  has its producer shipped and zero edges until the first ingest (§8i).
- **Dictionary lookup** (`define LEMMA`, MCP `nabu_define`): §8c —
  including `define *proto-form` on the reconstruction shelves.
- **Etymology walk** (`nabu etym LEMMA`, MCP `nabu_etym`, P14): attested
  lemma → reconstruction(s) → the proto chain, with cognates and corpus
  attestation counts. The P17-3 multi-hop closure (chains through the four
  intermediate proto shelves) and the `borrowed` flag with "(loan)"
  rendering are **live**, and since 2026-07-14 so are the three
  expert-curated witnesses (§8h) — IE-CoR cognate sets, LIV verbal roots,
  and de Vaan's Leiden chains ride the same walk beside kaikki's. The
  `--long` cognate lists name each code inline from the filled names
  census (`[zle-ort · Old Ruthenian]`, `[gkm · Medieval Greek]`).
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
- **Language cards** (`nabu language CODE`, P18-4, rehomed P19-1): the
  desk reference for every code the library surfaces — the 30 corpus
  languages and the **803-code** Wiktionary etymology universe the `etym`
  cognate lists expose (`gkm`, `zle-ort`, `zlw-opl`…). One card: name,
  family, curated context, live holdings (zero fields suppressed);
  unknown codes miss honestly with a family hint; ~0.2 s. The card's
  authored layer now lives in the **`canonical/local-language/` dossier
  shelf** (one dossier per curated code, §8i; the ledger seed is
  retired), the derived names census is **filled** (160 name records from
  the owner's wiktionary resyncs — the inline `[code · Name]` rendering
  in `etym --long` is active), and the live-count joins complete the
  card.
- **Ingest — the intake front door** (`nabu ingest FILE...`, P19-5,
  URL intake P20-0/P20-1): the second sanctioned canonical-write gateway
  (after the dossier shelf's) — copies your PDF/scan/article into the
  local-library shelf (§8i, never moves the original) **or downloads an
  http(s) URL first** (redirects followed, the given URL recorded as
  `source_url:`), derives metadata candidates mechanically (PDF
  metadata, filename heuristics, sha256), validates before any append,
  and confirms interactively, AI-assisted (`--assist
  script/ingest-assist-claude` prefills the prompts with a model's
  suggestion), or scripted (`--yes` plus flags); then syncs the shelf
  and prints the minted urn. `--shelf language CODE` scaffolds a
  language dossier; `--shelf source SLUG` a source dossier (§8i).
- **The content census** (`nabu list [SOURCE]`, P22-1): the what-is-held
  view beside `status`'s sync-state view — bare, one line per shelf with
  document/passage/entry counts, languages, and the effective
  license-class mix; with a SOURCE, one shelf's card (identity, credit
  line, dossier description, per-language breakdown, timeline and facet
  coverage). `--documents`/`--entries`/`--collections` enumerate with
  filters; `--source SLUG` also joined search/export as a filter in the
  same packet.
- **Owner notes** (`nabu note URN [TEXT]`, P24-1): annotations on any urn
  the corpus knows, resolution-checked before any write, stored as plain
  YAML on the `local-notes` shelf (§8i) and rendered on
  `show`/`define`/`links`; `nabu note URN` alone reads back what you
  said, `--list` enumerates, `--force` records a deliberately dangling
  note on planned material. Notes are canonical memory — retired by
  editing the topic file, never deleted by the tooling.
- **Shelf dossiers + the drift gate** (`rake site:check`, P24-0): every
  registered source carries a curated dossier (§8i) served on `list` and
  MCP `nabu_status`; the rake task flags presence/mention drift between
  the dossiers and this document at every gate.
- **News & citability** (P19-3): the project site carries a dated News
  section with an Atom feed (`/feed.xml`, jekyll-feed) — one honest entry
  per phase gate — and the repository ships `CITATION.cff`; tagged
  releases follow the release rail (ops §12: version bump → tag → GitHub
  release → Zenodo DOI).
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
  `research_private` documents, §8e) is the first source behind that
  gate, and the local-library shelf (§8i) defaults behind it too.
- **Protection stack**: upstream deletions are attic'd, never propagated
  (`retired_upstream` documents stay searchable); content-hash ledger
  (`db/history.sqlite3`) survives rebuilds; rsync backup to mounted volume +
  restore drill (`rake ops:drill`) proves the collection is reconstructable.
- **Health**: trend rules (spike/collapse/creep/stale), golden-query replay
  (13 goldens), remote drift + license-baseline probes — with honest drift
  vocabulary (P15-7: `up=unpinned` when no baseline pin exists, never a
  fake "ok"; `health --backfill-pins` seeds pins from the ledger; P16-0:
  the license column stays silent on sources it never checked; P19: a
  BEHIND verdict older than the last ok sync renders `up=?(re-probe)`
  instead of a stale alarm — found live when a re-synced source still
  read BEHIND from a 15-hour-old cache). A
  `license_watch:` registry key (P16-5) lets `health --remote` watch a
  source's upstream license page for changes — candidates are recorded
  commented-out in `config/sources.yml`, none enabled yet (owner decision).
  P18-7 folds the mechanical **postcondition invariants** into every
  `health` run: failed-run and partial-load surfacing, flag-vs-artifact
  and synced-vs-populated mismatches, pending migrations, and a
  **quarantine baseline** in the ledger so only the delta from the audited
  anchor alarms (the EDH 27 are anchored; the standing papyri stubs go
  quiet). Its first contact with the live library correctly surfaced the
  two real pending items — among them the then-empty language-names
  census, since filled at the owner's wiktionary resyncs. An optional
  `sync --review CMD` hook (off by default) pipes each sync summary to an
  external AI reviewer.
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
