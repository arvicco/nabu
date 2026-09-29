# ndl-kotenseki fixtures

Real captures retrieved 2026-09-29:

- `books/2532153.json` — the Bulk Download API (JSON) response for
  PID 2532153 (玉篇 巻中, the 1605 print's classical OCR), from
  https://lab.ndl.go.jp/dl/api/book/fulltext-json/2532153 — TRIMMED
  to the first 6 of 58 koma (the 2 empty cover koma, the title koma,
  3 text koma), the `hit`/`from` envelope kept.
- `census.tsv` — the adapter's own derived census shape (one header
  line + the PID's row), cut from the NDL open bibliographic dataset
  `dataset_202602_k_internet.xlsx`
  (https://dl.ndl.go.jp/static/files/dataset/dataset_202602_k_internet.xlsx,
  public domain, 2026-02 snapshot): the 権利区分「保護期間満了」filter
  and the column mapping in `NdlKotenseki::CENSUS_COLUMNS`.

Re-cut: fetch the fulltext-json URL and keep `list[0..5]`; re-derive
the census row by filtering the open-dataset xlsx to the PID.
