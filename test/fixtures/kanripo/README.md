# Kanripo fixture — Kanseki Repository, waves 1–3 + recovery exemplars (P33-0, P33-1, P37-1, P43-r2)

Seventeen real texts (2–4 per wave class KR1/KR2/KR3/KR4, five KR5)
fetched individually from github.com/kanripo — one repo per text — plus
trimmed slices of the KR-Catalog discovery index. The directory mirrors
the canonical workdir the adapter fetches: `KR-Catalog/` beside per-text
dirs named by KR id.

- **Retrieved:** 2026-07-20, via `git clone --depth 1
  https://github.com/kanripo/<name>` (master — Kanripo keeps alternate
  editions as git *branches*; master is the BASEEDITION working text).
  The two P43-r2 dirs (KR1a0149, KR2f0037) were instead extracted from
  the local canonical snapshot 2026-07-23 (byte-verbatim whole files;
  canonical HEAD shas in the table) — quarantined texts have no
  fresh-clone parse to eyeball, the canonical bytes ARE the evidence.
- **Text files are byte-verbatim upstream wholes.** Two repos are trimmed
  at the *repo* grain (a subset of their per-juan files, each file whole);
  the catalog files are byte-verbatim *slices* (org header + the complete
  entry blocks for the fixture ids).

## The texts (upstream HEAD sha at retrieval)

| dir | text | class | edition | files | trim | sha |
|---|---|---|---|---|---|---|
| KR1a0149 | 易翼說 | KR1 | WYG | Readme + juan 000 + 001 of 9 | repo-trim: 7 juan files omitted | 12d3f6b87f340efbccfc694146ad76a20bb66d7a (canonical HEAD) |
| KR1a0170 | 易緯坤靈圖 | KR1 | WYG | whole repo (000 header-only, 001, Readme) | none | 5067a9aa9992dd8328917c9f60598e6b6cd12db6 |
| KR1h0004 | 論語 | KR1 | CHANT | Readme + juan 001 + 020 of 20 | repo-trim: 18 juan files omitted | 89b65734d4386e2478179c77741a968bfc627abb |
| KR2a0001 | 史記 | KR2 | tls | Readme + section 201 of 14 section files | repo-trim: 13 section files omitted | 1c19dc6fa970b1c530fced9e8e3697d19163c26c |
| KR2a0038 | 明史 | KR2 | WYG | Readme + juan 046 of 548 | repo-trim: 547 juan files omitted | eccd6fe93126bde61b837240e6142e1343c22639 |
| KR2f0037 | 三朝名臣言行錄 | KR2 | SBCK | Readme + juan 042 of 56 | repo-trim: 55 juan files omitted | 5310198f9360d13ac25a9476a68829d0c8d5c85d (canonical HEAD) |
| KR2g0007 | 杜工部年譜 | KR2 | WYG | whole repo (000, 001, Readme) | none | c5bdb391e82298514d20d679e23feebdf309a4d9 |
| KR3a0001 | 孔子家語 | KR3 | SBCK | Readme + juan 001 of 11 | repo-trim: 000, 002–011 omitted | 47dc84abb7d01b95480800bff2e53be7a3440f6a |
| KR3g0023 | 青囊奧語 | KR3 | WYG | whole repo (single 000 file) | none | 2b8bb8b4076807e5f9c9af5194c83ed584c9da71 |
| KR3i0042 | 菌譜 | KR3 | WYG | whole repo | none | 6c2e78f41d6432b7f55c84bfd752413eb6f2be50 |
| KR4d0525 | 鯨背吟集 | KR4 | WYG | whole repo | none | 3556dec68237d96bc6de65357b478b2c8bacea98 |
| KR4j0026 | 無住詞 | KR4 | WYG | whole repo | none | e858eb7c47573893df92c59d4f166b66e2544c81 |
| KR5a0001 | 元始無量度人上品妙經 | KR5 | HFL + witness CK-KZ | Readme + juan 000–003 of 62 | repo-trim: 58 juan files omitted | 76ae4bb351cbf1beb0f44b60bd7f587123322352 |
| KR5a0004 | 元始天尊説無上内祕眞藏經 | KR5 | HFL + witness CK-KZ | Readme + juan 006 + 007 of 11 | repo-trim: 9 juan files omitted (incl. the stray-text `_000`, below) | 487e4634f9d812fbfaf4adf5541d3d3adb86297c |
| KR5c0091 | 道德眞經註 | KR5 | HFL + witness CK-KZ | Readme + juan 001 of 5 | repo-trim: 4 juan files omitted | eea2723ca2d4b35730021de0ab84ed3f47b1c5b7 |
| KR5g0001 | 大慧靜慈妙樂天尊說福德五聖經 | KR5 | HFL (plain) | whole repo (single 000 file) | none | 1b2c20b7e0b23cd6a444f79f2608d10311b2e75e |
| KR5i0030 | 唱道真言 | KR5 | CK-KZ (= witness) | Readme + juan 001 + 002 of 4 | repo-trim: 2 juan files omitted | d0d59038dee74e517bf9ac5735766cd3858156b7 |

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

The five KR5 texts (P37-1, retrieved 2026-07-20) attest the Daozang wave-3
census — fourteen KR5 repos probed whole, ~459 DZJY overlay files located
org-wide by code search. KR5g0001 is a PLAIN-mandoku KR5 repo (parses at
the leaf-side grain; carries the new `DZID`/`SOURCE` header properties —
DZ1192 — and the `mode: mandoku-view;` semicolon mode-line variant). The
other four are DZJY WITNESS-OVERLAY repos (`WITNESS CK-KZ` 重刊道藏輯要):
the file transcribes the witness's print columns, the witness's own `<pb:>`
anchors (page component `<juan>p<leaf><side>`, never the plain `-` form)
are the citable page structure, `<md:>` milestones mark where the BASE
edition's pages fall inside the witness text, and `@fw` lines are running
headers. All three censused anchor arrangements are attested: KR5a0001
度人經 `<pb:CK-KZ_JY001_01p001a>` (witness siglum + DZJY volume; also @fw
with embedded ¶/`<md:>`, the base edition's pilcrow-only front-matter pages
000-001a–000-002b before the first witness anchor, headings carrying ¶ and
milestones, empty witness pages as adjacent anchors, and the `LASTPB`
header property echoing the file's last milestone); KR5a0004
`<pb:KR5a0004_CK-KZ_02p048a>` (text id + witness — juan 006+007 pin the
CROSS-FILE page carry: page 02p048a opens in `_006` and its last column is
`_007`'s whole body; the omitted REAL `_000` is a header block plus one
stray anchor-less 八 — reproduced byte-verbatim in the parser test; since
P43-r2 it mints the `000:front` front-matter page instead of quarantining); KR5i0030 `<pb:CK-KZ_KR5i0030_01p001a>` (witness
siglum + text id as container; `BASEEDITION CK-KZ` IS the witness, no
`<md:>`, no `JUAN` property, `#-*- mode: org; -*-` mode line, and the
`#+TITLE:唱道真言 Changdao Zhenyan` no-space/romanized title variant).
KR5c0091 道德眞經註 pins the md-edition lie: header `BASEEDITION HFL`, but
every milestone says `WYG` — the md edition is recorded verbatim, never
validated. Witness (juan, leaf-side) pairs are unique per repo in every
probe; KR5c0067 (probed, not fixtured) shows sorted file order need not
follow witness page order (`_000` front matter at witness juan 03).

The two P43-r2 texts (extracted from the local canonical snapshot
2026-07-23) attest the D42-c quarantine-recovery census (owner-ruled at
the P42 gate: 133 quarantined texts, 75 duplicate-anchor + 26
text-before-first-anchor recoverable). KR2f0037 三朝名臣言行錄 juan 042
is the duplicate-anchor exemplar: upstream concatenated TWO source
fascicles into the one juan file — a fresh `#+PROPERTY: FILE` header
block mid-file names the second print source (SB02n0032-093
三朝名臣言行錄卷九之三, then SB02n0033-082 五朝名臣言行錄卷八之二) — and
each fascicle restarts its own leaf-side pagination at 1a, so the second
sweep re-opens closed page ids (it also re-asserts its own open pages,
9b and 12b, the P33-1 no-op shape against a disambiguated key). Parsed:
53 pages, the second sweep keyed `042:<page>#2`. KR1a0149 易翼說 is the
text-before-first-anchor exemplar: juan 001 opens with seven prefatory
print lines before `<pb:KR1a0149_WYG_001-1a>` (the seventh un-pilcrowed —
the print line runs across the page seam); parsed: 76 pages, the
prefatory text on the synthetic `001:front` page. `_000` is a real
anchor-only juan-0 file (header + `<pb:…_000-1a>`, no text): zero
passages.

## KR-Catalog slices (upstream HEAD 927469cd1543dfeed828151090b0bdd366b11ef4)

`KR-Catalog/README.org` is whole. Each `KR-Catalog/KR/KR<sub>.txt` is the
real file's org header (through the `**` subclass heading, including any
`#+LINK`/comment lines before the first entry) plus the complete `***`
entry block(s) for: KR1a0170, KR1b0049 (KR1b), KR1h0004, KR2a0001 +
KR2a0038 + KR2a0039 (KR2a), KR2g0007, KR3a0001, KR3g0023, KR3i0042,
KR4d0525, KR4j0026, KR5a0001 + KR5a0004 (KR5a — KR5a0001's block carries
the whole DZJY 目次 plus the 版本 witness listing naming `DZJY:JY001`, the
volume id in its witness anchors), KR5c0091, KR5g0001, KR5i0030; the
KR-Catalog HEAD is unchanged since P33-0. **KR1b0049 古文尚書寃詞 and KR2a0039 清史稿
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
