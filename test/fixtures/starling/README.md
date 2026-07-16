# StarLing / Tower of Babel fixtures (P22-0 + P23-0 — all five IE bases)

Real upstream samples from the **StarLing Indo-European package**
(`IE.exe` — a plain zip despite the name), the Tower of Babel project's
downloadable etymological databases.

- **Retrieved:** 2026-07-15 (P23-0 re-fetch verified byte-identical),
  from <https://starlingdb.org/download/IE.exe> — 6,464,232 B, sha256
  `e2b1cbb332419883f6e2d1e17387a3284beb8877eb39cf3fc07f040b49784b0f`.
  Full-package census at retrieval: `pokorny.dbf` 2,222 records /
  `piet.dbf` 3,291 / `germet.dbf` 1,994 / `baltet.dbf` 1,651 /
  `vasmer.dbf` 18,239 (+ LEXSTAT Swadesh tables). pokorny + piet were
  ingested in P22-0; vasmer + germet + baltet joined in P23-0.
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
  dictionaries of Friedrich, Tischler and Adams."; **germet** —
  `germet.inf` DBINFO: "The Common Germanic database, compiled by
  S. Nikolayev and subordinate to the Common Indo-European database.";
  **baltet** — `baltet.inf` DBINFO: "The Baltic database, compiled by
  S. Nikolayev and subordinate to the Proto-Indo-European database.";
  **vasmer** — `vasmer.inf` is BLANK (whitespace only), so the credit
  quotes the roster paragraph (snapshot 2026-07-15): "scanned, OCR'd,
  and database-converted versions of M. Vasmer's etymological
  dictionary of Russian (currently serving as a substitute for the
  comparative Slavic database)".
- **Format:** dBase III tables whose length-6 character cells are
  var-pointers (uint32 LE offset + uint16 LE length, field-descriptor
  byte 12 = `V`) into the sibling `.var` file; `.var` text is in
  StarLing's own encoding (single-byte page + `\x01`-shifted doublebyte
  runs + `\`-style markup), decoded via the vendored
  `config/starling/unipro.lst` **and, since P23-0, `chslav.lst`** — the
  package's official Church Slavonic conversion, which owns the
  `\x01\x86–\x88` doublebyte range vasmer's Old Cyrillic citations are
  typed in (see `config/starling/README.md`). vasmer field labels come
  from the live CGI (its `.inf` carries no aliases): Word / Near
  etymology / Further etymology / Trubachev's comments / Editorial
  comments / Pages (web-verified on #20, 2026-07-15).

## What was kept (3–6 records per base)

The fixtures are **trimmed, structurally intact rebuilds**: the DBF
header, field descriptors and the selected records' bytes are verbatim
upstream, every kept `.var` payload is the verbatim upstream byte run —
only the record count and the 6-byte var-pointers were rewritten to
address a compacted `.var` (payloads never move relative to their
records; the leading `\x13` var-header byte is mirrored; the trailing
`0x1A` DBF EOF byte is mirrored where upstream has one — pokorny/
germet/baltet yes, piet/vasmer no). Decoded output of every kept record
was verified against the live starlingdb.org web rendering on
2026-07-15 (one known divergence: the legacy web converter renders the
single byte `\xF0` as ɵ where the official `unipro.lst` maps U+03D1 ϑ —
germet #513; the table is the authority).

- `pokorny.dbf`/`pokorny.var` — records **1** (ā 'interjection': the
  survey's `\x01\x83\xC2…` Greek font-shift run decoding to ἆ, the
  `\xB0` → ā single-byte, `\x15` paragraph marks, `\B\I…\b\i` markup;
  PIET crosslink 0 = absent), **721** (gʷer(ə)-4: parenthesised-schwa
  root, PIET crosslink → piet #1763), **1089** (kʷel-1, kʷelə-: ʷ
  modifier folds, the pokorny/piet corpus's ONE unmapped byte pair
  `\x80\xA8` after τέλλω — upstream stray, decoded honestly as U+FFFD;
  PIET crosslink → piet #562, which is IN this fixture set).
- `piet.dbf`/`piet.var` — records **1** (*ay-er/n- 'morning': AVEST
  reflex `ayarə`, Khowar-prefixed IND cell that mints NO row, GREEK
  transcription column, GERM proto-form column, Cyrillic RUSMEAN утро,
  crosslinks PRNUM/GERMNUM/REFERNUM→pokorny #31; GERMNUM=1 ⇄ germet #1
  PRNUM=1 — a both-ways pair inside this fixture set), **562** (*kol-
  'neck': IND kaṇṭhá-/LAT collus/ALB qafɛ reflex rows, BALT+GERM
  proto columns with BALTNUM→baltet #1634 and GERMNUM→germet #390 —
  both IN this fixture set — and REFERNUM→pokorny #1089, the both-ways
  pokorny pair), **574 BOTH TIMES** (the upstream NUMBER collision that
  quarantined the owner's live piet load, 2026-07-16: file position 573
  = *kōim- 'village', the in-sequence record, keeps the plain id; file
  position 1573 = *kneuk-, -g- 'to shout', sitting exactly where the
  vacant 1574 belongs — evidently a dropped leading "1" — mints the
  stable suffix `574-b` plus an honest body note; the live CGI itself
  serves "Total of 2 records" for number 574), **1501** (*k'īgh- 'to
  move quickly': IND śīghrá- row, SLAV proto column with
  SLAVNUM→vasmer #12561 — IN this fixture set — pinning that
  proto-branch columns mint no rows even when their first token is
  clean), **3278** (one of piet's six HEADWORD-LESS content-bearing
  Iranian stubs at the file tail — the second whole-file quarantine
  class; the live CGI serves "Total of 0 records" for it, so its
  content exists only in the downloadable package — kept under the
  mechanical `#3278` placeholder).
- `vasmer.dbf`/`vasmer.var` (P23-0) — records **1** (а: the chslav pin —
  OCS азъ in the `\x01\x87…` Church Slavonic font range; no reflexes,
  no gloss lane — vasmer is prose fields only), **20** (абракада́бра:
  the ONE record class with all five text fields — GENERAL/ORIGIN/
  TRUBACHEV/EDITORIAL/PAGES — pinning the live-CGI field labels),
  **12561** (сига́ть, — headword verbatim with the dictionary's
  inflection-follows comma, as the live site renders it; the piet
  #1501 SLAVNUM target, closing that crosslink inside the fixture set).
- `germet.dbf`/`germet.var` (P23-0) — records **1** (*aira- 'early':
  rich per-language columns; OLFRANK "ONFrank ēr" pins the
  variety-ambiguous body-only verdict; PRNUM=1 ⇄ piet #1), **390**
  (*xálsa-z 'neck': GOT hals / OENGL heals join the got/ang gold —
  the ReflexViews attestation pin; PRNUM=562 ⇄ piet #562 GERMNUM=390),
  **401** (one of germet's six fully-EMPTY numbered placeholder slots
  — nothing but NUMBER; kept under the mechanical `#401` placeholder,
  baltet carries seven of the same shape), **513** (*marϑiō ?
  'wedding': GOT cell "CrimGot marzus" — the censused STOP_TOKENS gate
  pin, a Crimean Gothic label lead that mints nothing; doubt-marked
  headword verbatim).
- `baltet.dbf`/`baltet.var` (P23-0) — records **76 BOTH TIMES** (the
  upstream duplicate-NUMBER pair: file position 36 = *blus-ā̂ 'flea',
  which per piet #76's dangling BALTNUM=37 evidently should be #37 but
  wears 76 — file order rules, it keeps the plain id; file position 75
  = *dal-i-s 'part', the in-sequence record, mints `76-b` + the body
  note; baltet has six such pairs, censused in the P23-0 backlog
  block), **1634** (*kakla- 'neck; throat': PRNUM=562 ⇄ piet #562
  BALTNUM=1634 — the both-ways pair; Cyrillic glosses inside LITH
  cells; NOTES body line).
