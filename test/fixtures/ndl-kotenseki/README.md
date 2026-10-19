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

Added 2026-10-18:

- `books/2541107.json` — PID 2541107 (古今武者揃, an 赤本 picture book),
  copied whole (17 koma, 16 KB) from the box's canonical crawl of the
  same bulk route. Its census row carries two ||-separated 著者 parts
  with trailing role tokens ("夷福山人 作||広重 画"), a シリーズタイトル
  (赤本昔はなし) and a 容量・大きさ (1冊 ; 12.2cm).
- `census.tsv` re-derived for both PIDs with the series/extent
  columns (the adapter's own `derive_census!` over the held xlsx).
