# ponomar fixture

Real upstream files, byte-for-byte, from the Ponomar repository
<https://github.com/typiconman/ponomar> (branch `master`, commit
`0af645f438856f45c22026912d2e4a9ce495e531`, 2025-08-17), retrieved
2026-11-04 by a blobless sparse clone. Paths are kept exactly as upstream
lays them out, under `Ponomar/languages/cu/xml/Services/`. No file is
trimmed: every Services file is a single small record.

## License (first-hand, 2026-11-04)

- `LICENSE` (repo root): the GNU General Public License, Version 3, 29 June
  2007 (GitHub reports the repo license as GPL-3.0).
- `README.md` (repo root), verbatim: "Copyright 2006-2018 Aleksandr Andreev
  and others. Ponomar is free software: you can redistribute it and/or
  modify it under the terms of the GNU General Public License as published
  by the Free Software Foundation, either version 3 of the License, or (at
  your option) any later version."
- The text files carry no license of their own; the repo-wide grant covers
  them. The Hours' own source records (`Text/*Source.xml`) credit
  `http://orthlib.ru` for the text.

## Delivery grains (the whole repo)

Upstream's git tree holds 39,350 entries. Under the adapter's sparse cone,
`Ponomar/languages/cu/xml/Services/` holds **347 files** (the only count
upstream advertises — its tree listing):

| Grain | Upstream count | Fate | Specimen here |
|---|---|---|---|
| `CommonPrayers/*.xml` COMMONPRAYER with Church Slavonic TEXT | 106 | **accepted** (document = file, passage = TEXT) | `NiceneCreed.xml`, `SufferingLord.xml` (English editor's HEADER) |
| `CommonPrayers/TROPARION/*.xml` (TROPARION or COMMONPRAYER root) | 56 | **accepted** | `TUES7.xml` (UTF-8 BOM, decomposed и + U+0300) |
| `CommonPrayers/KONTAKION/*.xml` | 61 | **accepted** | `FRI5.xml` (an editor's XML comment) |
| `Command/*.xml` rubric words | 14 | **accepted** | `Bow.xml` |
| `Text/*.xml` service titles + the Paschal Hours rubric | 9 | **accepted** | `ThirdHour.xml` |
| blank TEXT records | 3 | skipped by rule | `CommonPrayers/Ending.xml` |
| English placeholder stubs ("Church Slavonic Text is placed here.") | 4 | skipped by rule | `CommonPrayers/Template.xml` |
| source-credit records (TEXT = `http://orthlib.ru`) | 5 | skipped by rule | `Text/ThirdSource.xml` |
| program window captions ("Пономарь: Ча́съ тре́тїй") | 5 | skipped by rule | `Text/Third1.xml` |
| `Var/*.xml` SERVICE / SERVICES assembly templates | 28 | skipped by rule | `Var/PKath3.xml` (SERVICES), `Var/STYX61C.xml` (SERVICE) |
| `Octoecheos/Tone 0–7/*.xml` TONE schedules | 56 | skipped by rule | `Octoecheos/Tone 1/Monday.xml` |

Reconciliation: 246 accepted + 101 skipped by rule = 347; 0 unrecognized
(census through the adapter over the full Services tree, 2026-11-04).

Outside the cone (never fetched): the other languages' trees (`el`, `zh`,
`en`, `fr`, `la`, `ar`, and the language-neutral `xml/`), `cu/xml/lives/`
(3,041 commemoration files: Russian-language lives and, on 581 of them,
troparia/kontakia/idiomela in Church Slavonic), the menaion day indexes
`cu/xml/01`–`12`, the Elizabeth Bible text `cu/bible/elis`, `cu/ru/`
(civil-script renderings), icons (jpg), fonts, and the Java/Perl program
code.

## Fixture file list

Accepted (6): `Command/Bow.xml`, `CommonPrayers/KONTAKION/FRI5.xml`,
`CommonPrayers/NiceneCreed.xml`, `CommonPrayers/SufferingLord.xml`,
`CommonPrayers/TROPARION/TUES7.xml`, `Text/ThirdHour.xml`.

Rejected specimens (7): `CommonPrayers/Ending.xml`,
`CommonPrayers/Template.xml`, `Text/ThirdSource.xml`, `Text/Third1.xml`,
`Var/PKath3.xml`, `Var/STYX61C.xml`, `Octoecheos/Tone 1/Monday.xml`.

Recipe to re-cut: `git clone --depth 1 --filter=blob:none --sparse
https://github.com/typiconman/ponomar.git`, `git sparse-checkout set
Ponomar/languages/cu/xml/Services`, copy the files above preserving paths.
