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

Added 2026-10-19 (the NDL Search bib join):

- `books/2537051.json` — PID 2537051 (花かつみ考), copied from the box's
  canonical crawl and trimmed to the first 4 of 31 koma; its census row
  (appended to `census.tsv`) carries only the prose date 寛政7序, the
  case the bib record's issued year fills.
- `sru/searchRetrieve-3.xml` — the live NDL Search SRU answer
  (https://ndlsearch.ndl.go.jp/api/sru, operation=searchRetrieve,
  version=1.2, recordSchema=dcndl, maximumRecords=200) for the CQL
  `anywhere="info:ndljp/pid/2532153" OR anywhere="info:ndljp/pid/2537051"
  OR anywhere="info:ndljp/pid/2541107"`, kept whole.
- `sru/diagnostic.xml` — a live SRU diagnostic answer (the interface
  refuses `(dpid=… OR dpid=…) AND (…)` as "illegal query syntax").
- `bib/<pid>.xml` — the adapter's sidecar shape: 2532153, 2537051 and
  2541107 split from `sru/searchRetrieve-3.xml` by
  `NdlSearchBib.sidecar`; 2546138 (ホメーロス批判, a digital-collection
  record with NDC 991, NDLC KP25, a life-years creator and a publisher
  location) split the same way from a live 50-PID census batch.

Metadata terms: NDL Search API provider list
(https://ndlsearch.ndl.go.jp/help/api/provider) — iss-ndl-opac and
ndl-dl-open metadata CC BY 4.0.

Re-cut: re-run the SRU query above and split it with
`NdlSearchBib.sidecar(pid, NdlSearchBib.records_for(pid, page.records))`.
