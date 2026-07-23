# OpenITI fixtures (premodern Arabic + Persian, OpenITI mARkdown)

Real samples from the **Open Islamicate Texts Initiative** (OpenITI) corpus —
premodern & early-modern Islamicate texts in **OpenITI mARkdown**, a bespoke
structured-plaintext markup. Six small text files (one kept whole, five body
trims) plus a trimmed copy of the central metadata index.

- **Retrieved:** 2026-07-22.
- **Release:** **2025.1.9** (the 9th overall release), published **2025-12-30**.
- **Zenodo record:** `10.5281/zenodo.17767721` (this version);
  concept DOI `10.5281/zenodo.3082463` always resolves to the latest release.
  - `OpenITI_data_2025-1-9.zip` — **5,936,029,637 B (5.9 GB)**,
    md5 `95cf19a9320fee6c37c4c26c9fa860b1`.
  - `OpenITI_metadata_2025-1-9.tsv` — **12,092,756 B**,
    md5 `cb2226f64264efa964df9ef659d40199` (14,108 lines incl. header).
- **Text files** were fetched individually from the **`OpenITI/RELEASE`** GitHub
  repo (`https://github.com/OpenITI/RELEASE`, default branch `master`), which
  aggregates the same data as the Zenodo zip. `master` is a **moving ref**; the
  files here correspond to the 2025.1.9 state.

## On-disk layout (RELEASE repo)

Flat **per-author** tree — NOT a 25-year-bucket scheme in this repo:

```
data/<AuthorURI>/<AuthorURI.BookURI>/<versionUri[.status-ext]>
data/<AuthorURI>/<AuthorURI.BookURI>/<versionUri[.status-ext]>.yml   # sidecar
data/<AuthorURI>/<AuthorURI.BookURI>/<AuthorURI.BookURI>.yml         # book sidecar
data/<AuthorURI>/<AuthorURI>.yml                                     # author sidecar
```

The version file has **no extension** when plain/completed, or a **status
extension**: `.mARkdown`, `.completed`, `.inProgress`. The 25-year AH buckets
that older docs describe are the *upstream annotation repos* (`OpenITI/0025AH`,
`OpenITI/0050AH`, …, referenced from the `.yml` sidecars' pre-clean links); the
RELEASE repo flattens them.

## URI scheme

`AuthorDeathAH<ShuhraLatin>.<WorkTitle>.<EditionId>-<lang><n>`, e.g.
`0792Hafiz.Muntasab.PDL00074-per1`:

- `0792` = author's **hijrī death year**, zero-padded to 4 digits (the
  `date` column of the metadata TSV always equals this prefix — 0 mismatches
  across 14,107 rows). Range observed: **AH 1 … AH 1450**.
- `Hafiz` = Latinized *šuhra* (best-known name).
- `Muntasab` = work title; `PDL00074` = edition/source id (source-collection
  prefix + number: JK, Shamela, ShamAY, Hindawi, Shia, PDL, AOCP, IEDC, …).
- `-per1` / `-ara1` = language + edition ordinal. Multi-language manuscript
  documents concatenate codes, e.g. `-ara1ugo1`, `-per1jup1`, `-mpp1`
  (ugo Uyghur, ota Ottoman, jup Judeo-Persian, mpp Middle-Persian/Pahlavi,
  bac Bactrian — all in the small `MSS` sub-corpus).

## The six texts

| File | genre / language | why it's here |
|---|---|---|
| `0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1` | **hadith**, ara | kept **whole** (3,872 B); Shamela-legacy #META# vocabulary; **real leading U+FEFF BOM** |
| `0001AbuTalibCabdManaf.Diwan.JK007501-ara1` | **poetry**, ara | LEGACY verse notation `# % hemi % hemi % no`; inline meter (البحر) |
| `0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1.mARkdown` | **history/biog**, ara | `.mARkdown` ext; `### |` / `### ||` header levels; msNN |
| `0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1` | **falsafa/logic**, ara | prose `#`/`~~`; inline `msNN` + folio notes `(73 وجه)` |
| `0792Hafiz.Muntasab.PDL00074-per1` | **poetry**, per | `%~%` hemistich notation; Persian orthography |
| `0428IbnSina.RisalaJudiya.AOCP202502141162-per1` | **prose/falsafa**, per | OCR (eScriptorium) #META#; inline image tags `![](.jpg)` |

Plus `OpenITI_metadata_2025-1-9.sample.tsv` — a stratified trim of the index
(header + the six books + ~290 assorted rows; pri/sec + ara/per/MSS mix).

### Trim procedure

mARkdown is plaintext with **no closing tags**, so every trim is a clean
**line-boundary truncation**: the header (magic value `######OpenITI#` through
the `#META#Header#End#` splitter) is kept intact, the body cut after a chosen
line; nothing is appended. The hadith is small enough to keep byte-for-byte
(`whole: true`). See `manifest.yml` for each file's cut line and full size.
Because a raw GET returns the FULL upstream file, the trims are marked
`whole: false` (fetched for URL-liveness, never byte-compared).

## mARkdown format census (observed in these files)

- **Magic value:** `######OpenITI#` (line 1; the hadith is preceded by a U+FEFF).
- **Metadata block:** `#META# key: value` lines, terminated by `#META#Header#End#`.
  The vocabulary is **source-dependent** — four distinct schemes appear:
  1. **KITAB numbered** (Diwan, Ziyadat, Jumal): `000.BookURI`, `010.AuthorNAME`,
     `011.AuthorDIED`, `019.AuthorDIED`, `020.BookTITLE`, `021.BookSUBJ`,
     `025.BookLANG`, `040.EdEDITOR`, `045.EdYEAR`, … `999.MiscINFO`.
  2. **Shamela legacy** (Hadith): Arabic keys (الكتاب, المتوفى, المصدر) +
     `iso`, `bkid`, `cat`, `bkord`, `DownloadSource`, `ConversionDate`, …
  3. **PDL/Ganjoor minimal** (Hafiz): `title`, `ed_info`, `url`.
  4. **eScriptorium/Kraken OCR** (Ibn Sīnā): `Creator`, `Created`, `LastChange`,
     `transcription layer name`, `avg transcription confidence`.
  The **machine-readable** metadata is the `.yml` sidecar (keys like
  `00#VERS#URI######`, `90#VERS#ISSUES###: … PRIMARY_VERSION …`) and the central
  TSV — NOT the `#META#` block.
- **Structural section headers:** `### |` (level 1) … `### |||||` (level 5);
  levels 1–2 observed here. May carry annotations (`### | AUTO …`).
- **Paragraph / line:** `#` begins a paragraph/unit; `~~` continues a wrapped
  line (both at line start; the OCR file also shows `# ~~`).
- **Page markers:** `PageVNNPNNN` (V=volume, P=page). Padding varies by source:
  `PageV01P001` (3-digit, Arabic) vs `PageV01P01` (2-digit, PDL Persian).
  Appear **inline** mid-line or standalone.
- **Milestones:** `msNN` word/segment markers; padding varies (`ms1` vs `ms01`).
- **Poetry / hemistich — TWO notations observed:**
  - `%~%` between hemistichs (`# 1 hemi1 %~% hemi2`) — Persian PDL (Hafiz).
  - legacy `# % hemi1 % hemi2 % <verse-no>` with `%` delimiters — Arabic JK
    (Diwan); `% %` marks an empty field.
- **Image reference:** `# ![image filename](./<page>.jpg)` — OCR page images.
- **Inline editorial notes** (not tags): meter `البحر : طويل`, folio `(73 ظ)`.

### Documented by the spec but NOT seen in this sample (loud-census surface)

The [mARkdown spec](https://maximromanov.github.io/mARkdown/) defines more that
the parser packet should expect but which does **not** appear in these files:
biographical/dictionary units (`### $`, `### $$`, `### $DIC_*$`, `### $BIO_*$`),
events (`### @`, `### $CHR_*$`), doxography (`### $DOX_*$`), `### |EDITOR|`,
`Milestone300` (300-word auto markers), riwāyāt/isnād (`# $RWY$`, `@MATN@`,
`@HUKM@`), automatic/manual **named-entity** tags (`@PERXX`/`@PXX`, `@TOPXX`,
`@YB####`/`@YD####`, `@SRCXX`, `@SOCXX`), open user tags
(`@USER@CAT_SUB@`), geo triples (`#$#PROV…#$#`), morphological `#~:cat:`, and
lacunae `......`. None were present in the six sampled texts — NER/analytic tags
are confined to specifically annotated sub-collections.

## Encoding / NFC (real evidence for the folding packet)

All six files are **UTF-8 NFC-stable** (`text == NFC(text)`, byte-identical) —
Arabic/Persian here needs no combining-mark reordering (unlike hbo/arc).

- **BOM:** the Hadith file has a leading **U+FEFF** (kept, byte-for-byte).
- **Tatweel** (U+0640): light use (1–2 per Arabic prose file); none in poetry.
- **No presentation-form** characters (U+FB50–FDFF / U+FE70–FEFF) — standard
  Arabic block throughout.
- **Persian vs Arabic orthographic split is clean:**
  - Arabic files use **ي U+064A** (arabic yeh) and **ك U+0643** (arabic kaf),
    zero Persian forms.
  - The Persian Ḥāfiẓ file uses **ی U+06CC** (farsi yeh, ×630) and
    **ک U+06A9** (keheh, ×236), plus **پ چ ژ گ** — **zero** U+064A/U+0643.
  A cross-language search/fold must therefore normalize yeh (U+06CC↔U+064A) and
  kaf (U+06A9↔U+0643).
- **OCR/edition artifacts** (Ibn Sīnā): footnote digits fused to words
  (`بجودیه1`), marginalia in guillemets `« … »` — canonical, not to be cleaned.

## Metadata index (D41-e sizing basis)

`OpenITI_metadata_2025-1-9.tsv` columns: `version_uri, language, subcorpus,
uncorrected_OCR, date, author_ar, author_lat, book, title_ar, title_lat,
ed_info, id, status, tok_length, char_length, local_path, tags, …`. The
priority flag is **`status` = `pri` (primary) / `sec` (secondary)**; the file
mirrors it as `PRIMARY_VERSION` in the `.yml` sidecar `ISSUES` field.
`tok_length` is the word count. Whole-index figures (all 14,107 versions):

| metric | all versions | primary only |
|---|---|---|
| text versions | 14,107 | 9,539 |
| words (Σ tok_length) | 2,348,893,857 | 1,117,218,563 |
| Arabic (`ara`) | 13,368 · 2.31 B w | 8,803 · 1.079 B w |
| Persian (`per*`) | 691 · 38.8 M w | 688 · 38.7 M w |
| other (bac/mpp/jup/mixed) | 48 · 13 k w | — |

Distinct works 9,109; distinct authors 3,558. `uncorrected_OCR: True` for 760
versions. Sub-corpora: `ara` 13,320, `MSS` 433 (documents; empty book/date),
`per` 354. Anomalies: 3 works with >1 primary; 433 MSS rows lack a book URI &
death date; multi-language MSS URIs; no zero-length / placeholder rows.

## License (recorded exactly)

Zenodo record metadata license field: **`cc-by-nc-sa-4.0`** — rendered as
*"Creative Commons Attribution Non Commercial Share Alike 4.0 International"*.
license_class: **attribution-noncommercial-sharealike** (the NC clause matters).

**Discrepancy, flagged:** there is **no `LICENSE` file** in the RELEASE repo
(404), the `README.md` states **no license**, and the mARkdown text files carry
**no in-file license statement**. The only license assertion is the Zenodo
record's `license` field. Cite: Romanov, Maxim, and Masoumeh Seydi.
*OpenITI: A Machine-Readable Corpus of Islamicate Texts*, Zenodo, 2019–
(version 2025.1.9). Co-PIs: Miller, Romanov, Savant.
