# menggu-ziyun fixtures

One byte-verbatim trim from **nk2028/menggu-ziyun-data** (branch `main`,
repo pushed 2025-02-15; MIT LICENSE at root, © 2025 nk2028), retrieved
**2026-08-29**:

- `data.tsv` — the REAL first 160 lines (`head -n 160`) of the
  9,447-line file (header + 159 character rows, small rhymes 1–14 of
  853). The trim deliberately reaches every optional-field kind the
  2026-08-29 census found: filled 釋義 (rows 9–10: 㓚 "刈也", 玒 "美玉"),
  an IDS-sequence 注釋 correction note with a plane-2 restored headword
  (row 40: 𧄓, 原卷作「⿰壴𰩨」), a 備選異體 variant (row 98: 衆/眾), and
  a 需作調整 deletion verdict (row 126: 唪 此字當刪 — which still mints,
  the guangyun 應刪字 stance; the trim carries BOTH 唪 rows).

Raw URL:
`https://raw.githubusercontent.com/nk2028/menggu-ziyun-data/main/data.tsv`

Census facts the tests pin (whole file): 9,446 data rows, all exactly 12
tab-separated fields, zero quoted cells; 釋義 filled on 104, 備選異體 on
320, 需作調整 on 54, 注釋 on 30; UTF-8 NFC-stable; 'Phags-pa is BMP
(U+A840–A87F) while headwords reach planes 2–3. small_rhymes.tsv (853
rows) is censused, not fixtured — the adapter never parses it.
