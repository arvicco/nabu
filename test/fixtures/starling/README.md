# StarLing / Tower of Babel fixtures (P22-0 — Pokorny + PIET)

Real upstream samples from the **StarLing Indo-European package**
(`IE.exe` — a plain zip despite the name), the Tower of Babel project's
downloadable etymological databases.

- **Retrieved:** 2026-07-15, from
  <https://starlingdb.org/download/IE.exe> — 6,464,232 B, sha256
  `e2b1cbb332419883f6e2d1e17387a3284beb8877eb39cf3fc07f040b49784b0f`.
  Full-package census at retrieval: `pokorny.dbf` 2,222 records /
  `piet.dbf` 3,291 / `germet.dbf` 1,994 / `baltet.dbf` 1,651 /
  `vasmer.dbf` 18,239 (+ LEXSTAT Swadesh tables). Only pokorny + piet
  are ingested in P22-0.
- **License / grant:** G. Starostin, e-mail 2026-07-15 — "all
  etymological data are free for anybody to use for any purposes as
  long as the source is properly acknowledged", with the EXPRESS
  condition that attribution name the specific compilers of each
  database (roster: <https://starlingdb.org/descrip.php?lan=en#bases>).
  Per-base credits: **pokorny** — the in-package `pokorny.inf` DBINFO:
  "scanned and recognized by George Starostin (Moscow), who has also
  added the English meanings. The database was further refurnished and
  corrected by A. Lubotsky."; **piet** — `piet.inf` DBINFO: "compiled
  on the basis of Walde-Pokorny's dictionary by S. L. Nikolayev. The
  Hittite and Tokharian reflexes were added by S. Starostin from the
  dictionaries of Friedrich, Tischler and Adams."
- **Format:** dBase III tables whose length-6 character cells are
  var-pointers (uint32 LE offset + uint16 LE length, field-descriptor
  byte 12 = `V`) into the sibling `.var` file; `.var` text is in
  StarLing's own encoding (single-byte page + `\x01`-shifted doublebyte
  runs + `\`-style markup), decoded via the vendored
  `config/starling/unipro.lst` (see its README).

## What was kept (3 of 2,222 / 3 of 3,291 records)

The fixtures are **trimmed, structurally intact rebuilds**: the DBF
header, field descriptors and the selected records' bytes are verbatim
upstream, every kept `.var` payload is the verbatim upstream byte run —
only the record count and the 6-byte var-pointers were rewritten to
address a compacted `.var` (payloads never move relative to their
records; the leading `\x13` var-header byte is mirrored). Decoded
output of every kept record was verified against the live
starlingdb.org web rendering on 2026-07-15.

- `pokorny.dbf`/`pokorny.var` — records **1** (ā 'interjection': the
  survey's `\x01\x83\xC2…` Greek font-shift run decoding to ἆ, the
  `\xB0` → ā single-byte, `\x15` paragraph marks, `\B\I…\b\i` markup;
  PIET crosslink 0 = absent), **721** (gʷer(ə)-4: parenthesised-schwa
  root, PIET crosslink → piet #1763), **1089** (kʷel-1, kʷelə-: ʷ
  modifier folds, the corpus's ONE unmapped byte pair `\x80\xA8` after
  τέλλω — upstream stray, decoded honestly as U+FFFD; PIET crosslink →
  piet #562, which is IN this fixture set).
- `piet.dbf`/`piet.var` — records **1** (*ay-er/n- 'morning': AVEST
  reflex `ayarə`, Khowar-prefixed IND cell that mints NO row, GREEK
  transcription column, GERM proto-form column, Cyrillic RUSMEAN утро,
  crosslinks PRNUM/GERMNUM/REFERNUM→pokorny #31), **562** (*kol-
  'neck': IND kaṇṭhá-/LAT collus/ALB qafɛ reflex rows, BALT+GERM
  proto columns with BALTNUM/GERMNUM links, REFERNUM→pokorny #1089 —
  the both-ways crosslink pair with the pokorny fixture), **1501**
  (*k'īgh- 'to move quickly': IND śīghrá- row, SLAV proto column with
  SLAVNUM→Vasmer #12561 — pins that proto-branch columns mint no rows
  even when their first token is clean).
