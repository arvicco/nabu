# qieyun-restored fixtures

One byte-verbatim trim from **nk2028/qieyun-restored** (branch `main`,
repo pushed 2025-03-02; MIT LICENSE at root), retrieved **2026-08-29**:

- `切韻 藤田拓海復元.csv` — the REAL first 166 lines (`head -n 166`) of
  the 11,159-line file (header + 165 data rows): the complete 東 rime
  (小韻 1–32) **plus the opening of 冬**, whose 小韻 numbering restarts
  at 1 — the restart the (頁, 行) entry id exists to survive. Raw URL:
  `https://raw.githubusercontent.com/nk2028/qieyun-restored/main/切韻 藤田拓海復元.csv`
  (URL-encoded upstream).

Upstream facts the tests pin: header
`頁,行,音韻地位描述,聲調,韻目,序数,小韻,音類,字頭,釋義`; zero quoted
cells, zero empty 字頭/釋義, all rows 10 fields, UTF-8 NFC-stable
(censused 2026-08-29 over the whole file); (頁, 行) unique ×11,158.

The sibling 切韻 李永富復元.csv (Li Yongfu's restoration, 11,163 rows,
97.4% byte-identical) is a censused witness lane, deliberately not
fixtured — the adapter never parses it.
