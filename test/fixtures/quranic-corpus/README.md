# quranic-corpus fixture

A trimmed real sample of the Quranic Arabic Corpus morphology file, version
0.4 (Kais Dukes, University of Leeds; corpus.quran.com) — the segment-level
morphological annotation of the whole Quran in Buckwalter transliteration.

- **File**: `quranic-corpus-morphology-0.4.txt`, retrieved 2026-11-27 from the
  mirror
  <https://raw.githubusercontent.com/q-ran/quran/master/sources/1.0/quranic-corpus-morphology-0.4.txt>
  (HTTP 200, `Content-Type: text/plain; charset=utf-8`, 6,309,503 bytes,
  ETag `"b154315e0f2eeaa527ad48816b14a84e972f2e88b9b477c5cbceee9417e33eae"`).
  The adapter fetches the same blob at the mirror's pinned commit
  `8abbbb2942f4479a8f314c04192d0c6f575ead15` (2019-03-14, the file's only
  commit in that repository):
  <https://raw.githubusercontent.com/q-ran/quran/8abbbb2942f4479a8f314c04192d0c6f575ead15/sources/1.0/quranic-corpus-morphology-0.4.txt>
  — byte-identical to the master copy at retrieval.
- **Full-file sha256** (the adapter's `FILE_SHA256` pin):
  `a1d12923815341face765083805d2148ed2d9f5cc3f7d6665219d887675d8c46`
- **Encoding**: pure ASCII, CRLF line ends, tab-separated.

## Why the mirror

The project's own download page (<http://corpus.quran.com/download/>) hands
the file out only after an email form — not an unattended route. The q-ran/quran
repository (the Text-Fabric edition of the Quran by Cornelis van Lit and Dirk
Roorda) carries the file verbatim in `sources/1.0/`, its copyright block intact,
as the source its own conversion reads. The file's terms permit verbatim
redistribution, which is what the mirror does; the adapter stores it
byte-for-byte as fetched and refuses any other bytes.

## The terms (verbatim, the file's own header)

The file opens with two copyright blocks — the Quranic Arabic Corpus
annotation and the Tanzil Quran text it builds on:

```
# PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK
#====================================================================
#
#  Quranic Arabic Corpus (morphology, version 0.4)
#  Copyright (C) 2011 Kais Dukes
#  License: GNU General Public License
#
#  The Quranic Arabic Corpus includes syntactic and morphological
#  annotation of the Quran, and builds on the verified Arabic text
#  distributed by the Tanzil project.
#
#  TERMS OF USE:
#
#  - Permission is granted to copy and distribute verbatim copies
#    of this file, but CHANGING IT IS NOT ALLOWED.
#
#  - This annotation can be used in any website or application,
#    provided its source (the Quranic Arabic Corpus) is clearly
#    indicated, and a link is made to http://corpus.quran.com to enable
#    users to keep track of changes.
#
#  - This copyright notice shall be included in all verbatim copies
#    of the text, and shall be reproduced appropriately in all works
#    derived from or containing substantial portion of this file.
#
#  Please check updates at: http://corpus.quran.com/download

# PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK
#====================================================================
#
#  Tanzil Quran Text (Uthmani, version 1.0.2)
#  Copyright (C) 2008-2009 Tanzil.info
#  License: Creative Commons BY-ND 3.0 Unported
#
#  This copy of quran text is carefully produced, highly
#  verified and continuously monitored by a group of specialists
#  at Tanzil project.
#
#  TERMS OF USE:
#
#  - Permission is granted to copy and distribute verbatim copies
#    of this text, but CHANGING IT IS NOT ALLOWED.
#
#  - This quran text can be used in any website or application,
#    provided its source (Tanzil.info) is clearly indicated, and
#    a link is made to http://tanzil.info to enable users to keep
#    track of changes.
#
#  - This copyright notice shall be included in all verbatim copies
#    of the text, and shall be reproduced appropriately in all files
#    derived from or containing substantial portion of this text.
#
#  Please check updates at: http://tanzil.info/updates/
#
#====================================================================
```

Licence class: `research_private`. The annotation block carries a GPL label
beside an explicit no-change clause, and the word forms rest on the Tanzil
text under CC BY-ND 3.0 with the same clause; the stricter reading governs, and
the house classes no-derivatives material `research_private` (the freising and
tipitaka-lk precedents): local research use, never redistributed, never a
dataset input. Credit names the Quranic Arabic Corpus with the link to
http://corpus.quran.com and the Tanzil project with the link to
http://tanzil.info.

## The trim

Lines 1–57 of the upstream file kept verbatim — both copyright blocks, the
blank lines between them and the `LOCATION FORM TAG FEATURES` column header —
followed by every row of three short suras, in upstream order, each line
byte-identical (CRLF kept):

| Sura | Verses | Rows (segments) | Pins |
|---|---|---|---|
| 1 | 7 | 48 | the opening sura; the `{ll~ah` proper noun, `PREFIX` / `STEM` segments |
| 109 | 6 | 38 | the empty-FORM segment `(109:6:4:2)` (the elided 1S suffix pronoun) |
| 112 | 4 | 19 | the last rows of the file's short-sura tail |

Recipe (the upstream file in a scratch directory):
`LC_ALL=C awk 'NR<=57 || /^\((1|109|112):/' quranic-corpus-morphology-0.4.txt`
— 162 lines, 7,384 bytes, sha256
`82ec7557936f6049cc9a74bce24815d99067c06bed70661112bb31d76864fe8b`.

## Grain census (whole upstream file, 2026-11-27)

What the corpus and its mirror serve:

- **Accepted**: `quranic-corpus-morphology-0.4.txt` — one file; the document
  is the sura (114), the passage the verse (6,236), the token the segment
  (128,219 rows).
- **In-file, not rows**: the 56 comment/blank header lines and the column
  header — the notice, kept in the stored file, never parsed into passages.
- **Not fetched**: the mirror's other `sources/1.0/` files (the Tanzil
  `quran-uthmani.xml` and `quran-simple-min.xml` texts, the `quran-data.xml`
  metadata, two translations) and its Text-Fabric tree; the corpus site's
  syntactic treebank (not part of the download). None of them lands in the
  workdir; anything beside the one file there is counted unrecognized.

Whole-file numbers: 114 suras, 6,236 verses (every sura's verses contiguous
from 1, matching the Tanzil metadata's per-sura counts), 77,429 words, 128,219
segments (28,670 PREFIX, 77,915 STEM, 21,634 SUFFIX), 208 empty-FORM segments,
4,832 distinct LEM values, 1,642 distinct ROOT values (1,602 triliteral, 40
quadriliteral), 45 TAG values.
