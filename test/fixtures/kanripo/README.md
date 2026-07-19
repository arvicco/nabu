# Kanripo fixture — Kanseki Repository, wave 1 (P33-0)

Seven real texts (2–3 per wave-1 class KR1/KR3/KR4) fetched individually
from github.com/kanripo — one repo per text — plus trimmed slices of the
KR-Catalog discovery index. The directory mirrors the canonical workdir the
adapter fetches: `KR-Catalog/` beside per-text dirs named by KR id.

- **Retrieved:** 2026-07-20, via `git clone --depth 1
  https://github.com/kanripo/<name>` (master — Kanripo keeps alternate
  editions as git *branches*; master is the BASEEDITION working text).
- **Text files are byte-verbatim upstream wholes.** Two repos are trimmed
  at the *repo* grain (a subset of their per-juan files, each file whole);
  the catalog files are byte-verbatim *slices* (org header + the complete
  entry blocks for the fixture ids).

## The texts (upstream HEAD sha at retrieval)

| dir | text | class | edition | files | trim | sha |
|---|---|---|---|---|---|---|
| KR1a0170 | 易緯坤靈圖 | KR1 | WYG | whole repo (000 header-only, 001, Readme) | none | 5067a9aa9992dd8328917c9f60598e6b6cd12db6 |
| KR1h0004 | 論語 | KR1 | CHANT | Readme + juan 001 + 020 of 20 | repo-trim: 18 juan files omitted | 89b65734d4386e2478179c77741a968bfc627abb |
| KR3a0001 | 孔子家語 | KR3 | SBCK | Readme + juan 001 of 11 | repo-trim: 000, 002–011 omitted | 47dc84abb7d01b95480800bff2e53be7a3440f6a |
| KR3g0023 | 青囊奧語 | KR3 | WYG | whole repo (single 000 file) | none | 2b8bb8b4076807e5f9c9af5194c83ed584c9da71 |
| KR3i0042 | 菌譜 | KR3 | WYG | whole repo | none | 6c2e78f41d6432b7f55c84bfd752413eb6f2be50 |
| KR4d0525 | 鯨背吟集 | KR4 | WYG | whole repo | none | 3556dec68237d96bc6de65357b478b2c8bacea98 |
| KR4j0026 | 無住詞 | KR4 | WYG | whole repo | none | e858eb7c47573893df92c59d4f166b66e2544c81 |

Chosen to attest the censused format spread: CHANT vs WYG vs SBCK base
editions; multi-branch repo (KR3a0001: master + SBCK + WYG + _data
branches); header-only `_000` files (KR1a0170, KR3i0042) beside `_000`
files that carry the whole text (KR3g0023) or a 提要 preface (KR4d0525,
KR4j0026); repeated ID/BASEEDITION header lines and `# src:` CHANT refs
(KR1h0004); mid-line `<pb:>` anchors; recto/verso leaf sides; the gaiji ref
`&KR0809;` (KR3g0023, page 000-2b); WITNESS/FILE properties (KR3a0001).
KR1h0004 論語 is the UD-Kyoto crosswalk anchor (P33-3). Parsed total,
pinned in tests: 139 page passages.

## KR-Catalog slices (upstream HEAD 927469cd1543dfeed828151090b0bdd366b11ef4)

`KR-Catalog/README.org` is whole. Each `KR-Catalog/KR/KR<sub>.txt` is the
real file's org header (through the `**` subclass heading) plus the
complete `***` entry block(s) for: KR1a0170, KR1b0049 (KR1b), KR1h0004,
KR3a0001, KR3g0023, KR3i0042, KR4d0525, KR4j0026. **KR1b0049 古文尚書寃詞
is a real catalog id with NO github repo** (one of 61 such wave-1 ids
censused 2026-07-20) — the fetch tests' recorded-absent case.

## License (org description, verbatim, retrieved 2026-07-20)

> Comprehensive collection of premodern Chinese texts. Licensed as CC BY
> SA 4.0.

Sampled repos carry no LICENSE file (github license field null).
Corroboration, ytenx `DATA_LICENSE.md`: "Kanseki Repository material
marked as CC BY-SA must be used under the applicable Creative Commons
Attribution-ShareAlike terms". Confirmation email to Christian Wittern
(№25) sent, non-blocking → `attribution`.
