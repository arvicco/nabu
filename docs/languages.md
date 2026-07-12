# Languages of the library

**As of 2026-07-12** (live inventory — every code below appears in the
catalog, the lemma index, or the reference shelf). This page explains the
code system once, then lists every code with one sentence each.

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
| `grc` | Ancient Greek | The library's largest language — Homer through the papyri to Swete's Septuagint and both Greek NTs, polytonic. |
| `akk` | Akkadian | East Semitic language of Babylon and Assyria, held in transliteration with ORACC's gold lemmas (SAA letters, omens, royal inscriptions). |
| `eng` | English | The translation layer — Perseus/First1K editions, WEB bible, SAA tablet translations, Freising rendering; never an original. |
| `sux` | Sumerian | The language isolate of the earliest written literature, from Ur III royal inscriptions to the great lexical lists. |
| `cop` | Coptic | The last stage of Egyptian, in the documentary papyri of Christian Egypt. |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine bible, and papyrus fragments. |
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
| `pol` / `ita` / `ger` | Polish / Italian / German | Modern scholarly translations of the Freising Manuscripts (one document each). |
| `grc-Latn` | Greek (romanized) | Two papyri whose Greek survives only in Latin transliteration. |
| `egy-Egyd` | Egyptian (Demotic) | Two Demotic documentary papyri. |
| `xct` / `xct-Latn` | Classical Tibetan | A stray GRETIL text (native + transliterated). |
| `xcl` | Classical Armenian | The 5th-century Armenian New Testament, gold-lemmatized. |
| `uga` | Ugaritic | A lexical-list trace from the cuneiform shelf. |
| `ta-Latn` | Tamil (romanized) | One GRETIL stray. |
| `arc` | Aramaic | A single cuneiform-shelf document. |
| `en` | English (legacy tag) | One GRETIL stray using the 2-letter tag; everything else standardizes on `eng`. |

## Reference-shelf languages (dictionaries)

| Code | Dictionary | One sentence |
|---|---|---|
| `grc` | LSJ | The Greek-English lexicon, 116k entries, citations resolved into the corpus. |
| `lat` | Lewis & Short | The Latin dictionary, 52k entries, same resolution. |
| `ang` | Bosworth-Toller | The Anglo-Saxon dictionary, 63k entries, æ/þ/ð-folded lookup. |
| `chu` | Wiktionary-OCS | 4.6k crowd-sourced OCS entries whose etymologies seed the reconstruction crosswalk. |
| `sla-pro` | Proto-Slavic (reconstructed) | ~5.2k reconstructed headwords with descendant trees naming attested reflexes. |
| `ine-pro` | Proto-Indo-European (reconstructed) | ~1.8k roots — the trunk the `etym` command ascends to. |
| `gem-pro` | Proto-Germanic (reconstructed) | ~5.6k reconstructions bridging PIE to Gothic and Old English. |

## Gold-lemma languages (searchable via `--lemma`, 14 as of today)

`lat, grc, orv, san, sux, chu, akk, got, ang, xcl, sl, xhu, uga, hit` —
the treebanks, ORACC, and goo300k feed these; everything else is
full-text-searchable but not lemma-searchable (yet — see improvements
§3.1 for the cluster plan to project lemmas onto the rest).

---

*Maintenance: this page is refreshed at phase gates alongside library.md
(§10 duty). The authoritative per-source assignments live in each
adapter's manifest; folding rules in conventions §9; the proto-code
rationale in conventions §4.*
