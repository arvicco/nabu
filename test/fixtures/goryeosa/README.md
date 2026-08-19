# Goryeosa fixtures (P78-3 — the goryeosa family, first sibling)

Real upstream samples of the **고려사 원문** (History of Goryeo, 1451,
정인지 et al. — the official Joseon-compiled history of the Goryeo
dynasty, original hanmun), NIKH bulk XML via data.go.kr (CLAUDE.md
fixture rules). `kr_000.xml` is **byte-verbatim**; `kr_069.xml` and
`kr_118.xml` are **trimmed** — interior sibling level nodes removed by
whole-line cuts, every kept byte verbatim, structure intact (see the
table).

- **Upstream:** data.go.kr dataset **15053637** (one zip, 5.3 MB /
  50 MB unpacked: 138 members `kr_000.xml`..`kr_137.xml` +
  `history.dtd`). Download is the three-step resolution
  `Nabu::DataGoKrFetch` implements (the atchFileId bumps on upstream
  file replacement).
- **Retrieved:** 2026-08-18 (whole zip; members below unpacked from
  it). In-zip file dates 2022-10-26.
- **License:** 이용허락범위 제한 없음 per the dataset page
  (https://www.data.go.kr/data/15053637/fileData.do, verified
  2026-08-18); owner ruling D47-a → `attribution`, credit
  국사편찬위원회.

## Upstream format reality (what these members preserve)

Korean History Database unified DTD — **ver 1.4 (2020-07-30)** here,
not sillok's 1.3 — shipped as `history.dtd` IN the zip. Member names
carry **no `2nd_` prefix** (unlike sillok). Members root at **level1**
(one 卷 per file across the 世家/志/表/列傳 divisions), EXCEPT
`kr_000` — the zip's ONE `<item>`-rooted member (DOCTYPE item): four
SIBLING level1 front-matter sections with `$`-carrying ids
(`kr_$s01`..`kr_$s04`). Leaves sit at level4 or level5 by division.
**NO 서기 calendar line exists anywhere in the zip**: dated fronts lead
with the lunar 음 machine date (`date="1048-02-16L0"`, L = lunar flag),
the solar 양 following; 志/世家 carry them at leaf grain only, 列傳
carries none. Volume (root) fronts are never dated → documents claim no
date. Text paragraphs carry `<index>` named-entity refs
(persons/places/offices/book titles) and kyudb.snu.ac.kr original-image
`<link>` elements.

## The members

| File | Why |
|---|---|
| `kr_000.xml` | **byte-verbatim** — the ONE `<item>`-rooted member: 進高麗史箋, 高麗世系 (×2 sections), 편찬 범례 as four sibling level1 trees; `$`-carrying section ids; 13 leaves, no dates |
| `kr_069.xml` | **trimmed** (523 → 114 lines: level5 siblings 0030–0050 and 0070, and the whole second level4, removed) — 志 卷第二十三 (禮 11): level1→2→3→4→5 chain, two undated ritual prescriptions + one 음/양-dated entry (문종 2년 = 1048) |
| `kr_118.xml` | **trimmed** (276 → 127 lines: level4 siblings 0030–0070 removed) — 列傳 卷第三十一 (조준): level4 leaves, NO dates anywhere — the honest-absence case |
| `history.dtd` | the DTD verbatim (ver 1.4, 2020-07-30) — the family's spec travels with the fixture |
