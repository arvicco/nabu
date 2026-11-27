# corpus-coranicum fixtures — the Cairo 1924 Qurʾān with the Talmon concordance

Retrieved 2026-11-27 from `https://github.com/telota/corpus-coranicum-tei`
(Berlin-Brandenburgische Akademie der Wissenschaften, TELOTA), commit
`57cb2b7be321ecfba100cb5f7988974f47864a14` ("Initial commit",
2024-12-20) — the repository's only commit; the Corpus Coranicum project
ran 2007–2024. The README's citation: "Corpus Coranicum Project, ed.
Michael Marx. TEI Data. Berlin-Brandenburg Academy of Sciences and
Humanities. https://github.com/telota/corpus-coranicum-tei."

License, the README verbatim:

    ## Licence
    © Berlin-Brandenburgische Akademie der Wissenschaften 2024
    Creative Commons CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/

The data files carry no licence of their own. → `attribution`
(share-alike).

## The files

Laid out as the adapter's fetch lays out `canonical/corpus-coranicum/`
(the repository tree; only `data/` is shown).

| path | what | why it is here |
|---|---|---|
| `data/cairo_quran/cairoquran.xml` | TRIM of the 17.5 MB file: suras 1, 111 and 112 | the accepted text grain; three facsimile surfaces (page 2, 825, 826) so 111:1–2 lands on 825 and 111:3 opens 826 inside the sura, 112 carrying 826 across the sura boundary; the transcription and the three translation divs cut to the same suras (present, never carried) |
| `data/quran_concordance/sura001.xml` | whole | the word layer of sura 1: 29 words, 31 analyses (2:3 rabbi and 5:4 nastaʿīnu carry a second) |
| `data/quran_concordance/sura111.xml` | whole | sura 111: 23 words, 31 analyses |
| `data/quran_concordance/sura112.xml` | whole | sura 112: 15 words, one analysis each |
| `data/quran_commentary/sura-00103.xml` | whole | the REJECTED commentary grain's specimen |
| `data/quran_intertexts/intertext-01010.xml` | whole | the REJECTED intertexts grain's specimen |
| `data/quran_manuscripts/manuscript-02504.xml` | whole | this source's REJECTED manuscripts specimen; for `corpus-coranicum-manuscripts` the REJECTED metadata-only record (Rotterdam 96D17, empty body) |
| `data/quran_manuscripts/manuscript-00017.xml` | whole (25 KB) | `corpus-coranicum-manuscripts`: Chicago A 6990 — kūfī B.Ia, 650–750, provenance al-Fusṭāṭ; supplied and unclear letters, a line-split word, line notes, two heading bands keyed verse 0 |
| `data/quran_manuscripts/manuscript-00504.xml` | whole (37 KB) | `corpus-coranicum-manuscripts`: BnF Arabe 7201 — ḥiǧāzī, "-750" (before 750), no provenance (the library is not the place); the 49:0 basmala band |
| `data/quran_manuscripts/manuscript-01362.xml` | whole (29 KB) | `corpus-coranicum-manuscripts`: Doha HC.MS.03151 — kūfī D.IV, 750–900; `<del>`, `<add>`, `<mod>`, words flagged unclear |
| `data/quran_manuscripts/places.xml` | TRIM | the repository authority: the whole header, and of its 110 `<item>` blocks only `repository_3` (BnF), `_5` (Chicago), `_84` (Qatar National Library, blank GeoNames key) and `_113` (Rotterdam) — whole lines, none edited; 380 of 1,339 lines |
| `data/quran_variants/sources.xml` | whole | this source's REJECTED variants specimen; for `corpus-coranicum-variants` the REJECTED source authority (cited by no reading) |
| `data/quran_variants/allvariants.xml` | TRIM | `corpus-coranicum-variants`: the header and `<list>` lines, every `<item>` block whose first word is in sura 111 or 112 (100 items), plus `variant_2330` (no reader), `variant_12427` (no reader, no words) and `variant_12428` (reader 444, no words) — whole lines, none edited; 1,362 of 222,719 lines, 103 items |
| `data/quran_variants/reader.xml` | TRIM | `corpus-coranicum-variants`: the header, and the `<person>` blocks of the 73 readers the trimmed items cite (reader 444 among them) — whole lines, none edited; 794 of 8,259 lines |

The concordance, specimen and whole manuscript files are byte-identical
copies of the files at the commit (raw URL:
`https://raw.githubusercontent.com/telota/corpus-coranicum-tei/57cb2b7be321ecfba100cb5f7988974f47864a14/<path>`).

This one tree backs THREE adapters, as the clone does on the box
(`canonical/corpus-coranicum/` is cloned once): `corpus-coranicum`
(`test/adapters/corpus_coranicum_test.rb`), `corpus-coranicum-manuscripts`
and `corpus-coranicum-variants` (their tests construct the adapter with
`clone_dir:` this directory). For `corpus-coranicum` every file under
`quran_manuscripts/` and `quran_variants/` is skipped by rule (5 + 3 in
this tree).

### The cairoquran.xml trim recipe

Whole lines only, none edited, in file order: everything up to and
including `<facsimile>`; of the 826 `<surface>` blocks (three lines
each) only `xml:id` `i2`, `i825`, `i826`; `</facsimile>` through each
body `<div>`'s opening line; inside every div (arabic_text,
transcription, translation en/de/fr) only the 8-space-indented sura
`<lg>` blocks of suras 001, 111 and 112 (`sura-NNN`,
`transcribed-sura-NNN`, `translated-xx-sura-NNN-xx`), each from its
opening line to its first `        </lg>`; every closing line. 493 of the
file's 265,701 lines (24,837 bytes; the whole file's sha256 is
`6f8265224514c02bf0d286022ba72aa095953b678c8cb36b49f47b5706a36b25`).

## Delivery grains (enumerated at fixture time, the whole repository)

`data/` holds 3,240 files in the six directories the README lists;
`schema/` (the ODD and RNG) and the README are documentation.

- **`cairo_quran/cairoquran.xml`** (1 file) — the Cairo 1924 text: a
  `<facsimile>` of 826 page images (`<surface n="826, Q 111:3- Q 113:3">`,
  links to the project's image server) and five body divs. **ACCEPTED:**
  the `arabic_text` div — `<lg xml:id="sura-NNN">` → `<lg
  xml:id="verse-NNN-VVV">` → one `<l>` → `<w xml:id="w-NNN-VVV-WWW">` —
  one document per sura (`urn:nabu:corpus-coranicum:sura-112`), one
  passage per verse (`…:112.1`). Inside the same file, **not taken**: the
  `transcription` div (a Latin transcription word by word, the
  concordance's `word_corpus_coranicum` again) and the `translation`
  divs `en`, `de`, `fr` (modern translations under their own rights).
- **`quran_concordance/suraNNN.xml`** (114 files) — one per sura, one
  `<w>` per ANALYSIS of a word, each 43 `<seg type="…">` fields: sura,
  verse, word_number (the join key — the files carry no ids), Talmon's
  ASCII transliteration and the project's DMG-style one (word, base,
  root), the analysis number, and the analyse_* fields (prefixes, part of
  speech, subcategory, semantics, pattern, aspect, voice, energicus,
  mood, gender, number, case, person, the dependent pronoun, definiteness,
  diptosis, the full analysis string) plus database timestamps.
  **ACCEPTED as the word layer** of the sura's document; never documents
  of their own.
- **`quran_commentary/`** (85 files, `sura-NNNNN.xml`) — the
  chronological, literary-critical commentary by sura. **REJECTED**
  (a later packet): skipped by rule.
- **`quran_intertexts/`** (714: 713 `intertext-NNNNN.xml` + `categories.xml`)
  — the intertexts database (late-antique and earlier texts). **REJECTED**:
  skipped by rule.
- **`quran_manuscripts/`** (2,323: 2,322 `manuscript-NNNNN.xml` +
  `places.xml`) — the manuscript descriptions. **REJECTED** for
  `corpus-coranicum`: skipped by rule. Taken by
  **`corpus-coranicum-manuscripts`**: the 193 records with a transcription
  (a `<w>` in the body) are its documents, one passage per verse; the 2,129
  metadata-only records are skipped by rule; `places.xml` is its repository
  authority. Images are links (`<graphic url>`), never fetched.
- **`quran_variants/`** (3: `allvariants.xml`, `reader.xml`,
  `sources.xml`) — the variant readings and their authority files.
  **REJECTED** for `corpus-coranicum`: skipped by rule. Taken by
  **`corpus-coranicum-variants`**: `allvariants.xml` (18,000 readings) →
  one document per reader, one passage per verse; `reader.xml` its
  authority; `sources.xml` skipped by rule (no reading cites a source).

## Census of the pinned clone (2026-11-27, every file read)

- Cairo arabic text: 114 suras, 6,236 verses, 77,432 words; every word id
  sits in its verse with contiguous ordinals; the 826 surface ranges
  cover every verse exactly once (the `<pb>` stream names the same 826
  ranges); every `<pb>` falls between verses.
- Concordance: 91,285 rows over exactly 77,432 distinct (sura, verse,
  word) keys — the join to the Cairo words is exact both ways, residue 0.
  11,938 words carry 2–16 analyses (10,527 two, 1,044 three …); three
  single analyses are numbered oddly upstream (2:255:50 empty, 16:93:2
  and 24:35:30 "2") and ride verbatim. Six rows have an empty
  `word_corpus_coranicum`; 816 an empty part of speech (the mysterious
  letters ʾalif-lām-mīm, some demonstratives, "MysteriousLetters" in the
  full analysis); a pronoun suffix's root field holds the suffix itself
  (-u, -hum, -nā; 7 rows).
- Roots: 1,702 distinct non-empty `root_corpus_coranicum` strings (1,718
  Talmon ASCII), 54,238 rows with a root.
- NFC changes 7 of the 77,432 Cairo words, each canonically equivalent:
  six write shadda before its vowel (U+0651 U+064E / U+064B — 2:143:16,
  9:83:17, 11:80:3, 17:12:15, 33:61:1, 36:36:6), NFC reorders them
  vowel-first; one writes alef + combining maddah (U+0627 U+0653, 6:42:8),
  NFC composes it to U+0622.
- Expected first sync: 114 documents / 6,236 passages / 77,432 tokens,
  3,125 files skipped by rule (85 + 714 + 2,323 + 3), 0 unrecognized.

### The manuscripts (`corpus-coranicum-manuscripts`, census 2026-11-27)

- 2,322 records: 193 with a transcription (462,012 `<w>` elements), 2,129
  without (2,111 empty bodies, 18 "(No content available)").
- Parsed: 193 documents, 32,182 passages (31,730 verses + 452 sura heading
  bands keyed verse 0), 411,803 words (17,668 joined from line-split
  fragments), 32,533 verse-division markers (`000-000-000`), 4 unkeyed and
  3 empty `<w>`; 962 verses resume after an interruption (merged in file
  order).
- Letters: 115,725 supplied (from the Cairo rasm: `omitted-in-original`
  and `illigible`), 23,384 unclear, 8,148 added, 15,058 modified; 887
  words carry a `<del>`.
- Axes: 172 dated (origDate CE years; `-750` = before 750), 98 with a
  provenance, script style on 186, material parchment 177 · paper 9 ·
  papyrus 7.
- NFC changes none of the 411,803 words; the archaic dotless letters
  (U+066E 145,265, U+066F 26,255, U+06A1 33,200, U+06BA 62,649, U+06D2
  20,708 occurrences) and the U+FEE9 presentation form are untouched.
- Cairo join: 31,676 verse passages cite a Cairo verse, 54 do not;
  393,965 words carry a Cairo word key, 13,876 a key beyond the Cairo
  verse's words; 76,999 of the 77,432 Cairo words are witnessed.

### The variants (`corpus-coranicum-variants`, census 2026-11-27)

- 18,000 items (ids 28–18306), 30,112 reader ascriptions, 753 distinct
  readers of the authority's 870 (all present in `reader.xml`), 34,172
  words over 12,943 distinct keys in 3,495 verses of all 114 suras; the
  Arabic field and the source key are empty on every item.
- Join to the Cairo words: 12,937 keys name a Cairo word, 5 a verse the
  Cairo text lacks, 1 (111:3:6) a word past the verse's end.
- Parsed: 753 documents (752 readers + the unattributed readings — 13
  items naming no reader and `variant_1841`, ascribed only to upstream's
  `test` record, reader 328), 22,658 passages; 2 empty items dropped; 194
  readers dated by their death, 68 placed by their residence.
