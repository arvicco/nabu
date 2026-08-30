# zhongyuan fixtures

One byte-verbatim trim from **nk2028/zhongyuan-data** (branch `main`,
repo pushed 2025-05-22; CC0 1.0 full legal code at root), retrieved
**2026-08-29**:

- `中原音韻.tsv` — the REAL first 80 lines (`head -n 80`) of the
  5,878-line file (header + 79 character rows, the 東鍾 rhyme's opening).
  The trim deliberately reaches every optional-field kind the 2026-08-29
  census found: 校註 editorial notes (row 43: 憽 原作“愡”，誤; row 78:
  䩺 四庫本作“𨎃” — a plane-2 variant char) and filled 釋義 (row 48:
  囱 "煙突"; row 69: 叿 "人聲").

Raw URL:
`https://raw.githubusercontent.com/nk2028/zhongyuan-data/main/中原音韻.tsv`
(URL-encoded upstream).

Census facts the tests pin (whole file): 5,877 data rows, all exactly 12
tab-separated fields, zero quoted cells; 釋義 filled on 13, 校註 on 94;
(小韻, 字) pairs duplicate-free; UTF-8 NFC-stable. The four
reconstruction columns are 楊耐思 (1981), 寧繼福 (1985), 薛鳳生(音位)
(1990), unt(音位) + unt transcription (2021), per the README's source
list; the repo's verify.py cross-checks descriptions against the IPA.
