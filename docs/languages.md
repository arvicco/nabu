# Languages of the library

**As of 2026-08-04** (post the P57 full rebuild — 68,408,109 live
passages across the 126-row registry; live inventory: every code below
appears in the catalog, the lemma index, or the reference shelf). This
page explains the code system once, then lists the significant codes
with one sentence each (the corpus now carries 122 document language
codes; the long tail of single-inscription script variants is folded
into grouped rows).

**The headline has moved again — to the Islamicate world.** With the
OpenITI load (2026-07-22 evening), **`ara` (Classical Arabic) is the
library's largest language — 33.3M passages**, more than the whole
pre-Arabic corpus combined; `lzh` (Literary Chinese, 13.4M) is second,
Sumerian (3.04M) third, Ancient Greek (3.01M) fourth, and Japanese
(2.98M) fifth.

**The desk reference is a command (P18-4), and languages are now
file-backed (P19-1):** `nabu language CODE` explains any code this page
covers AND the **803-code** Wiktionary etymology universe the `etym`
cognate lists surface (`gkm`, `zle-ort`, `zlw-opl`…) — name, family,
curated context, live holdings, and (since 2026-07-28) the related
research axes: an `axes:` line naming the desks whose shelves hold the
code, in ~0.2 s. **The curation's home is
the `canonical/local-language/` dossier shelf (architecture §16)** — one
Markdown file per code, edit it in any editor, then `nabu sync
local-language` re-derives the card. The owner-fired migration is
complete: the dossiers on disk derive the catalog's `language_records`
(name, family, context, and the IE-CoR witness sections — that shelf's
first programmatic writer), and the `config/languages.yml` seed is
retired. The derived names census (`language_names`, from the held kaikki
extracts) is **filled** — 160 name records, feeding the inline
`[gkm · Medieval Greek]`-style rendering in `etym --long` (superseded,
where nabu-lects is synced, by the resolved-lect reading — "The lect
layer" below).
`nabu ingest --shelf language CODE` scaffolds a new dossier;
`nabu language --list` prints the held languages.

## The system, in five rules

1. **Codes are BCP-47-shaped**: a primary language subtag (ISO 639: `grc`,
   `lat`, `chu`…), optionally followed by a **script subtag** (`san-Latn` =
   Sanskrit in Latin transliteration) or another qualifier. Validation is
   shape-only, so a few deliberate non-ISO codes pass (rule 4).
2. **The code names the language of the passage text as stored** — not the
   manuscript's, not the modern nation's. GRETIL stores IAST romanization,
   so its Sanskrit is `san-Latn`; the UD Vedic treebank stores Devanagari-
   independent CoNLL-U, so it is plain `san`. CCMH stores the corpus's own
   7-bit transliteration but the *language* is still `chu`.
3. **Historical stages ride the nearest standard code, documented**: Old
   East Slavic, Middle Russian, and Ruthenian all live under `orv`
   (following Universal Dependencies); Early Modern Slovenian and the
   ~1000 CE Freising Manuscripts under `sl` (no better subtag exists —
   an acknowledged anachronism).
4. **Reconstruction shelves use Wiktionary's etymology codes verbatim**
   (`sla-pro`, `ine-pro`, `gem-pro`) — non-ISO, kept because they join
   directly against the upstream descendants data (conventions §4).
5. **Search folding is per-language** (conventions §9): the code picks the
   rule — `grc` final-sigma, `lat` u/v–i/j, `ang` æ→ae/þ,ð→th,
   `sl`/`gmh` ſ→s (Slovenian and the ReM Middle High German diplomatic
   text), `akk`/`sux` determinative stripping, generic diacritic folding
   elsewhere. Where a source's language differs from a tool's expectation,
   the per-document override records reality (P10-4).

## The lect layer

Everything above is the code system this library has always spoken —
ISO-639-shaped tags, one per stored passage/entry, folded and searched as
documented in the five rules. **nabu-lects** (P57-3/4;
github.com/arvicco/nabu-lects) is a SEPARATE, OPTIONAL module layered on
top: a small curated registry of *lects* — language varieties identified by
genealogical anchor × historical stage × variety × orthography
(`lat:med` = Medieval Latin; `grc:byz` = Byzantine Greek; `ine:pro` =
Proto-Indo-European) — plus a universal mapping from the codes above onto
them. It answers a question the code system alone cannot: not just "what
language is this passage tagged," but "which SPECIFIC historical stage of
that language, and is it a reconstruction or attested."

**It changes nothing about storage.** Stored codes are exactly as documented
above, forever (rule 2's promise). `Nabu::Lects` (`lib/nabu/lects.rb`) is a
pure READ resolver: `#resolve(code, source:, urn:)` maps a stored code onto
a lect id, `#lect(id)` looks up its name/band/mode, `#reconstructed?(id)`
asks whether it is a comparative-method reconstruction (a registry field,
never a guess from the code's spelling — rule 4's `-pro` convention is a
Wiktionary joining convention, not evidence of reconstruction; nabu-lects
registers the real distinction, e.g. Rundata's `gmq-pro` runic inscriptions
are ATTESTED epigraphy filed under a proto-looking tag).

**Resolution precedence, highest first**: a per-document ruling (the lect
journal, `db/lects.sqlite3` — P58-1: urn-keyed assignments that survive
`nabu rebuild` and ride backups, written by `nabu lect assign` at hand
grain and by the ratified compilers at batch grain: `lect apply-rules`
turns period/corpus facet values into stages, `lect infer-dates` stages a
document whose date interval sits inside exactly one stage band; every
row states its basis and `lect check-dates` audits the lot against the
documents' own dates) → a per-source override
(`config/lect_overrides.yml`, Nabu-authored — what one particular source's
use of a code actually means in its holdings, e.g. DÉRom's `la-vul` really
means the reconstructed `roa:pro`, not Wiktionary's attested-register
default) → the module's own universal codemap → identity (an unmapped code
resolves to itself as a bare anchor — always legal, honest coarseness).

**Feature-detected everywhere it surfaces, never required**: `Nabu::Lects
.load_default` returns `nil` when `canonical/nabu-lects` has not been
synced (`nabu sync nabu-lects`), and every consumer below degrades to its
pre-P57-4 behavior byte-for-byte in that case — the cldf-spine/nabu-data
posture, same as every other optional module this library carries (Pleiades,
the Oracc Sign List, Tibetan word segmentation).

Since P58-4 the resolved lect is also MATERIALIZED as an ordinary
document facet (`document_facets`, facet `lect`, rows only where the
resolution differs from the bare code — "no row means identity"), so the
stage is a first-class query axis: `show` prints it on the facets line,
`search --lect` filters by it at every grain including per-document
rulings, and the `language` ladder counts from it. As of 4 August 2026
the journal holds 408,884 assignments and the facet 491,648 rows.

Consumers as of P57-4 (ladder counts facet-backed since P58-6):

- **`nabu language CODE`** grows a `stages:` ladder when the code is a
  registered anchor with stages: each stage ord-sorted with its band and
  live document counts (aggregated by resolving every held (language,
  source) pair through the registry); reconstructed stages carry a leading
  asterisk; codes that resolve to the bare anchor group under one honest
  `unstaged` line.
- **`search --lect LECT-ID`** (CLI) and **`nabu_search`'s `lect` parameter**
  (MCP) filter hits to passages whose (language, source) resolves to the
  given lect or a MORE SPECIFIC one under it — prefix semantics over the
  `:`/`/`/`@` axis grammar (`--lect lat` matches `lat:med`; `--lect lat:med`
  matches `lat:med` and `lat:med/xyz`, not `lat:cla`). A resolution-level
  filter: stored codes are never touched. Errors, naming the module, when
  nabu-lects is not synced.
- **`nabu etym`**'s reconstruction predicate (the display asterisk, and the
  reconstruction-shelf scope for a direct `*headword` lookup) resolves the
  dictionary's (language, source) and asks `#reconstructed?` instead of
  testing the code for a `-pro` suffix — the class of correction Rundata's
  `gmq-pro` needed. Its cognate-language brackets also prefer the resolved
  lect id + composed name (`[grc:byz · Byzantine Greek]` for `gkm`, the
  codemap default) over the older kaikki-census name where nabu-lects
  supplies one — display-only, additive.

Absent the module, every one of the above reads exactly as it did before
P57-4: no ladder section, no `--lect` flag (a clear error naming the
module if used), the old `-pro`-suffix string test, the old bracket names.

## Corpus languages (documents / passages)

| Code | Language | One sentence |
|---|---|---|
| `lzh` | Literary Chinese | The library's largest language by passages (13.0M) — the Kanripo classical-Chinese repository and the CBETA Buddhist canon (Taishō + Xuzangjing), plus the HDIC Heian-period character-dictionary line. Since P37-2, traditional/simplified/z-variant spellings fold to one search skeleton (conventions §9). |
| `grc` | Ancient Greek | The largest *Western* language and second overall (1.99M passages) — Homer through the papyri to Swete's Septuagint, both Greek NTs, and the EDH bilinguals, polytonic. |
| `sux` | Sumerian | The language isolate of the earliest written literature, from Ur III royal inscriptions to the great lexical lists — 3.03M passages, the largest cuneiform language. |
| `akk` | Akkadian | East Semitic language of Babylon and Assyria, held in transliteration with ORACC's gold lemmas (SAA letters, omens, royal inscriptions) — now joined at scale by the CDLI and eBL fragment shelves. |
| `san-Latn` | Sanskrit (IAST romanization) | The GRETIL, SARIT, and DCS shelves — Vedas to early-modern śāstra — stored in the international transliteration scheme with accents preserved (0.84M passages). |
| `san` | Sanskrit (Devanagari / CoNLL-U) | The UD Vedic treebank and the gold-lemmatized Digital Corpus of Sanskrit; `san-Deva` holds the Devanagari-scripted SARIT slice separately. |
| `pli` | Pali | The SuttaCentral Tipiṭaka — the segmented Pali canon (0.44M passages), aligned to its English and the Chinese Āgamas. |
| `sl` | Slovenian (historical) | Early Modern print (Dalmatin 1584 → 1899), the IMP historical-Slovene corpus, and, by lineage, the ~1000 CE Freising Manuscripts (0.41M passages). |
| `hit` | Hittite | The Anatolian cuneiform corpus at fragment scale — the TLHdig transliterations beside the lexical-list entries, gold- and silver-lemmatized (0.36M passages). |
| `syc` | Classical Syriac | The Digital Syriac Corpus (632 TEI documents) and the ETCBC Peshitta OT — extending the Aramaic axis by a millennium (0.17M passages). |
| `egy` | Egyptian | The Ancient Egyptian Sentences (AES/TLA) and Late-Egyptian/Demotic Hugging-Face shelves — 0.12M gold-lemmatized passages from the Pyramid Texts onward; `egy-Egyd` holds a couple of Demotic papyri separately. |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine bible, papyrus fragments — and, since the EDH sync, ~81,000 inscriptions (library.md §8g); 0.80M passages. |
| `cop` | Coptic | The last stage of Egyptian: documentary papyri plus the literary Coptic Scriptorium shelf in Sahidic and Bohairic, gold-lemmatized (233,020 rows; library.md §8f). |
| `qpc` | Proto-cuneiform | The pre-linguistic administrative tablets of the late 4th millennium BCE (dcclt archaic lists) — signs before language. |
| `hbo` | Biblical Hebrew | The Masoretic shelves — OSHB Westminster Leningrad, the BHSA/ETCBC treebank, the Dead Sea Scrolls — gold-lemmatized, NFC-exempt (0.09M passages). |
| `xeb` | Eblaite | The eBL/Ebla East-Semitic lexical material from the cuneiform fragment shelves (0.05M passages). |
| `arc` | Aramaic / Targumic | The Sefaria Targum shelf, DSS Aramaic, and cuneiform-shelf traces — now 0.05M passages, gold-lemmatized where the Targums carry it. |
| `ara` | Arabic | **The library's largest language (33,294,039 passages, loaded 2026-07-22)** — the OpenITI corpus: hadith, history and biography, law, falsafa, the dīwāns; unannotated (no gold lemmas — full-text and the AH timeline are the instruments), cross-searchable with Persian under the Arabic-script fold. |
| `fas` | Persian | The Persian shelf of OpenITI (1,337,472 passages, loaded 2026-07-22 — Ḥāfiẓ, Niẓāmī, ʿAṭṭār, Ibn Sīnā), minted from the `-per*` URI suffix — never `per`, so the fold keys on it: folded to the same Arabic-script skeleton as ara (ی/ي, ک/ك), either keyboard finds either language. |
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts (incl. Assemanianus and Savvina kniga). |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `ojp` | Old Japanese | The Oxford-NINJAL Corpus of Old Japanese (ONCOJ) — gold-morphology Man'yōshū-era verse, gold-lemma language #23 (123,002 rows). |
| `ang` | Old English | Beowulf and the complete ASPR poetry plus the ISWOC prose/gospel treebank, ca. 700–1150. |
| `sga` / `mga` | Old & Middle Irish | The CorPH Palaeohibernicum and the Ogham corpus — the Celtic axis, gold-lemmatized in CorPH. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
| `gmh` | Middle High German | The ReM reference corpus (1050–1350), synced live 2026-07-22: 406 manually annotated texts / 355,449 manuscript lines, diplomatic layer stored (long ſ folds to s — rule 5) — and instantly the corpus's **third-largest gold-lemma pool** (2.10M rows). |
| `gml` | Middle Low German (incl. Low Rhenish) | The ReN reference corpus (1200–1650), adapter landed P46-5 (`ren`, `wired: false` — counts land at the owner-fired first sync): 161 gold pos+msd+lemma texts + 74 transcribed-only, expected ~297,594 manuscript lines; the 28 texts upstream classes *niederrheinisch* ride `gml` with an `upstream_language` marker (no `dum` split invented). |
| `non` / `gmq-pro` | Old Norse / Proto-Norse | The North Germanic lane (synced live 2026-07-22): Menotec's seven Old Norwegian treebanks and the Poetic Edda of Codex Regius (gold PROIEL-scheme morphology), plus Rundata's runic corpus in transliteration with its Old-West-Norse normalisation lane — 39,923 passages; the urnordisk-dated inscriptions carry `gmq-pro` (the wiktionary-recon proto-code convention of rule 4 — no ISO code exists; 822 passages). |
| `osx` | Old Saxon | The *Heliand* (HeliPaD, synced live 2026-07-22): 3,549 syntactically parsed tree blocks with gold form-lemma pairs — the 9th-century gospel harmony beside its Gothic and Old English gospel cousins. |
| `is` | Icelandic (diachronic) | IcePaHC via UD, live 2026-07-22 — the 12th–21st c. under the one modern tag (the `orv`/Middle-Russian precedent of rule 3): 44,029 passages whose 812,484 gold rows enter straight at #4 of the lemma pools. |
| `jpn` | Japanese | The Aozora Bunko reading desk (synced live 2026-07-21): 2.99M passages of Meiji-and-later public-domain literature, ruby readings as annotations, kyūjitai works reachable through the reform fold (rule 5 / conventions §9). |
| `xcl` / `xhu` / `uga` / `elx` / `peo` | Classical Armenian / Hurrian / Ugaritic / Elamite / Old Persian | The 5th-century Armenian NT plus lexical-list and inscriptional traces from the cuneiform and Achaemenid shelves — small but gold-lemmatized. |
| `ett` / `osc` / `xlu` / `xtg` / `xfa` / `xve` / `scx` / `xly` / `xpu` / `xrr` | Etruscan / Oscan / Luwian / …the pre-Roman epigraphic long tail | The Italic, Anatolian, and Mediterranean inscription corpora (OpenEtruscan, CEIPoM, ItAnt, LexLep, TIR, I.Sicily) — dozens of languages, mostly script-tagged (`-Grek`/`-Latn`/`-Ital`), many at a few hundred passages each. |
| `eng` / `en` / `ger` / `deu` / `ita` / `pol` / `fra` | Modern translation tags | The facing-translation layer (Perseus/First1K, WEB/Vulgate, SuttaCentral, Freising) — never originals; `en`/`deu` are legacy strays standardizing on `eng`/`ger`. |
| `und` | Undetermined | Inscriptions (chiefly EDH and epigraphic-shelf) whose language the upstream record could not determine — coded honestly rather than guessed. |

## Reference-shelf languages (dictionaries)

| Code | Dictionary | One sentence |
|---|---|---|
| `grc` | LSJ | The Greek-English lexicon, 116,497 entries, citations resolved into the corpus. |
| `lat` | Lewis & Short | The Latin dictionary, 51,636 entries, same resolution. |
| `san` | Monier-Williams | The Sanskrit-English dictionary (1899), 193,890 entries live since 2026-07-13 — SLP1↔IAST transcoded lookup, RV./BhP. citations resolving to GRETIL urns. |
| `ang` | Bosworth-Toller | The Anglo-Saxon dictionary, 62,815 entries, æ/þ/ð-folded lookup. |
| `chu` | Wiktionary-OCS | 4,615 crowd-sourced OCS entries whose etymologies seed the reconstruction crosswalk (2,210 descendant edges live). |
| `sla-pro` | Proto-Slavic (reconstructed) | 5,431 reconstructed headwords with descendant trees naming attested reflexes. |
| `ine-pro` | Proto-Indo-European (reconstructed) | 1,905 roots — the trunk the `etym` command ascends to. |
| `gem-pro` | Proto-Germanic (reconstructed) | 5,717 reconstructions bridging PIE to Gothic and Old English. |
| `ine-bsl-pro` | Proto-Balto-Slavic (reconstructed) | 491 headwords, live since the P17-3 resync — the STRUCTURAL intermediate shelf (PIE → PBS → Proto-Slavic) the multi-hop closure walks. |
| `gmw-pro` | Proto-West Germanic (reconstructed) | 5,551 headwords — the Old English proto desk, and the second intermediate shelf (Proto-Germanic → PWG → ang). |
| `itc-pro` | Proto-Italic (reconstructed) | 745 headwords bridging PIE to Latin (best record-level crosswalk join). |
| `iir-pro` | Proto-Indo-Iranian (reconstructed) | 799 headwords: Sanskrit via romanization + the flagged Iranian-loan layer in Armenian. |
| `ine` | IE-CoR (cognate sets) | 4,981 expert-curated Indo-European cognate sets under the collective `ine` tag, live since 2026-07-14 — the third etymological witness, 26,325 reflex edges, 2,308 loan-flagged. |
| `ine-pro` | LIV-LOD | 305 PIE verbal etymons with stem types (LiLa Turtle edition), live since 2026-07-14 — 374 Latin reflex edges. |
| `ine-pro` / `itc-pro` | de Vaan EDL | De Vaan's *Etymological Dictionary of Latin* (LiLa skeleton, `nc`): 2,860 etymons across two shelves, live since 2026-07-14 — the lat → Proto-Italic → PIE Leiden chains. |
| `ine-pro` / `rus` / `gem-pro` / `bat-pro` | StarLing (Pokorny · PIET · Vasmer · Germanic · Baltic) | The classical etymological bases digitized by the Tower of Babel project — Pokorny (2,222), the PIET Indo-European base (3,291), Vasmer's Russian (18,239), plus the Germanic and Baltic subordinate bases; library.md §8j. |
| `hbo` | BDB · SDBH · OSHB lexicon | The Masoretic desk: Brown-Driver-Briggs (11,845), the UBS Dictionary of Biblical Hebrew (7,932), and the Strong's-indexed OSHB lexicon; library.md §8q. |
| `egy` | AED · CCL | The TLA Ägyptische Wortliste (35,052 entries) and the Comprehensive Coptic Lexicon (11,284) — the Egyptian→Coptic dictionary chain; library.md §8o. |
| `sl` | Pleteršnik · JSV · Besedje16 | The Slovene historical lexica (Pleteršnik 1894, 103,185 entries; Janez Svetokriški; the 16th-century word-list) — diachronic Slovene on one desk; library.md §8k. |
| `sga` / `mga` / `wlm` / `xum` / `ett` / `ojp` | Wiktionary recon shelves | Old & Middle Irish, Middle Welsh, Umbrian, Etruscan, and Old Japanese kaikki extracts — the small crosswalk shelves that carry `etym` into Celtic, Sabellic, and the Sino/Japonic axes. |
| `och` / `ltc` | Baxter-Sagart · Guangyun · TLS | Old Chinese reconstruction and Middle Chinese phonology (Baxter-Sagart 2014, the 廣韻 Guangyun rime dictionary, 25,336 entries) plus the Thesaurus Linguae Sericae concept/word nets; library.md §8s/§8t. |
| `zho` / `lzh` | Unihan · HDIC quartet | The Unicode Han Database (65,092 codepoint entries) and the HDIC Heian character dictionaries (Yuanben/Songben Yupian, Tenrei Banshō Meigi, Shinsen Jikyō) — Literary-Chinese lexicography by codepoint; library.md §8s. |
| `jpn` / `ojp` | JMdict · KANJIDIC2 · ONCOJ lexicon | The EDRDG Japanese dictionaries (JMdict 217,951 glosses; KANJIDIC2) and the Old-Japanese ONCOJ lexicon; library.md §8s. |

*(All seven proto shelves are live — `define`/`etym` walk them with
multi-hop closure and per-edge "(loan)" flags — the Phase-18 trio
(`iecor`, `liv`, `edl`) synced live 2026-07-14, and the Phase-30–33
expansion added the StarLing bases, the Hebrew/Egyptian/Slovenian
desks, and the Sino/Japanese shelves. The table above is representative:
**56 dictionary shelves** now hold **1,310,763 entries** total
(2026-07-22 census) —
library.md §8c/§8h/§8j/§8k/§8m/§8o/§8q/§8s/§8t enumerate them per phase.)*

## Gold-lemma languages (searchable via `--lemma`, 28 as of today)

`san, sux, gmh, is, egy, lat, grc, orv, lzh, akk, hbo, non, cop, sl,
chu, ojp, sga, got, osx, bul, ang, xcl, peo, arc, hit, xhu, elx, uga` —
the treebanks, ORACC, goo300k, DCS, ONCOJ, the Hebrew/Egyptian shelves,
Coptic Scriptorium, and the P40 Germanic shelves feed these
**16,240,531 gold rows** (ordered above by pool size: `san` 5.54M and
`sux` 2.97M lead; **`gmh` debuts third at 2.10M** — the ReM sync of
2026-07-22 — and the owner's same-day `sync ud` landed `is` at **#4**
(IcePaHC, 812K) plus `lzh`'s first gold lane (427K), with `non` 258K
and `osx` 47K in the same wave). A parallel **silver layer** adds
8,244,309 machine-suggested rows in 8 languages (chiefly Greek/Diorisis
7.54M and Hittite/TLHdig), always labelled. Everything else is
full-text-searchable but not lemma-searchable (yet — see improvements
§3.1 for the cluster plan to project lemmas onto the rest).

---

*Maintenance: this page is refreshed at phase gates alongside library.md
(§10 duty). The authoritative per-source assignments live in each
adapter's manifest; the curated per-language prose lives in the
`canonical/local-language/` dossiers (edit there, not here); folding
rules in conventions §9; the proto-code rationale in conventions §4.*
