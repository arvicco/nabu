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
- `kart/kartet.dbf`/`kart/kartet.var` (P46-6) — the SECOND package:
  **`KART.exe`** (a plain zip like IE.exe), retrieved 2026-07-26 from
  <https://starlingdb.org/download/KART.exe> — 211,769 B, sha256
  `311ed963131fd3ee031b060c55d210a64a6497fd76e64e9281d6c7677ef6602e`;
  full-base census at retrieval: `kartet.dbf` 1,310 records (matching
  the `kartet.inf` DBINFO's own "1310 entries"), non-empty reflex cells
  GRU 1,241 / MEG 1,010 / SVA 659 / LAZ 722, duplicate NUMBERs 48 and
  134 (×2 each — the second 134 sits at file position 1133, piet's
  dropped-leading-digit shape). Credit (kartet.inf DBINFO verbatim):
  "compiled by S. Starostin on the basis of G. Klimov's and
  Faehnrich-Sardhveladze's etymological dictionaries of Kartvelian
  languages"; roster item 6 concurs ("Compiled by Sergei Starostin …
  (G. Klimov and H. Faehnrich-Z. Sardzhveladze)"). Same trim recipe as
  the IE bases (records byte-verbatim, var-pointers rewritten against a
  compacted `.var`; no trailing `0x1A` — kartet.dbf has none upstream).
  Records kept: **1** (\*abed- 'tinder' — decoded PROTO/RUSMEAN/GRU/MEG/
  SVA/LAZ/NOTES verified against the live starlingdb.org CGI rendering
  on 2026-07-26, including the Svan comma-multiform "haböd-, habed-,
  hobed-"), **2** (\*ac̣- — PRNUM=1207 → the unheld Nostratic base, the
  body-line crosslink pin; empty SVA cell), **21** (\*baba — all four
  reflex columns mint), **48 BOTH TIMES** (\*berq- 'foot, step' at file
  position 47 keeps the plain id; \*ćwet- at position 147 mints `48-b`
  + the body note; its GRU cell "cwet-/cwit-/cwt-" pins the unspaced
  slash-variant token minting as one form).

## The P104-3 packages (six further downloads, same grant)

Retrieved **2026-09-26** from `https://starlingdb.org/download/<NAME>.exe`
(each a plain zip despite the name, like IE.exe/KART.exe):

- `ALTAIC.exe` — 1,950,481 B, sha256
  `855e82a67a8f7b1c6a9c50e6f7098b229228446210712049969f5cffd3e1d048`;
  census: altet 2,805 / turcet 2,017 / monget 2,174 / tunget 2,435 /
  koret 1,206 / japet 1,705 (+ LEXSTAT).
- `CAUC.exe` — 1,304,331 B, sha256
  `b0187353194a844b6dd458211db6733856290d747c9f67bf89e8470a1f79642c`;
  census: caucet 2,327 (223 headword-less) / nakhet 970 / aandet 1,539 /
  cezet 1,108 / laket 955 / darget 924 / lezget 1,569 / khinet 349 /
  abadet 817 (+ LEXSTAT).
- `SINTIB.exe` — 2,404,279 B, sha256
  `dd87b7bbadf1eba4ce7ef216de377cb610cbbdfbc953527fe928a8f3c741c26d`;
  census: stibet 2,823 (46 headword-less) / bigchina 9,093 (Big5
  CHARACTER/FANQIE cells) / doc 2,614 (dialect-readings support table) /
  kiret 994 / dumet 1,517 / kulet 1,466 / limet 2,354 / yamet 1,974
  (+ LEXSTAT).
- `DRAV.exe` — 2,118,705 B, sha256
  `1ff655a7ca0c99e73300cd6e91710556fd098a62a0d662018d975cfe0005a5d3`;
  census: dravet 2,171 / sdret 4,692 / telet 2,774 / kogaet 1,509 /
  gndet 1,428 / gonet 1,475 / kuiet 1,377 / konet 961 / ktet 1,665 /
  ndret 989 / pemet 740 / braet 269 (+ LEXSTAT).
- `CHUKCHEE.exe` — 772,741 B, sha256
  `9b00cca7636eb96d30e1aee17400bf8164abd075873b49a45e20771cb4136e2e`;
  census: kamet 1,099 (dup NUMBER 689 ×2) / chuket 2,281 (dups 1206/
  1584/1657/1956 ×2) / itelet 1,673 (dups 199/269/1119/1521 ×2)
  (+ LEXSTAT).
- `YENISEY.exe` — 198,208 B, sha256
  `91ad3ddba76d68466b01438376a808508ba7463c5c65172b00deabc490cca5bf`;
  census: yenet 1,059 (dup NUMBER 904 ×2, 2 headword-less) (+ LEXSTAT).

Same trim recipe as the IE bases (records byte-verbatim, var-pointers
rewritten against a compacted `.var`, the leading var header byte and
any trailing `0x1A` DBF EOF byte mirrored — japet/kamet have one, the
rest do not), with one addition: **upstream-defect pointer cells stay
byte-verbatim** so the fixtures pin the parser's two P104-3 lanes.

### What was kept (per base, one subdir per package)

- `altaic/altet.dbf`/`.var` — records **1** (*èbà 'to join, meet': all
  five branch protoform columns + all five branch links; JAPNUM=632 ⇄
  japet #632 PRNUM=1, the both-ways pair inside this fixture set), **2**
  (brace-notation gloss `{rage, anger}`, Nostratic PRNUM line, no KOR
  cell), **1728** (*pā̀ró 'to buy, sell' — THE junk-pointer pin: the TURC
  slot holds the literal whitespace bytes `0a 20 20 0a 0a 20` where a
  var pointer belongs; kept byte-verbatim, reads as an empty field).
- `altaic/japet.dbf`/`.var` — records **1** (*muta: AJP mints ojp;
  English MEANING "together with" beside RUSMEAN), **2** (*páp(u)í
  'ashes': the full dialect-column spread TOK/KYO/KAG/NAS/SHU/HAT),
  **632** (*àp- 'to meet': PRNUM=1 ⇄ altet #1 JAPNUM=632).
- `cauc/caucet.dbf`/`.var` — records **1** (*ḳwĭrV 'leg bone': NAKH/LEZG
  branch protoforms + Hurro-Urartian comment; PRNUM → the unheld sccet
  base), **2** (*Hrimq̱̇wV̆ 'ashes, soot': the ACTUAL-form columns LAK ḳa
  and KHIN zäḳ mint lbe/kjj rows), **9** (one of the 223 headword-less
  records — content-bearing LEZG cell under the `#9` placeholder).
- `sintib/stibet.dbf`/`.var` — records **2** (*bā(H) / *phā(H): the
  Big5-lead pin — the CHIN cell's character byte decodes to the honest
  U+FFFD, Starostin's OC transcription after it survives whole;
  CHINNUM/KIRNUM/PRNUM links; the unaliased STLSNUM=824 rides nowhere),
  **5** (TIB `ãphar` — the transliterated column's body-only pin), **8**
  (*[b]iw: LEPCHA `kŭm-bŭ` mints lep, KACH `nbo1` is tone-digit gated),
  **2785** (THE truncated-var pin: seven pointers at 663142+ against
  upstream's 640,352-byte `.var`, kept byte-verbatim — every affected
  cell reads as U+FFFD).
- `drav/dravet.dbf`/`.var` — records **1** (*ac- 'stamp, mould': the
  "****" overflow sentinel in GNDNUM/NDRNUM/BRANUM — no crosslink line
  without a number; SDRNUM/TELNUM links intact), **2** (*as- 'to move':
  NDR branch protoform), **16** (*aḍḍ- 'to hinder': BRA `aḍ` mints brh;
  all six branch links live).
- `chukchee/kamet.dbf`/`.var` — records **1** (*maĺ'mɨ: CHUKNUM=804 ⇄
  chuket #804 PRNUM=1 and ITELNUM=1 ⇄ itelet #1 PRNUM=1 — both pairs
  inside this fixture set; Russian gloss), **2** (empty PRNUM — no
  Nostratic line), **689 BOTH TIMES** (the upstream duplicate-NUMBER
  pair: *'el 'no, negation' keeps the plain id, *hehe 'axe' mints
  `689-b` + the body note).
- `chukchee/chuket.dbf`/`.var` — records **1** (*ạlạ 'summer': CHU/KOR/
  ALU mint ckt/kpy/alr, PAL body-only; the reference columns IM/BOG/NRS/
  YFA/PAK; NIODNUM link; unaliased STPRO/CHFUNC/KOFUNC/ALFUNC ride
  nowhere), **804** (*macbɨ #: the kamet #1 both-ways pair; trailing
  `#` marker verbatim).
- `chukchee/itelet.dbf`/`.var` — records **1** (*məźə-m: PRNUM=1 ⇄ kamet
  #1 ITELNUM=1; Dybowski's Western Kamchadal columns with Latin/Polish
  glosses; unaliased ICOST/WCOST ride nowhere), **2** (*meč'a- 'far':
  ITE mints itl; Kovran/Stebnitski variant columns).
- `yenisey/yenet.dbf`/`.var` — records **1** (*ʔaʔd 'bone': KET/SYM/KOT
  mint ket/yug/zko; PRNUM → the unheld sccet base), **904 BOTH TIMES**
  (the duplicate-NUMBER pair: *ʔa 'to become' keeps the plain id — its
  KET/SYM affix leads `-a`/`-e-` are gated, KOT mints — and *qo- 'to
  lick' mints `904-b`; its KET `qɔ:` length-colon lead is gated).

Decoded output of the kept records was verified against the live
parse of the full upstream tables (the same decoder path end to end);
the per-base field labels are the packages' own `.inf` aliases.

## The LEXSTAT tables (P113-2 — inside IE.exe, same retrieval)

`IE.exe` (above: retrieved 2026-07-15, sha256 `e2b1cbb3…`) also ships a
`LEXSTAT/` subtree: 13 lexicostatistical `.dbf` tables with `.inf`
siblings (+ five `.png/.jpg/.wmf` tree images) — 31 files. Census at
fixture time (2026-10-01, read from the held package tree):

- **Ten wordlists** — `balt` 118 records / `celt` 129 / `dard` 149 /
  `germ` 154 / `ind` 198 / `iran` 172 / `mix` 141 / `pi` 223 / `rom` 146 /
  `slav` 133. Shape: NUMBER (wordlist item 1..110) + WORD (English
  meaning) + per-language FORM columns each followed by `<COL>NUM` (the
  cognation number). File position 0 is the per-language date row
  (century values). Positive cognation numbers are entry ids of the base
  each `.inf` names (`proto = \data\ie\baltet.dbf` / germet / piet /
  `lexstat\dardet` / `indet` / `iranet`) — every positive cell resolves
  (mix: 858 of 861). 23,096 non-empty form cells in all.
- **Three Indo-Iranian etymology tables** — `dardet` 426 / `indet` 520 /
  `iranet` 498 (18 of them fully-empty NUMBER-0 blank slots): the
  PROTO/PRNUM/MEANING etymology shape, PRNUM → piet (1,004 of 1,004
  links resolve).
- Inline character cells only — **no `.var` siblings** upstream, no V
  descriptors. Column labels: `pi.inf`'s field aliases (the package's
  one full alias set; `balt.inf`/`germ.inf` repeat it, the rest carry
  none). No `.inf` carries a DBINFO credit.

Same trim recipe minus the var rewrite (records byte-verbatim, header +
descriptors verbatim, only the record count rewritten; the trailing
`0x1A` mirrored — balt/germ have one, iranet does not):

- `LEXSTAT/balt.dbf` — file position 0 (the date row: LIT 20 / LET 20 /
  JAT 18), items **1** (all: vìsa- / viss / wisa → baltet #607), **2**
  (ashes: the `-666` Yatvingian cell with no form — mints nothing),
  **26 BOTH ROWS** (fat n.: riebalaĩ + the synonym row's taukaĩ →
  `26.lit` / `26.lit-b`), **58** (neck: kãklas / kakls → baltet #1634
  \*kakla-, IN this fixture set — the both-ways pin), **64** (person:
  LET cilveks `-1`, JAT mard → #1065), **106** (snake: the `-4`/`-5`
  non-positive numbers).
- `LEXSTAT/germ.dbf` — file position 0 (the date row: GOT 4 / AIS 10 /
  AEG 8 / AHD 9, modern 20), items **1** (all), **2** (ashes: RKS aske
  `-1`, AHD "asca, asga"), **3** (bark: the `-100` Gothic cell with no
  form), **58 BOTH ROWS** (neck: GOT hals → germet #390 \*xálsa-z, IN
  this fixture set; the synonym row's HOL nek → #874 and AEG swēora).
- `LEXSTAT/iranet.dbf` — NUMBER **1** (\*hama 'all': "hama hama" form +
  etymon cells, OSS äppät, REF "\*hama-kaϑa всем домом Аб.", PRNUM →
  piet #3005), **3** (\*pawasta 'bark'), **127** (headword-less: MEANING
  nose + REF only → `#127`), and the first NUMBER-0 blank slot (file
  position 293).

## The branch-bases wave (the 2026-10-01 extension grant)

The 28 subordinate bases of the ALTAIC / CAUC / DRAV / SINTIB packages
(census above, "The P104-3 packages") ride as BASES rows from
`StarlingBranchBases`. G. Starostin's e-mail of 2026-10-01 extends the
2026-07-15 grant to every downloadable database under the same
conditions (any use, per-base attribution wherever displayed); each
base's credit is its own `.inf` DBINFO text (koret.inf has none — its
credit is the Altaic package's AED). Samples were cut on 2026-10-07 from
the held 2026-09-26 package trees (sha256 above) with the P104-3 recipe;
the decoded records of every kept sample were verified identical to the
same records parsed from the full upstream tables.

- `altaic/turcet.dbf`/`.var` — records **2** (*kül 'ashes': all 29
  language columns filled — the 27 minting columns plus Old Turkic
  "kül (OUygh.)" and Middle Turkic, body-only by the mixed-source
  verdict), **1931 BOTH TIMES** (the upstream duplicate-NUMBER pair: file
  position 1922 = *bẹŕ- 'to shiver' keeps the plain id, position 1930 =
  *jabĺan 'wormwood' mints `1931-b` + the body note), **2001** (*ab- 'to
  crowd': PRNUM=1 ⇄ altet #1 TURCNUM=2001, the both-ways pair).
- `cauc/lezget.dbf`/`.var` — records **1** (*zo-n 'I': all nine
  Lezgic columns mint; the alias-less COMMENT column), **3** (*ḳʷir(a)
  'hoof': PRNUM=1 ⇄ caucet #1 LEZGNUM=3), **11** (*ḳosʷɨ- 'to bite':
  PRNUM=9 ⇄ caucet #9 LEZGNUM=11; Udi `k:aIšpsun` — the ":" tense mark
  gates the lead, body only).
- `drav/sdret.dbf`/`.var` — records **2** (*agasai 'common flax': KTNUM
  0, the logical CHECKED flag riding nowhere), **42** (*ac- 'mould,
  type': PRNUM=1 ⇄ dravet #1 SDRNUM=42; ta/ml/kn/kfa/tcy mint, the KT
  Proto-Nilgiri protoform body-only, KTNUM=1157 → ktet), **384** (one of
  sdret's 807 headword-less records → the `#384` placeholder, still
  minting its Tamil/Malayalam/Kannada forms).
- `drav/ktet.dbf`/`.var` — records **766** (the bare "?" protoform: its
  fold is empty, so the entry folds under its NUMBER — THE regression pin
  for the numeric-cell encoding defect found at the full-scale dry parse:
  N cells were sliced binary and reached validation as ASCII-8BIT),
  **1157** (*as (*-c) 'mould for casting iron': PRNUM=42 ⇄ sdret #42
  KTNUM=1157).
- `sintib/kiret.dbf`/`.var` — records **2** (*ʔìŋ 'buy': Khaling/Limbu/
  Yamphu mint, LIMNUM=460 → limet #460 and YAMNUM=425; PRNUM 0), **645**
  (*bhä́[p] 'broad, wide': PRNUM=2 ⇄ stibet #2 KIRNUM=645; the stress-led
  Khaling lead `'bhäppä` is gated).
- `sintib/limet.dbf`/`.var` — records **1** (a- 'my.': the grammar-only
  body), **460** (iNmaʔ, -iN- 'buy, purchase.': PRNUM=2 ⇄ kiret #2
  LIMNUM=460) — G. van Driem's Limbu dictionary in the original Leiden
  transcription.

### The .var frame census (found at the first live parse-only sync)

Every `.var` file is a heap of FRAMED payloads: uint32 owner NUMBER +
the tag byte `0x12`, then the text (stale payloads of edited records
stay in the heap). A live payload never contains a frame byte (`0x12`)
or NUL — censused over all 47 var-backed tables of the eight packages,
exactly THREE pointer cells break the frame, all in the Altaic branch
bases, and all three are kept byte-verbatim here:

- `altaic/tunget.dbf`/`.var` — record **42** (*xol-sa 'fish'): the SOL
  pointer lands ON a frame tag and spans 37 bytes across two
  neighbouring frames (a stale copy of the REFERENCE text, a stale
  `*liamba-`, record 43's frame), NULs inside — the NULs reached the
  catalog INSERT and quarantined the record at the live sync; record
  **1821** (*kīran 'eagle'): the MAN pointer lands on the UDE payload's
  frame tag and spans 1,816 bytes of following frames. Both cells read
  as U+FFFD (no payload starts there); the records land whole and the
  damaged Manchu cell mints no mnc row.
- `altaic/monget.dbf`/`.var` — record **2161** (*čubali 'ant'): the MMO
  pointer starts cleanly and runs one NUL past its payload — it ends at
  the frame byte, `čubali (MA 136)`, and mints its xng row.
