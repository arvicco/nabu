# cntr fixtures

Retrieved 2026-11-21 from the Center for New Testament Restoration's
electronic transcriptions (github.com/Center-for-New-Testament-Restoration/transcriptions),
pinned at commit `4e743a41a4b2ca010ece53229cd272aa59b1efe6` (main,
2026-10-01 — the export upstream's README.txt stamps "Generated on
10/1/2026"). The repo has no tags or releases; the adapter fetches GitHub's
commit-addressed archive

    https://codeload.github.com/Center-for-New-Testament-Restoration/transcriptions/zip/4e743a41a4b2ca010ece53229cd272aa59b1efe6

(4,524,417-byte zip, sha256 `fe4eb90c5e6eec8c04f76dbe013248a54e83d6d51bb73919b7d9c85472dbeca4`,
byte-identical across two downloads at pin time; one top directory
`transcriptions-<commit>/`, which maps onto the workdir). Raw URL shape for a
single file: `https://raw.githubusercontent.com/Center-for-New-Testament-Restoration/transcriptions/<commit>/<path>`
(spaces as `%20`).

License: **CC BY-SA 4.0**. `LICENSE.md` is the full legal code ("Creative
Commons Attribution-ShareAlike 4.0 International"). Upstream's README.md
(not checked in here — this file takes its place in the fixture root) opens:
"Copyright © 2020-2026 by Alan Bunning. All rights reserved. Released under
the Creative Commons Attribution-ShareAlike 4.0 International License (CC
BY-SA 4.0)." and states the attribution term "You must give credit to Alan
Bunning and the Center for New Testament Restoration, and any derivative work
must likewise require that this attribution be included." Recorded slip:
the README's license heading ("## Creative Commons Attribution 4.0
International (CC BY-SA 4.0)") and README.txt ("Released under Creative
Commons Attribution 4.0 International License (CC BY-SA 4.0).") name the BY
license with the BY-SA code; LICENSE.md governs.

## Delivery grains upstream serves (the whole tree at the pin)

| Grain | Files | Taken? |
|---|---|---|
| `class 1/` — continuous-text witnesses, by Gregory-Aland number (P1…P141, 01…059, 0160…0326, O23) | 130 | **accepted**: one document per witness, one passage per verse |
| `class 2/` — extant manuscripts quoting the NT, by Trismegistos number | 47 + README.txt | **accepted** (47); README.txt skipped by rule |
| `class 3/` — church fathers' quotations, by CNTR's author abbreviation | 12 + README.txt | **accepted** (12); README.txt skipped by rule |
| `critical texts/` — KJTR, RP, SR, ST, WH (modern editions, 7,957 lines each) | 5 | rejected by rule (editions, not witnesses) |
| root — LICENSE.md, MES.g4 (the grammar), README.md, README.txt | 4 | skipped by rule (documentation) |

196 files in the four folders (189 accepted + 2 READMEs + 5 critical texts),
200 with the root documentation.

Inside a witness file the grain is one line per verse, `BBCCCVVV <MES>`
(BB 40–66). Letterless verse lines (`-` absent, `-~` absent by vid, `+~`
present by vid) mint no passage and land in the document metadata; a ref
repeated on several lines (a deleted dittography keyed to the same verse)
merges into one passage.

## Files

- `class 1/P52.txt` — WHOLE (5 lines): the John Rylands fragment, John
  18:31–33, 37–38 — lacunae (`&`, `*`, skipped lines `/11`), missing (`^`)
  and damaged (`%`) letters, supplied words (`~`, `+` by vid), a nomen
  sacrum (`+=ιηυ`).
- `class 1/0171.txt` — WHOLE (32 lines): Matt 10 + Luke 22 — a later
  hand's correction (`{κοιμενουσ} a{κοιμωμενουσ}`, Luke 22:45), two absent
  verses (Luke 22:51, 22:62), transpositional vid (`+~δε`), the overline `¯`.
- `class 1/03.txt` — TRIM of Vaticanus (11 lines): Matt 1:1–2 (page skip
  `\1186`, `το¯`), John 10:25 (a breaks-only edit `x{/} {ο}`), Rom 4:3–6
  (the dittography: 4:4–5 on two lines each, `x{…} {}` deleting the
  repeat), Phil 1:16–17 (the alternate-verse markers `⋄16` `⋄17`).
- `class 2/62312.txt` — WHOLE (1 line): TM 62312, once GA P12 (Heb 1:1
  quoted in private correspondence), with the kai ligature `ϗ`.
- `class 3/Meli.txt` — WHOLE (1 line): the father CNTR abbreviates `Meli`, Matt 22:43 (gaps both sides).
- `class 3/Orig.txt` — TRIM (2 lines): Origen, Matt 4:5 and 1 John 3:2 —
  the one off-grammar mark at the pin (`^εφα%ν%ε…`, a `^` before a word's
  first letter), tolerated and recorded by the parser.
- `class 2/README.txt`, `LICENSE.md`, `MES.g4`, `README.txt` — WHOLE,
  rejected-grain specimens (skipped by rule).
- `critical texts/SR.txt` — TRIM (3 lines, Matt 1:1–3): the rejected
  critical-text grain specimen.

Dry parse of the fixtures: 6 documents / 48 passages.

## Reconciliation (full tree at the pin, censused 2026-11-21)

189 witness files parse with 0 errors: **189 documents / 42,228 verse
passages** (class 1: 130 / 41,692; class 2: 47 / 400; class 3: 12 / 136),
717,544 word tokens, 3,012 corrections. Verse lines: 42,492 = 42,228
passages + 260 letterless verses + 4 repeat lines merged (01 1 Thess
2:13–14, 03 Rom 4:4–5).

## Re-cut recipe

Clone (or download the archive above) into a scratch directory — never
`canonical/`. Whole files copy as-is; trims keep upstream lines verbatim
and in order, selected by their 8-digit refs (03: 40001001 40001002
43010025 45004003 45004004 45004005 45004006 50001016 50001017; Orig:
40004005 62003002; SR: the first 3 lines).
