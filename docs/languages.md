# Languages of the library

**As of 2026-07-20** (post the settled full rebuild — 24,415,015 live
passages across 80 sources — which loaded the Sino and Chinese-library
axes; live inventory: every code below appears in the catalog, the lemma
index, or the reference shelf). This page explains the code system once,
then lists the significant codes with one sentence each (the corpus now
carries ~100 passage languages; the long tail of single-inscription
script variants is folded into grouped rows).

**The headline has moved east.** With Kanripo and CBETA loaded, **`lzh`
(Literary Chinese) is now the library's largest language by a wide
margin — 13.0M passages**, more than the whole rest of the corpus put
together; Ancient Greek (`grc`, 1.99M) is now second.

**The desk reference is a command (P18-4), and languages are now
file-backed (P19-1):** `nabu language CODE` explains any code this page
covers AND the **803-code** Wiktionary etymology universe the `etym`
cognate lists surface (`gkm`, `zle-ort`, `zlw-opl`…) — name, family,
curated context, and live holdings, in ~0.2 s. **The curation's home is
the `canonical/local-language/` dossier shelf (architecture §16)** — one
Markdown file per code, edit it in any editor, then `nabu sync
local-language` re-derives the card. The owner-fired migration is
complete: the dossiers on disk derive the catalog's `language_records`
(name, family, context, and the IE-CoR witness sections — that shelf's
first programmatic writer), and the `config/languages.yml` seed is
retired. The derived names census (`language_names`, from the held kaikki
extracts) is **filled** — 160 name records, feeding the inline
`[gkm · Medieval Greek]`-style rendering in `etym --long`.
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
   rule — `grc` final-sigma, `lat` u/v–i/j, `ang` æ→ae/þ,ð→th, `sl` ſ→s,
   `akk`/`sux` determinative stripping, generic diacritic folding
   elsewhere. Where a source's language differs from a tool's expectation,
   the per-document override records reality (P10-4).

## Corpus languages (documents / passages)

| Code | Language | One sentence |
|---|---|---|
| `lzh` | Literary Chinese | The library's largest language by passages (13.0M) — the Kanripo classical-Chinese repository and the CBETA Buddhist canon (Taishō + Xuzangjing), plus the HDIC Heian-period character-dictionary line. |
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
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts (incl. Assemanianus and Savvina kniga). |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `ojp` | Old Japanese | The Oxford-NINJAL Corpus of Old Japanese (ONCOJ) — gold-morphology Man'yōshū-era verse, gold-lemma language #23 (123,002 rows). |
| `ang` | Old English | Beowulf and the complete ASPR poetry plus the ISWOC prose/gospel treebank, ca. 700–1150. |
| `sga` / `mga` | Old & Middle Irish | The CorPH Palaeohibernicum and the Ogham corpus — the Celtic axis, gold-lemmatized in CorPH. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
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
**54 dictionary shelves** now hold **1,168,775 entries** total —
library.md §8c/§8h/§8j/§8k/§8m/§8o/§8q/§8s/§8t enumerate them per phase.)*

## Gold-lemma languages (searchable via `--lemma`, 23 as of today)

`sux, san, egy, lat, grc, orv, hbo, cop, sl, chu, ojp, akk, sga, got,
bul, ang, xcl, arc, hit, peo, uga, elx, xhu` — the treebanks, ORACC,
goo300k, DCS, ONCOJ, the Hebrew/Egyptian shelves, and Coptic Scriptorium
feed these **12,597,062 gold rows** (ordered above by pool size: `san`
5.54M and `sux` 2.97M lead). A parallel **silver layer** adds 8,000,317
machine-suggested rows in 8 languages (chiefly Greek/Diorisis 7.54M and
Hittite/TLHdig), always labelled. Everything else is full-text-searchable
but not lemma-searchable (yet — see improvements §3.1 for the cluster
plan to project lemmas onto the rest). The newest gold joiner is **`ojp`
as #23** (Old Japanese, 123,002 rows from ONCOJ).

---

*Maintenance: this page is refreshed at phase gates alongside library.md
(§10 duty). The authoritative per-source assignments live in each
adapter's manifest; the curated per-language prose lives in the
`canonical/local-language/` dossiers (edit there, not here); folding
rules in conventions §9; the proto-code rationale in conventions §4.*
