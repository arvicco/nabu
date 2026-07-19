# HDIC fixtures (P32-4 — Hanzi Dictionaries in Early Japan)

Real upstream samples of the **HDIC project** databases (CLAUDE.md fixture
rules; docs/backlog.md P32-4). Every kept row is **byte-verbatim** upstream
data under the full `#` comment headers (provenance, credits, the per-file
license grant); only the row SET was trimmed.

- **Upstream:** `https://github.com/shikeda/HDIC` — the ACTIVE repo
  (README "Last modified: July 8, 2026"; last push 2026-07-15,
  `TSJ_wakun.tsv` v1.1.8). The nk2028/HDIC mirror is a stale 2022 fork and
  was NOT fetched.
- **Retrieved:** 2026-07-19, clone at commit
  `c8c36835228d8e6be6ee5237517aa1f05ef83b21` (2026-07-15T16:09:08+09:00).
- **License (verbatim README.md §"Data License Information and Access
  Rights"):** "License / Creative Commons Attribution-ShareAlike 4.0
  International License (CC BY-SA 4.0)" + "Access Rights (Availability) /
  Open access". Every data file below carries the same in-file grant in
  its header. **DISCREPANCY (owner gate):** the repo-level `LICENSE` file
  is the CC BY-NC-SA 4.0 LEGALCODE ("Attribution-NonCommercial-ShareAlike
  4.0 International"). Git forensics: upstream commit `72cfe74`
  (2022-02-02, "ライセンスの記述を変更") moved README + every file header
  from CC BY-NC 4.0 to BY-SA but placed the BY-NC-SA legalcode in LICENSE
  — an apparent template mismatch, journaled in the adapter, sources.yml
  and 02-sources; classed `attribution` per the concordant grants pending
  the owner ruling.

## The upstream file census (2026-07-19, full-file row counts)

| DB | File | Rows | Work |
|---|---|---|---|
| YYP | YYP.tsv | 2,087 | Yuanben Yupian 原本玉篇 fragments (Gu Yewang, 543), updated 2026-05-23 |
| KTB | KTB.tsv | 18,932 | Tenrei Banshō Meigi 篆隸萬象名義 (Kūkai, c. 827-835) — the project-claimed "TBM", VERIFIED present |
| TSJ | TSJ_definitions.tsv | 19,980 | Shinsen Jikyō 新撰字鏡 (Shōju, c. 898-901), VERIFIED present |
| TSJ | TSJ_wakun.tsv | 3,828 | TSJ Japanese readings (wakun) DB, v1.1.8 2026-07-15 |
| SYP | SYP.tsv | 22,809 | Songben Yupian 宋本玉篇 (1013) |
| KRM | KRM.tsv | 32,607 | Ruiju Myōgishō 類聚名義抄 (Kanchiin ms., 12th c.) — updates MOVED to github.com/shikeda/krm |

Not ingested (censused): `GLS*`/`YQF.tsv` "In preparation" upstream; `ZRM`
only on the sample-dev branch; `TSJ_entries.tsv` (24,381 headword-list
rows) and the `*_ndl`/`KTB_entries`/`KRM_definitions`/`KRM_wakun`/
`SYP_keio` edition concordances stay upstream.

## Format reality (what these fixtures preserve)

- `#` comment header, then ONE column-name row, then tab-separated rows;
  column names differ per database (YYID/SYID/TBID/TSJ2ID/KRID_n…).
- `TBID`/`SYID`/`YYID` columns are the project's own cross-dictionary
  links (KTB 1_016_A51 一 → SYP a005a101 一).
- TSJ_definitions has exactly ONE row with an empty `Entry_word` cell
  (s0811a303a — kept here as the skip-by-rule exemplar); headwords may be
  IDS sequences (s0104a602a `𬻃⿳一丷兀…`) or multi-character (KRM's
  `一／人` slot notation).
- TSJ_wakun joins TSJ_definitions by `tsj_id` (s0104a705 鬵 → sj_w00001
  カナヘ; man'yōgana source 倭云加奈戸, historical kana, POS).

## These files (trims, one-shot recipe run 2026-07-19)

Each fixture = full `#` header + column row + the first 12 data rows of
its file, plus (TSJ_definitions) rows `s0104a705`/`s0104a804` (the two
wakun-attested exemplars — a705 is within the first 12) and `s0811a303a`
(the empty-headword row); TSJ_wakun keeps only its rows `s0104a705` and
`s0104a804`. Selection by first-column id, order preserved, bytes
verbatim.
