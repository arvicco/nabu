# CEIPoM fixture — Corpus of the Epigraphy of the Italian Peninsula (P29-1)

Trimmed, real samples of CEIPoM v1.3 (Reuben Pitts, KU Leuven): the
"Corpus of the Epigraphy of the Italian Peninsula in the 1st Millennium
BCE" — Zenodo record 6475427 (version DOI 10.5281/zenodo.6475427,
concept DOI 10.5281/zenodo.4759134), published 2022-04-21.

- **Retrieved:** 2026-07-18, from
  `https://zenodo.org/api/records/6475427/files/<name>.csv/content`
  (the API download links of record 6475427; the human-facing download
  URLs `https://zenodo.org/records/6475427/files/<name>.csv?download=1`
  serve the same bytes and are what the adapter fetches).
- **Upstream sha256 (whole files, at retrieval):**
  - `texts.csv` — `a6853697f826d8980873d6547c530f6d44c6519c2d5c70f17de2e8c08c033f3e` (1,225,788 B)
  - `sentences.csv` — `76c4da404b28e470569ce33234aae6132495c916fc58f5f3e061c42b6dc93c65` (809,796 B)
  - `tokens.csv` — `7147fc26153e1f0e8bed2cf221807aec01fc07e08f9b8520a9ff2c5267a6b5ef` (3,164,822 B)
  - `analysis.csv` — `9254136cdbe73a43a6cfba7e82e6bc6f51b587d2aa18582f15b21881bb4d10a7` (11,505,480 B)
  - `links.csv` — `e0a439a3915a51c15bccb2303d959c61d221cb05785b3ab5e6bac93484114f1b` (92,846 B)
- **Layout:** the fixture mirrors the workdir the adapter fetches —
  FileFetch is one-file-per-dir, so each CSV lives in its own subdir:
  `texts/texts.csv`, `sentences/sentences.csv`, `tokens/tokens.csv`,
  `analysis/analysis.csv`, `links/links.csv`.

## Encoding — the UTF-16 pin (a first for flat CSV)

Every upstream CSV is **UTF-16LE with a BOM** (`FF FE`), CRLF line
endings, comma-separated with double-quoted fields where needed. The
trims here are **byte-verbatim row slices**: the BOM + header line +
selected data rows, each row's UTF-16LE bytes exactly as upstream
serves them (verified byte-subsequence of the originals at trim time).
The adapter decodes at the boundary (`BOM|UTF-16LE` → UTF-8 → NFC);
the encoding test pins the BOM bytes verbatim.

## Upstream census (whole corpus, at retrieval 2026-07-18)

- `texts.csv`: **3,875 texts**. Language × variety:
  Latin/Latin 1,378 · Latin/Faliscan 420 · Latin/"Faliscan / Latin" 35
  · Latin/Paelignian 1 · Oscan/Oscan 823 · Oscan/Paelignian 63 ·
  Oscan/Marrucinian 16 · Messapic 591 · Venetic 411 · Umbrian/Umbrian
  61 · Umbrian/Volscian 7 · Old Sabellic/Old Samnite 34 ·
  Old Sabellic/South Picene 25 · Greek 10.
- Script column: Latin 2,094 · Oscan 661 · Messapic 591 · Venetic 221
  · Greek 132 · Umbrian 42 · Etruscan 27 · South Picene 25 · Nocera 3
  · empty 10 · 9 mixed "/" variants ×69 (incl. the spacing-less
  `Umbrian/Latin` on the Iguvine Tables).
- Dates: signed years as FLOAT strings (`-675.0`); **3,872/3,875
  dated** (3 undated), always both bounds; **one degenerate inverted
  range** (text 819, `-100.0` → `-51300.0` — an upstream typo).
  **3,815/3,875 carry WGS84 lat/long** (60 unplaced). `Provenance` is
  always non-empty but 10 values are degenerate (`?` ×4, `0` ×3,
  "Provenance unknown [found & written]" ×3). `GeoID` (1,036 texts) is
  a bare float-formatted number (`11847.0`), id space undocumented —
  carried verbatim, never resolved.
- `sentences.csv`: **5,303 sentences**, globally unique `Sentence_ID`,
  `Sentence_position` 1-based per text. **4 texts have no sentence row
  at all** (793, 2911, 3102, 3184) — nothing citable, skipped by rule.
  519 sentences are non-NFC (combining marks, e.g. the Lapis
  Satricanus dot-below) — the boundary `Normalize.nfc` composes them.
- `tokens.csv`: 37,041 tokens (`Relation` SBJ/OBJ/PRED… + `Head`
  pointers as float strings). `analysis.csv`: 36,874 analyses —
  **`Lemma` is an opaque lemma ID (`12444a`), NOT a citation form**
  (33,442 rows carry one; the rest are `-`); `-` is the corpus-wide
  null. 12 tokens carry >1 analysis (max 3).
  `Classical_Latin_equivalent`: 32,415 rows / 3,952 distinct values.
- `links.csv`: 3,630 Trismegistos ids over 3,627 texts (3 texts carry
  two ids, e.g. text 719).

## Texts in this trim (17; every fixture row is a real upstream row)

| Text | What it pins |
|---|---|
| 2 | **Fibula Praenestina** (CIL XIV 4123; sentence 2 "Manios med fhefhaked Numasioi"), TM 256173 |
| 5 | **Duenos inscription** (CIL I² 4; sentences 5–7), TM 568865 |
| 9 | Lapis Satricanus (EDCS 24700256) — non-NFC combining dot-below |
| 719 | 7 sentences; TWO Trismegistos ids (496141, 832355) |
| 793 | sentence-less text — the skip-by-rule pin |
| 819 | the inverted date range (-100 → -51300) — axis invalid pin |
| 871 | South Picene (Old Sabellic → `spx`), South Picene script |
| 896 | Old Samnite (Old Sabellic → `spx`), Etruscan script |
| 954 | Oscan, Oscan script (Capua 7) |
| 995 | **Iguvine Tables** (`xum`, script `Umbrian/Latin` → mixed) — trimmed to sentences 1070 (Table 1a), 1129 (Table 1b; holds the trim's one multi-analysis token), 1405 (Table 6a, Latin alphabet) |
| 1795 | Messapic (`cms`) |
| 2390 | Venetic (`xve`) |
| 2584 | undated + unplaced + degenerate Provenance `0` — the full-residue pin |
| 2747 | Faliscan (`xfa`), script "Etruscan / Latin" → mixed facet |
| 2756 | Faliscan (`xfa`), Latin script |
| 3106 | variety "Faliscan / Latin" — stays `lat` (mapping pin) |
| 15171 | Greek (`grc`), real Greek codepoints ("νωλαιων / νωλα / νωλαιος") |

## License (verbatim)

Zenodo record 6475427 license field: **`cc-by-sa-4.0`** ("Creative
Commons Attribution Share Alike 4.0 International") →
`license_class: attribution` (the SA share-alike rider is recorded in
`docs/02-sources.md`; derivatives must carry the same license). Cite:
Reuben Pitts, *Corpus of the Epigraphy of the Italian Peninsula in the
1st Millennium BCE*, v1.3, Zenodo (2022), doi:10.5281/zenodo.6475427.
