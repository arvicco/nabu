# eBL Fragmentarium fixture (P31-3)

Trimmed real slice of the eBL Fragmentarium bootstrap snapshot — Zenodo
record 10018951, "Transliterated Fragments of the Electronic Babylonian
Literature Project (eBL)", DOI 10.5281/zenodo.10018951, published
2023-10-18 (Yunus Cobanoglu; companion code repo
ElectronicBabylonianLiterature/transliterated-fragments @ 9b77f70b).

- Retrieved: 2026-07-19
- Source file: `fragments.json` from
  <https://zenodo.org/records/10018951/files/fragments.json>
  (73,854,507 B; Zenodo md5 `71538e2d86c8ba6d47f499892bb3e5d3` verified
  byte-for-byte on download; full-file sha256
  `4e970d8713315ca9559fb9dfd79956d5b19b1debb9941c22f8bed0339745d753`,
  pinned in `Nabu::Adapters::Ebl::SNAPSHOT_SHA256`)
- Upstream shape: ONE single-line JSON array of 23,289 fragment objects,
  each with a non-empty eBL-ATF `atf` field.

## Trim recipe

`fragments.json` here is a JSON array of **14 member objects copied
byte-verbatim** from the upstream array (spans located with a streaming
`raw_decode` walk; members joined with `", "` inside `[` `]`, preserving
upstream relative order). No member was edited; the K.5808 twin appears
twice because upstream carries the byte-identical duplicate at array
indexes 999/1000.

| _id | upstream index | why |
|---|---|---|
| K.11360 | 0 | smallest cdliNumber carrier; `@column N'` without a surface |
| K.12174 | 43 | `// F K.2198+ …` parallel riders on text lines |
| K.13942 | 145 | `%sux` shifts, `A+N'` sigla labels, `// (Instructions of Šuruppak N)` parallels, `#note` rider |
| K.2954 | 795 | `// (UḪ V 52)` BEFORE any text line (document-level parallel); interlinear `($___$)` bilingual |
| K.5808 | 999 + 1000 | the byte-identical duplicate `_id` — first-wins skip-by-rule |
| IM.75911 | 1693 | translation extents `#tr.en.(r i 4'):` AND the dotless `#tr.en(r i 8'):` spelling |
| BM.47447 | 1966 | the ONLY `#lem`-bearing fragment corpus-wide (71 lines); `$ obverse` state-line, blank lines |
| IM.61678 | 4128 | structured king/year `date` field; `#tr.en.(o 4):` extent; `@date` discourse division; Ur III `%sux` |
| K.21002 | 6657 | zero text lines (states only) → metadata-only document |
| 1868,0523.2 | 8509 | the deposit README's own exemplar: `#tr.en` + `@i{…}` markup, `#note`, `$ single ruling`, comma museum number |
| U.7321 ? | 16087 | the one whitespace-bearing `_id` corpus-wide; `$ obverse` |
| K.20565 | 20876 | `editedInOraccProject: saao` + cdliNumber → double edge |
| N.7458 | 22414 | uniform `%es` (Emesal) fragment; `period: "None"` sentinel |

## License (recorded verbatim at fixture time — the claims conflict)

JOHD data paper 10.5334/johd.148 ("Transliterated Cuneiform Tablets of
the Electronic Babylonian Library Project", 2024), License section:

> eBL fragments Python code: MIT License
>
> Data (fragments.json): Attribution-NonCommercial-ShareAlike 4.0
> International (CC BY-NC-SA 4.0).
>
> Photographs: Reproduction of the images requires explicit consent from
> both the funding projects, the relevant institutions, as well as the
> institutions in which the cuneiform tablets are kept.

Zenodo record 10018951 license field: `cc-by-4.0`.

nabu holds the source at `license_class: nc` (the conservative reading)
until owner email №24 resolves the conflict. Photographs are entirely
out of scope. The Corpus side of eBL (Gilgameš chapter editions) is NOT
in this deposit and NOT covered by these grants — out of scope.
