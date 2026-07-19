# Kanripo fixture — Kanseki Repository, waves 1–2 (P33-0, P33-1)

Ten real texts (2–3 per wave class KR1/KR2/KR3/KR4) fetched individually
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
| KR2a0001 | 史記 | KR2 | tls | Readme + section 201 of 14 section files | repo-trim: 13 section files omitted | 1c19dc6fa970b1c530fced9e8e3697d19163c26c |
| KR2a0038 | 明史 | KR2 | WYG | Readme + juan 046 of 548 | repo-trim: 547 juan files omitted | eccd6fe93126bde61b837240e6142e1343c22639 |
| KR2g0007 | 杜工部年譜 | KR2 | WYG | whole repo (000, 001, Readme) | none | c5bdb391e82298514d20d679e23feebdf309a4d9 |
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
pinned in tests: 253 page passages (139 wave 1 + 114 wave 2).

The three KR2 texts (P33-1) attest the wave-2 census additions. KR2a0038
明史 juan 46 (二十四史; WYG) carries BOTH new shapes on real bytes: the
interleaved edition-volume anchors `<pb:KR2a0038_WYG_WYG0297-0606c>` /
`-0609b>` (alpha-prefixed WYG volume ordinal, a/b/c print registers —
annotated as `edition_pages`, never text, never a page boundary) and the
re-asserted anchor for the still-open page `046-10b` (the same shape is
pervasive in SBCK 大清一統志 KR2k0009 — 1,507 instances across 178 of 210
files at census, every one the OPEN page; a closed page's repeat stays a
loud ParseError). KR2a0001 史記 is BASEEDITION `tls` (the TLS re-edition,
cf. row 106): files are SECTION ordinals, not juan (`_100` 紀, `_201`–
`_210` 表, `_300` 書 …; `_201` here) with `#+PROPERTY: JUAN` diverging
from the suffix — anchor NNN still equals the file suffix, all-`a` sides,
and `_100` (not fixtured, 538 KB) carries 1,894 `# src:` SHIJI refs.
KR2g0007 杜工部年譜 is a small whole WYG 傳記 repo.

## KR-Catalog slices (upstream HEAD 927469cd1543dfeed828151090b0bdd366b11ef4)

`KR-Catalog/README.org` is whole. Each `KR-Catalog/KR/KR<sub>.txt` is the
real file's org header (through the `**` subclass heading) plus the
complete `***` entry block(s) for: KR1a0170, KR1b0049 (KR1b), KR1h0004,
KR2a0001 + KR2a0038 + KR2a0039 (KR2a), KR2g0007, KR3a0001, KR3g0023,
KR3i0042, KR4d0525, KR4j0026. **KR1b0049 古文尚書寃詞 and KR2a0039 清史稿
are real catalog ids with NO github repo** (61 wave-1 + 2 wave-2 such ids
censused 2026-07-20; KR2's other is KR2d0020) — the fetch tests'
recorded-absent case. The inverse shape is KR2-only: **4 un-catalogued KR2
repos** (KR2b0041, KR2p0015/0021/0024 — the whole KR2p 出土簡帛 subclass,
e.g. Mawangdui 合陰陽釋文, has repos but no catalog file) sit outside the
catalog-driven wave scope.

## License (org description, verbatim, retrieved 2026-07-20)

> Comprehensive collection of premodern Chinese texts. Licensed as CC BY
> SA 4.0.

Sampled repos carry no LICENSE file (github license field null).
Corroboration, ytenx `DATA_LICENSE.md`: "Kanseki Repository material
marked as CC BY-SA must be used under the applicable Creative Commons
Attribution-ShareAlike terms". Confirmation email to Christian Wittern
(№25) sent, non-blocking → `attribution`.
