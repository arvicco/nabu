# stgall-priscian fixtures

`db_priscian_v2.sql` — a line-verbatim TRIM of the St Gall Priscian
Glosses database dump (phpMyAdmin, MySQL), the single data file of the
edition's website repository:

https://github.com/padraicmoran/stgallpriscian/blob/fdb2502e7ef97c4cd09ac25511271d1548759fc1/db_priscian_v2.sql

Retrieved 2026-10-14 (upstream HEAD fdb2502e, "Minor updates",
2026-06-16; the dump itself last changed in df7f07b2, "Upgrade to v2.1",
2023-06-28; full file 7,730,286 bytes — glosses 13,395 rows,
priscian_lines 23,245, types 86, word_instances 17,526).

License — the repository's LICENSE, verbatim header: "MIT License /
Copyright (c) 2023 Pádraic Moran", with the standard MIT grant ("…to
deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute…", the
notice to be included in all copies). Edition credits (README.md): "A
digital edition by Rijcklof Hofman, Pádraic Moran, Bernhard Bauer."
These rows are redistributed under that license.

## The trim

Every non-data line (header comments, SET statements, the four CREATE
TABLE blocks, the trailing SET lines) is kept verbatim. Of each table's
chunked INSERT statements only the FIRST header line is kept; the kept
tuple lines are byte-verbatim, except that the last kept tuple of each
table carries the statement's `;` terminator in place of its `,`.

- `glosses` — 26 rows on three manuscript pages:
  - p. 1: 1, 2, 8, 9, 13, 18, 23, 31
  - p. 2: 68, 71, 72, 73, 75, 84, 89, 92, 120
  - p. 51: 4188, 4192, 4200, 4206, 4207, 4209, 4224, 4227, 4229
- `priscian_lines` — the 24 Hertz lines those glosses sit on (matched on
  keil_vol / keil_page / keil_line).
- `types` — all 86 rows (note: codes 24 and 3223 occur twice upstream).
- `word_instances` — the 62 analyses whose glossID is a kept gloss.

What the selection documents:

- 13 `.i. attá di ṡe<add>i</add>rc …` — an Old Irish gloss with
  expansions, a scribal addition, a translation, 14 analysed words
  (homonym-indexed headwords such as `ad 1`).
- 9 `.i. libardaib`, 71 `.i. in<del>d</del>t airdircus`, 4207, 4224 —
  Latin-flagged (`irish` = 0) glosses whose words are analysed Old Irish
  forms; 71 also carries a scribal deletion.
- 92 `.i. ut accentus. d hí c` — a Latin gloss with one Irish element.
- 4227 `parcus` — flagged Irish upstream, Thesaurus ref `105`
  (unpadded); 89 likewise has the unpadded ref `50`.
- 2, 8, 4206 — construe marks (`<g>` symbols and `&gt; (…)` pointers);
  8 also carries a `{…}` editorial note citing the Karlsruhe Priscian.
- 120 `<g>XIII</g>` — a symbol-only numeral; 4200 `cautéla` — a
  term-only record with no gloss element.
- 23 — an editorial `<supplied>` letter; 84 — a `{…}` note after the
  gloss; 18 `in méit-so` — the known-gloss snippet.
- p. 1 and p. 51 are Old-Irish-majority in this selection, p. 2
  Latin-majority (five Latin glosses against three).

Upstream data warts seen in the full dump and NOT in the fixture
(covered by doctored-fixture tests): two `<add hand="C">` tags with an
attribute; five `{{212}}`-style double-brace markers inside a gloss;
one stray `}` (gloss 7464); gloss 11412 whose ms_num (201) disagrees
with its ms_ref (203a31) — the adapter documents by ms_num.

Re-cut: clone the repository at the commit above and re-apply the
procedure (keep the listed recordIDs; the dependent rows follow).
