# tianyige fixture

Retrieved 2026-11-02 from Zenodo record 23817595 (v1.0, 2026-10-30;
concept record 23817594), file `tianyige-ming-exam-records-v1.0.zip`
(96,836,611 bytes, md5 9276b9512f06fe7ed1f4bffa0b3dc2e8 = the record's
checksum; central-directory sha256 de1bb49f…41e4, the adapter's pin), via
https://zenodo.org/api/records/23817595/files/tianyige-ming-exam-records-v1.0.zip/content

The tree is the zip as ZipRangeFetch lands it (the single top directory
`tianyige-ming-exam-records-v1.0/` stripped). This README replaces the
deposit's own README.md (same path; in the fetch cone, license evidence).

## Delivery grains (every grain the deposit serves; 955 members)

| grain | file(s) | taken? |
|---|---|---|
| record × page | `pages/<tianyige_id>.jsonl` (312 records, 40,461 page lines) | TAKEN — document = record, passage = page (`text`); 1,750 `blank` pages skip by rule, counted per document |
| record table | `volumes.tsv` (312 rows) | read as document metadata |
| page fields `punctuated`, `translation_en`, `translation_model` | inside every page line | DECLINED — machine punctuation + machine English translation (the Honkoku precedent); present in the fixture lines, never surfaced |
| page field `alt_text` | inside 12,664 page lines | DECLINED — the second model's reading; only `alt_ocr_model` + `agreement` ride |
| logical documents | `documents/<tianyige_id>.jsonl` (81,298, model-segmented re-cut of the same text) | rejected — outside the Range cone; first 2 lines of 0006944 pinned |
| plain text | `text/<year>_<title>_<id>.txt` | rejected — a rendering of `pages/`; first 12 lines of the 0006944 file pinned |
| tables | `tables/*.jsonl`, `questions.tsv`, `graduates.tsv`, `volumes.json` | rejected (the questions/graduates persons layer is a later lane); header + 2 rows of each TSV and 2 lines of `tables/questions.jsonl` pinned |
| viewer | `index.html`, `assets/` | rejected; `index.html` pinned whole |
| citation | `CITATION.cff` | fetched; pinned whole |

## The cuts (page lines byte-identical)

- `pages/0006944.jsonl` — 洪武四年會試錄 (metropolitan, 1371), pages 1–4,
  all dual-read (gemini primary, Claude `alt_ocr_model`, agreement).
- `pages/0000538.jsonl` — 康熙二十三年四川鄉試錄 (provincial, Sichuan, 1684,
  the one Qing record), pages 12–15: two non-blank around two `blank`.
- `pages/0007858.jsonl` — 隆慶四年廣東武舉鄉試錄 (military provincial,
  Guangdong, 1570), pages 1 (blank) and 2.
- `volumes.tsv` — header + the three records' rows.

## Reconciliation (full unpack, through the adapter, 2026-11-02)

312 records = the record's 312; 40,461 page lines = its 40,461; 1,750
blank by flag (one, 0007578 p73, carries stray model output "エンド" —
the flag governs) → 38,711 passages, 0 errors. volumes.tsv reign era +
year agree with western_year on all 312 through config/eras.yml.
