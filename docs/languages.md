# Languages of the library

**As of 2026-07-14** (post Phase 19 — live inventory: every code below
appears in the catalog, the lemma index, or the reference shelf; the
Phase-18 etymological trio synced live 2026-07-14, so nothing in the
dictionary table is pending). This page explains the code system once,
then lists every code with one sentence each.

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
| `grc` | Ancient Greek | The library's largest language by passages — Homer through the papyri to Swete's Septuagint, both Greek NTs, and the EDH bilinguals, polytonic. |
| `akk` | Akkadian | East Semitic language of Babylon and Assyria, held in transliteration with ORACC's gold lemmas (SAA letters, omens, royal inscriptions). |
| `eng` | English | The translation layer — Perseus/First1K editions, WEB bible, SAA tablet translations, Freising rendering; never an original. |
| `sux` | Sumerian | The language isolate of the earliest written literature, from Ur III royal inscriptions to the great lexical lists. |
| `cop` | Coptic | The last stage of Egyptian: 2,063 documentary papyri plus the literary Coptic Scriptorium shelf, live since 2026-07-13 — 482 docs / 74,169 passages in Sahidic and Bohairic, gold-lemma language #15 (233,020 rows; library.md §8f). |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine bible, papyrus fragments — and, since the EDH sync, 80,561 inscriptions (library.md §8g), making it the largest language by documents. |
| `san-Latn` | Sanskrit (IAST romanization) | The GRETIL shelf — Vedas to early-modern śāstra — stored in the international transliteration scheme with accents preserved. |
| `sl` | Slovenian (historical) | Early Modern print (Dalmatin 1584 → 1899) and, by lineage, the ~1000 CE Freising Manuscripts. |
| `qpc` | Proto-cuneiform | The pre-linguistic administrative tablets of the late 4th millennium BCE (dcclt archaic lists) — signs before language. |
| `ang` | Old English | Beowulf and the complete ASPR poetry plus the ISWOC prose/gospel treebank, ca. 700–1150. |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts (incl. Assemanianus and Savvina kniga). |
| `ar` | Arabic | A handful of early Islamic-era documentary papyri. |
| `hit` | Hittite | Anatolian entries in the multilingual cuneiform lexical lists. |
| `xhu` | Hurrian | Isolated lexical-list column entries from the cuneiform shelf. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
| `san` | Sanskrit (Vedic, CoNLL-U) | The UD Vedic treebank's gold-annotated sentences. |
| `pol` / `ita` / `ger` | Polish / Italian / German | Modern scholarly translations of the Freising Manuscripts (three documents each — one per manuscript). |
| `grc-Latn` | Greek (romanized) | Two papyri whose Greek survives only in Latin transliteration. |
| `egy-Egyd` | Egyptian (Demotic) | Two Demotic documentary papyri. |
| `xct` / `xct-Latn` | Classical Tibetan | A stray GRETIL text (native + transliterated). |
| `xcl` | Classical Armenian | The 5th-century Armenian New Testament, gold-lemmatized. |
| `uga` | Ugaritic | A lexical-list trace from the cuneiform shelf. |
| `ta-Latn` | Tamil (romanized) | One GRETIL stray. |
| `arc` | Aramaic | A single cuneiform-shelf document. |
| `en` | English (legacy tag) | One GRETIL stray using the 2-letter tag; everything else standardizes on `eng`. |
| `und` | Undetermined | Five EDH inscriptions whose language the upstream record could not determine — coded honestly rather than guessed. |

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

*(All seven proto shelves are live — `define`/`etym` walk them with
multi-hop closure and per-edge "(loan)" flags — and the Phase-18 trio
(`iecor`, `liv`, `edl`) is **synced live since 2026-07-14**, adding three
independent expert-curated witnesses beside the Wiktionary-derived
chains; library.md §8h.)*

## Gold-lemma languages (searchable via `--lemma`, 15 as of today)

`lat, grc, orv, akk, cop, sl, san, sux, chu, got, ang, xcl, xhu, uga,
hit` — the treebanks, ORACC, goo300k, and (since 2026-07-13) Coptic
Scriptorium feed these 2,852,069 rows; everything else is
full-text-searchable but not lemma-searchable (yet — see improvements
§3.1 for the cluster plan to project lemmas onto the rest). **`cop` is
live as #15**: 233,020 gold lemma rows from the coptic-scriptorium shelf,
the fifth-largest lemma pool in the library.

---

*Maintenance: this page is refreshed at phase gates alongside library.md
(§10 duty). The authoritative per-source assignments live in each
adapter's manifest; the curated per-language prose lives in the
`canonical/local-language/` dossiers (edit there, not here); folding
rules in conventions §9; the proto-code rationale in conventions §4.*
