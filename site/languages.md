---
title: Languages
permalink: /languages/
description: >-
  The languages of the Nabu library: corpus languages, reference-shelf
  dictionaries, and the gold-lemma index, with the code conventions.
---

As of **19 July 2026** — a live inventory: every code below appears in the
catalog, the lemma index, or the reference shelf. The maintained original of
this page is
[docs/languages.md](https://github.com/arvicco/nabu/blob/main/docs/languages.md)
in the repository.

The library also carries this reference as a command: `nabu language CODE`
explains any code the tools surface — the corpus languages below and the
803 Wiktionary etymology codes that appear in `etym` cognate lists — on
one card: name, family, curated historical context, and live holdings. An
unknown code is reported honestly, with a family hint. Since 14 July 2026
the curated layer behind these cards is file-backed: one plain Markdown
dossier per language code (213 dossiers) on the library's local
language-dossier shelf, editable in any editor and re-derived into the
catalog on sync.

## The code system

1. **Codes are BCP-47-shaped**: a primary ISO 639 subtag (`grc`, `lat`,
   `chu`…), optionally followed by a script subtag (`san-Latn` is Sanskrit
   in Latin transliteration) or another qualifier.
2. **The code names the language of the passage text as stored** — not the
   manuscript's script, not the modern nation's. GRETIL stores IAST
   romanization, so its Sanskrit is `san-Latn`; the CCMH codices store a
   7-bit transliteration, but the language is still `chu`.
3. **Historical stages ride the nearest standard code, documented**: Old
   East Slavic, Middle Russian, and Ruthenian all live under `orv`
   (following Universal Dependencies); Early Modern Slovenian and the
   Freising Manuscripts under `sl` — an acknowledged anachronism, since no
   better subtag exists.
4. **Reconstruction shelves use Wiktionary's etymology codes verbatim**
   (`sla-pro`, `ine-pro`, `gem-pro`) — non-ISO, kept because they join
   directly against the upstream descendants data.
5. **Search folding is per-language**: the code selects the rule — Greek
   final sigma and diacritics, Latin u/v and i/j, Old English æ/þ/ð,
   Slovene long s, cuneiform determinative stripping, and generic diacritic
   folding elsewhere.

## Corpus languages

| Code | Language | Notes |
|---|---|---|
| `grc` | Ancient Greek | The library's largest language by passages — Homer through the papyri to Swete's Septuagint, both Greek New Testaments, and the inscriptional bilinguals, polytonic. |
| `akk` | Akkadian | East Semitic language of Babylon and Assyria: ORACC's gold-lemmatized corpora (SAA letters, omens, royal inscriptions) plus the CDLI transliteration mass and the eBL Fragmentarium with inline English (grown 19 July 2026). |
| `eng` | English | The translation layer — Perseus and First1K editions, the WEB Bible, tablet translations; never an original. |
| `sux` | Sumerian | The language isolate of the earliest written literature — the ETCSL literary canon in two scholarly editions (Oxford's hand-lemmatized composites and ORACC's ePSD2), the Ur III administrative mass, and the great lexical lists (grown 19 July 2026). |
| `cop` | Coptic | The last stage of Egyptian: documentary papyri plus the literary Coptic Scriptorium shelf (Sahidic and Bohairic, live since 13 July 2026), the fifteenth lemma-searchable language. |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine Bible, papyrus fragments, and 80,561 inscriptions — the largest language by documents. |
| `san-Latn` | Sanskrit (IAST) | The GRETIL shelf — Vedas to early-modern śāstra — in international transliteration with accents preserved. |
| `sl` | Slovenian (historical) | Early Modern print (Dalmatin 1584 to 1899) and, by lineage, the ~1000 CE Freising Manuscripts. |
| `qpc` | Proto-cuneiform | The pre-linguistic administrative tablets of the late fourth millennium BCE — signs before language. |
| `ang` | Old English | Beowulf and the complete ASPR poetry, plus the ISWOC prose and gospel treebank, ca. 700–1150. |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts. |
| `sga` | Old / Early Irish | The Celtic axis's keystone (added 17 July 2026): CorPH's gold-lemmatized texts and gloss corpora, 7th–10th c., plus the two Old Irish UD treebanks — a new gold-lemma language. |
| `xtg` | Gaulish | The 428 RIIG inscriptions in Gallo-Greek and Gallo-Latin scripts (added 17 July 2026). |
| `pgl` | Primitive Irish | The ogham stones, in real Ogham codepoints with aligned transliteration layers (added 17 July 2026; held `nc` pending a license clarification). |
| `bul` | Bulgarian (pre-standardized) | The damaskini witnesses of the Church Slavonic–Bulgarian continuum, 15th–19th c., gold-annotated (added 17 July 2026). |
| `ar` | Arabic | A handful of early Islamic-era documentary papyri. |
| `hit` | Hittite | The TLHdig corpus — 23,486 tablet manuscripts, >98% of published Hittite fragments, with candidate morphology at an honest silver tier — plus the gold HitTB treebank and the lexical-list traces (grown 19 July 2026). |
| `xhu` | Hurrian | Isolated lexical-list column entries from the cuneiform shelf. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
| `san` | Sanskrit (Vedic) | The Universal Dependencies Vedic treebank's gold-annotated sentences. |
| `pol` / `ita` / `ger` / `deu` | Polish / Italian / German | Modern scholarly translation layers (Freising, ItAnt, the Egyptian shelves — `ger` and `deu` are both accepted at every query filter). |
| `grc-Latn` | Greek (romanized) | Two papyri whose Greek survives only in Latin transliteration. |
| `egy` | Egyptian | The whole span in Unicode transliteration (added 18 July 2026): 101,793 gold-lemmatized sentences from the Pyramid Texts to the sawlit literary canon, plus 13,383 Demotic and 3,606 Late Egyptian sentences from the TLA — with German translation siblings throughout. |
| `hbo` | Biblical Hebrew | The Masoretic text of the Leningrad Codex, byte-verbatim (the combining-mark order is never normalized), fully morphology-tagged with ketiv/qere preserved (added 18 July 2026). |
| `pli` | Pali | The complete Tipiṭaka in roman script (Mahāsaṅgīti), segment-aligned to English (added 18 July 2026). |
| `ett` | Etruscan | 6,248 inscriptions with English siblings and the ETP scholarly glossary — Tyrsenian, honestly isolate-adjacent (added 18 July 2026). |
| `osc` / `xum` / `spx` | Oscan / Umbrian / South Picene | The Sabellic axis: CEIPoM's lemmatized epigraphy (incl. the complete Iguvine Tables), ItAnt's critical editions, Mamertine Oscan in Greek script on Sicily (added 18 July 2026). |
| `xfa` / `xve` / `cms` | Faliscan / Venetic / Messapic | CEIPoM's dated, geolocated inscriptions — for Messapic and Venetic the largest machine-readable corpora in existence (added 18 July 2026). |
| `xlp` / `xcg` / `xrr` | Lepontic / Cisalpine Gaulish / Raetic | The Alpine corner: Lexicon Leponticum's inscriptions and 627-word lexicon, the Raetic corpus of record (added 18 July 2026). |
| `peo` | Old Persian | The Achaemenid royal trilinguals (ario): the cuneiform court language of Darius and Xerxes, lemmatized upstream (added 19 July 2026). |
| `elx` | Elamite | The Elamite versions of the Achaemenid trilinguals — tagged per word by upstream, honestly lemma-less (added 19 July 2026). |
| `syc` | Classical Syriac | The Digital Syriac Corpus (632 documents) and the ETCBC Peshitta OT — the Aramaic axis extended by a millennium; the Peshitta is the verse-alignment hub's seventh leg (added 19 July 2026). |
| `xeb` | Eblaite | The CDLI catalog's Ebla tablets — the third-millennium East Semitic sister of Akkadian (added 19 July 2026). |
| `scx` / `xly` / `xpu` | Sicel / Elymian / Sicilian Punic | The fragmentary languages of pre-Greek Sicily, in their only digital home (I.Sicily, added 18 July 2026). |
| `egy-Egyd` | Egyptian (Demotic script tag) | Two Demotic documentary papyri on the papyrus shelf (the bulk demotic corpus lives under `egy`). |
| `xct` / `xct-Latn` | Classical Tibetan | A stray GRETIL text (native and transliterated). |
| `xcl` | Classical Armenian | The fifth-century Armenian New Testament, gold-lemmatized. |
| `uga` | Ugaritic | The Copenhagen Ugaritic Corpus: 279 KTU tablets / 27,770 words in alphabetic cuneiform with per-sign damage flags (added 19 July 2026). |
| `ta-Latn` | Tamil (romanized) | One GRETIL stray. |
| `arc` | Aramaic | Biblical Aramaic (Daniel, Ezra) in the Masoretic shelf, the verse-aligned Targums (Onkelos, Jonathan, the Writings targums), and a cuneiform-shelf trace (grown 18 July 2026). |
| `en` | English (legacy tag) | One GRETIL stray using the two-letter tag; everything else standardizes on `eng`. |
| `und` | Undetermined | Five inscriptions whose language the upstream record could not determine — coded honestly rather than guessed. |

## Reference-shelf languages (dictionaries)

| Code | Dictionary | Notes |
|---|---|---|
| `grc` | Liddell-Scott-Jones | The Greek-English lexicon, 116,497 entries, citations resolved into the corpus. |
| `lat` | Lewis &amp; Short | The Latin dictionary, 51,636 entries, same resolution. |
| `san` | Monier-Williams | The Sanskrit-English dictionary (1899), 193,890 entries, transliteration-tolerant lookup, citations resolving into the Sanskrit shelf. |
| `ang` | Bosworth-Toller | The Anglo-Saxon dictionary, 62,815 entries, æ/þ/ð-folded lookup. |
| `chu` | Wiktionary-OCS | 4,615 crowd-sourced OCS entries whose etymologies seed the reconstruction crosswalk. |
| `sla-pro` | Proto-Slavic | 5,431 reconstructed headwords with descendant trees naming attested reflexes. |
| `ine-pro` | Proto-Indo-European | 1,905 roots — the trunk the `etym` command ascends to. |
| `gem-pro` | Proto-Germanic | 5,717 reconstructions bridging PIE to Gothic and Old English. |
| `ine-bsl-pro` | Proto-Balto-Slavic | 491 headwords — the structural intermediate shelf (PIE → PBS → Proto-Slavic). |
| `gmw-pro` | Proto-West Germanic | 5,551 headwords — the second intermediate shelf (Proto-Germanic → PWG → Old English). |
| `itc-pro` | Proto-Italic | 745 headwords bridging PIE to Latin. |
| `iir-pro` | Proto-Indo-Iranian | 799 headwords — Sanskrit via romanization, plus the flagged Iranian-loan layer in Armenian. |
| `ine` | IE-CoR | 4,981 expert-curated Indo-European cognate sets (synchronized 14 July 2026), with loan events flagged — an independent witness beside the Wiktionary-derived chains. |
| `ine-pro` | LIV-LOD | 305 Proto-Indo-European verbal etymons with stem types (synchronized 14 July 2026). |
| `ine-pro` / `itc-pro` | de Vaan, <em>Etymological Dictionary of Latin</em> | 2,860 etymons across two shelves (synchronized 14 July 2026) — the Latin → Proto-Italic → PIE chains of the Leiden school. |
| `ine-pro` | StarLing: Pokorny; Nikolayev PIE | Pokorny's complete <em>IEW</em> (2,222 roots) and Nikolayev's Walde-Pokorny-based database (3,291 etymologies with per-branch reflexes), synchronized 17 July 2026 under a written grant. |
| `rus` | StarLing: Vasmer | Vasmer's etymological dictionary of Russian, Trubachev edition — 18,239 entries (synchronized 17 July 2026). |
| `gem-pro` / `bat-pro` | StarLing: Common Germanic; Baltic | 1,994 and 1,651 etymologies with per-language reflex columns (synchronized 17 July 2026). |
| `sl` | Pleteršnik; Svetokriški; besedje16 | The Slovenian historical dictionary shelf, 139,405 entries (synchronized 17 July 2026) — toneme-accented headwords, Baroque attestation quotes, 16th-century print sigla. |
| `sga` / `mga` / `wlm` | Wiktionary Celtic extracts | Old Irish (6,564 entries), Middle Irish (767), and Middle Welsh (766) extracts joining the reconstruction crosswalk (synchronized 17 July 2026). |

<p class="aside">All seven reconstruction shelves are live, with multi-hop
chains through the intermediate shelves and per-edge loan flags; the
three etymological witnesses — IE-CoR, LIV-LOD, and de Vaan — are
synchronized and live as of 14 July 2026, and the five StarLing bases,
the Slovenian historical dictionaries, and the Celtic Wiktionary
extracts as of 17 July 2026.</p>

## Gold-lemma languages

Seventeen languages are searchable by dictionary form (`search --lemma`)
as of 17 July 2026:

`lat, grc, orv, akk, cop, sl, san, sux, chu, got, ang, xcl, xhu, uga,
hit, sga, bul`

The treebanks, ORACC, goo300k, Coptic Scriptorium, CorPH, and damaskini
feed these annotations — over 2.85 million rows (the exact count of
2,852,069 dates from the 14 July census; the Old Irish and Bulgarian
layers landed on 17 July). Everything else is full-text-searchable but
not yet lemma-searchable.
