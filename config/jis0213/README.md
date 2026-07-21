# JIS X 0213:2004 → Unicode mapping table

`jisx0213-2004-std.txt` — the Project X0213 reference mapping,
retrieved 2026-07-21 from http://x0213.org/codetable/jisx0213-2004-std.txt
(dated 3 May 2009; the table is stable — JIS X 0213:2004 has not been
revised since).

License (from the file header): Copyright earthian@tama.or.jp, I'O,
Project X0213 — "You can use, modify, distribute this table freely."

Consumers: the Aozora adapter (P38-3) resolves Aozora gaiji notation
`第N水準X-Y-Z` (men-ku-ten) to Unicode through this table. Key format:
plane 1 rows are `3-XXXX`, plane 2 rows `4-XXXX`, where XXXX is the
GL encoding of row/cell: byte1 = 0x20 + row, byte2 = 0x20 + cell
(e.g. 第3水準1-93-12 → `3-7D2C`). Some entries map to a two-codepoint
sequence written `U+xxxx+xxxx` (combining forms) — consumers must
handle both shapes.
