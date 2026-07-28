# tibetan-verbs fixtures

Trimmed real sample of the Tibetan Verbs Database (TVD) for the
`tibetan-verbs` adapter tests.

- Retrieved: 2026-07-28
- URL: https://raw.githubusercontent.com/tibetan-nlp/tibetan-verbs-database/master/db.csv
  (github.com/tibetan-nlp/tibetan-verbs-database — the whole upstream is
  one 146,676 B headered CSV, 2,491 data rows)
- License: CC0-1.0 (in-repo LICENSE file, verified 2026-07-28 — the
  GitHub license field agrees)

## Trim recipe

`db.csv` here is the upstream header + the first 24 data rows + 4
appended rows (all byte-verbatim upstream lines) = 28 entries, chosen to
document the upstream quirks (full-file census 2026-07-28):

- header row IS Tibetan: `ད་ལྟ,འདས་པ,མ་འོངས,སྐུལ་ཚིག,TDC,PH,GT,KN`
  (present, past, future, imperative + the four source columns; source
  cells carry exactly TDC/PH/GT/KN, censused whole-file).
- ཀེར ×3 (rows 2–4): the same present stem under three DIFFERENT
  source-attributed paradigms — upstream deliberately keeps the
  grammarians' disagreements as separate rows; the 4-stem tuples differ,
  so ids stay distinct without suffixes.
- ཀེར༼ད༽: the second-suffix ད in upstream's own Tibetan-parenthesis
  notation, verbatim.
- དཀའ (row 10): empty imperative (599 rows whole-file) — the lane is
  omitted, never faked.
- ཁ (appended, upstream line 125): present-only row (11 rows whole-file
  have empty past AND future).
- བྱེད,བྱས,བྱ,བྱོས ×2 (appended, upstream lines 1560/1562, with the
  intervening GT variant line 1561): one of the 5 whole-file duplicate
  4-tuples → the second occurrence gets the positional `:2` id suffix.
- ཀློག (row 9): the classic "read" paradigm attested by all four
  sources — the golden entry.
