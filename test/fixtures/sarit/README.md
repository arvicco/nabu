# SARIT fixtures (P26-2)

Real upstream samples from the SARIT corpus repo,
<https://github.com/sarit/SARIT-corpus>, retrieved **2026-07-18** at HEAD
`1eac9ee0b055c8d11147edac4a75c76008ccc363` (last upstream merge 2024-05-25;
content dormant since 2021). The live site sarit.indology.info was serving
502s at scouting time — the repo is the source of record.

Four files spanning the corpus's dominant addressability shapes (whole-corpus
census 2026-07-18: 83 editions / ~170 MB, 41 Devanagari-surface / 42 IAST):

| file | script | shape exercised |
|---|---|---|
| `astavakragita.xml` (**whole**, 67 KB) | IAST | `lg/@xml:id` verses (`verse_1.1`); the l-carried-id quirk (the FIRST lg holds its id on its first `<l>`, not itself); upstream encodes verse 1.13 *before* 1.12 (document order kept); prose speaker lines → div-scoped ordinals |
| `samanyadusana.xml` (**whole**, 33 KB) | Devanagari | NO addressing anywhere → pure ordinals (`v1`…`v5`, `p1`…`p29`); `<lb break="no"/>` word joins; variant-apparatus `<note>` subtrees (each wrapping its own `<p>`) dropped |
| `vatsyayana-nyayabhasya-s1-2.xml` (**trim**) | IAST | nested `div/@xml:id` path ladder (`nyāyabhāṣya__1.1.1` → `1.1.1`); base-text `<quote n="NyāSū__1.1.2">` sūtra blocks (citation inherited by the wrapped `<p>`); inline `<quote>` kept as reading text |
| `mahabharata-devanagari-adi1-svarga1.xml` (**trim**, 147 KB — the trimmed-but-big streaming fixture) | Devanagari | parva/adhyāya div path (`@n`, with the svargārohaṇa adhyāyas carrying only `@xml:id` → stripped to `001`); self-contained hyphenated lg ids (`adi-1-1-1`); `<seg n="a..d">` pada segments; prose invocations |

## Trims

- `vatsyayana-nyayabhasya-s1-2.xml`: upstream `vatsyayana-nyayabhasya.xml`
  (566 KB) lines 1–231 (teiHeader + div 1 > 1.1 > sūtras 1.1.1–1.1.2 complete)
  plus closing tags. Re-apply after any refresh.
- `mahabharata-devanagari-adi1-svarga1.xml`: upstream
  `mahabharata-devanagari.xml` (38.6 MB — the file the >5 MB streaming rule
  exists for) lines 1–1831 (teiHeader + ādiparva div + complete adhyāya 001)
  + `</div>`, then lines 487077–487220 (svargārohaṇaparva div + complete
  adhyāya 001) + closing tags. Preserves the two-parva nesting, both div
  addressing styles, lg/seg verse structure and prose. Re-apply after any
  refresh.

Both trims carry suffixed filenames so their urns are FIXTURE urns
(`urn:nabu:sarit:mahabharata-devanagari-adi1-svarga1`), never colliding with
the real corpus urns minted at the owner-fired first sync (the GRETIL
Ṛgveda-trim precedent).

## License (verbatim, per-file)

Every SARIT header carries its own grant in `<availability>`; the corpus
wrapper `saritcorpus.xml` declares the CC BY-SA 3.0 default that governs
"unless specified otherwise in the respective headers". Census over all 83
editions at the retrieval HEAD: **CC BY-SA 4.0 ×56, CC BY-SA 3.0 ×26
(one of them as bare prose with no ref target — ratnakirti-nibandhavali),
MIT ×1 (bhattojidiksita-siddhantakaumudi) — zero NC**. These fixtures:

- `astavakragita.xml`: "Distributed by SARIT under a Creative Commons
  Attribution-ShareAlike 3.0 Unported License." (Copyright Suryansu Ray 2012;
  ref target `http://creativecommons.org/licenses/by-sa/3.0/`)
- `samanyadusana.xml`: `<licence>` "Distributed under a Creative Commons
  Attribution-ShareAlike 4.0 International licence." (Copyright 2016-2018
  SARIT; ref target `https://creativecommons.org/licenses/by-sa/4.0/`)
- `vatsyayana-nyayabhasya-s1-2.xml`: CC BY-SA 3.0 (same wording family as
  astavakragita), header preserved byte-verbatim in the trim.
- `mahabharata-devanagari-adi1-svarga1.xml`: CC BY-SA 3.0, header preserved
  byte-verbatim in the trim.

## Upstream structure notes

- The Mahābhārata is the **Southern Recension** (its own editionStmt: "This
  e-text is based on the `Southern Recension' of the Mahābhārata, edited by
  Krishnacharya 1906–1914" — the Kumbakonam edition, T.R. Krishnacharya &
  T.R. Vyasacharya, Nirnayasagar 1906–1910, 17 volumes). NOT the BORI
  critical edition and NOT the Calcutta vulgate Monier-Williams's "MB."
  citations reference — no MW citation joins are promised on this text.
- Five corpus files were quarantined under the v1 rungs: four Braj/Awadhi
  texts whose content rides in `<ab>` blocks (diksita-jivanacaritra,
  hajarilala-srisivavivahakavitavali, nivajakavi-sakuntala-upakhyana,
  trisuli-piyusalahari) and the list-shaped ayurvedasutram
  (`<label>1.1</label><item>sūtra</item>`). The 2026-11-13 quarantine
  review's grains recover them (see "Citation-unit fixtures" below).
- Six corpus files declare no language anywhere (`<text>`/`<body>` both
  bare); discovery sniffs the script of the first body text (san default).
  Not exercised by these fixtures' headers but covered by a doctored-copy
  test.

## Citation-unit fixtures (the 2026-11-13 quarantine review)

Trimmed REAL slices from the local canonical clone
(`sarit/SARIT-corpus@master`), cut **2026-11-13**; headers byte-verbatim.

- **`trisuli-piyusalahari-p4p5p16.xml`** — the lb-in-ab print
  transcription: the whole text in ONE attribute-less `<ab>` segmented only
  by `<lb/>` print lines and `<pb n="…"/>` pages (no lg/l/p; heads and
  trailers outside the `<ab>`). TRIM: upstream lines 1..144 (teiHeader,
  front, body through page 05) + 415..444 (page 16 to the end: the `<ab>`
  close, both trailers, closing tags) → passages `pb04 pb05 pb16`, the PAGE
  grain (addressing `page`). Grant: CC BY-SA 4.0 (`<licence>` target in the
  header). The same shape carries the other three quarantined Braj/Awadhi
  texts AND four loaded siblings (bandimocana,
  giridharadasa-bharatibhusana, pyarelala-ragabinoda,
  tulasidasa-ramayanasatika) that held one passage each — their epigraph
  `<p>` — while the `<ab>` text was dropped; those gain their pages (15, 31,
  39, 48 passages) and their existing `p1` stays put.
