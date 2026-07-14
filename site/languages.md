---
title: Languages
permalink: /languages/
description: >-
  The languages of the Nabu library: corpus languages, reference-shelf
  dictionaries, and the gold-lemma index, with the code conventions.
---

As of **14 July 2026** — a live inventory: every code below appears in the
catalog, the lemma index, or the reference shelf. The maintained original of
this page is
[docs/languages.md](https://github.com/arvicco/nabu/blob/main/docs/languages.md)
in the repository.

The library also carries this reference as a command: `nabu language CODE`
explains any code the tools surface — the corpus languages below and the
803 Wiktionary etymology codes that appear in `etym` cognate lists — on
one card: name, family, curated historical context, and live holdings. An
unknown code is reported honestly, with a family hint.

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
| `akk` | Akkadian | East Semitic language of Babylon and Assyria, held in transliteration with ORACC's gold lemmas (SAA letters, omens, royal inscriptions). |
| `eng` | English | The translation layer — Perseus and First1K editions, the WEB Bible, tablet translations; never an original. |
| `sux` | Sumerian | The language isolate of the earliest written literature, from Ur III royal inscriptions to the great lexical lists. |
| `cop` | Coptic | The last stage of Egyptian: documentary papyri plus the literary Coptic Scriptorium shelf (Sahidic and Bohairic, live since 13 July 2026), the fifteenth lemma-searchable language. |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine Bible, papyrus fragments, and 80,561 inscriptions — the largest language by documents. |
| `san-Latn` | Sanskrit (IAST) | The GRETIL shelf — Vedas to early-modern śāstra — in international transliteration with accents preserved. |
| `sl` | Slovenian (historical) | Early Modern print (Dalmatin 1584 to 1899) and, by lineage, the ~1000 CE Freising Manuscripts. |
| `qpc` | Proto-cuneiform | The pre-linguistic administrative tablets of the late fourth millennium BCE — signs before language. |
| `ang` | Old English | Beowulf and the complete ASPR poetry, plus the ISWOC prose and gospel treebank, ca. 700–1150. |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts. |
| `ar` | Arabic | A handful of early Islamic-era documentary papyri. |
| `hit` | Hittite | Anatolian entries in the multilingual cuneiform lexical lists. |
| `xhu` | Hurrian | Isolated lexical-list column entries from the cuneiform shelf. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
| `san` | Sanskrit (Vedic) | The Universal Dependencies Vedic treebank's gold-annotated sentences. |
| `pol` / `ita` / `ger` | Polish / Italian / German | Modern scholarly translations of the Freising Manuscripts. |
| `grc-Latn` | Greek (romanized) | Two papyri whose Greek survives only in Latin transliteration. |
| `egy-Egyd` | Egyptian (Demotic) | Two Demotic documentary papyri. |
| `xct` / `xct-Latn` | Classical Tibetan | A stray GRETIL text (native and transliterated). |
| `xcl` | Classical Armenian | The fifth-century Armenian New Testament, gold-lemmatized. |
| `uga` | Ugaritic | A lexical-list trace from the cuneiform shelf. |
| `ta-Latn` | Tamil (romanized) | One GRETIL stray. |
| `arc` | Aramaic | A single cuneiform-shelf document. |
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

<p class="aside">All seven reconstruction shelves are live, with multi-hop
chains through the intermediate shelves and per-edge loan flags. Three
further dictionary sources — the IE-CoR cognacy database, LIV-LOD, and de
Vaan's Latin etymological dictionary — are built and registered as of
14 July 2026 but not yet synchronized: they hold no live entries.</p>

## Gold-lemma languages

Fifteen languages are searchable by dictionary form (`search --lemma`) as
of 14 July 2026:

`lat, grc, orv, akk, cop, sl, san, sux, chu, got, ang, xcl, xhu, uga, hit`

The treebanks, ORACC, goo300k, and Coptic Scriptorium feed these
2,852,069 annotations; everything else is full-text-searchable but not yet
lemma-searchable.
