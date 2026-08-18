# Goryeosa-jeoryo fixtures (P78-3 — the goryeosa family, second sibling)

Real upstream samples of the **고려사절요 원문** (Essentials of Goryeo
History, 1452, 김종서 et al. — the chronological digest compiled one
year after the goryeosa, original hanmun), NIKH bulk XML via data.go.kr
(CLAUDE.md fixture rules). `kj_000.xml` is **byte-verbatim**;
`kj_033.xml` is **trimmed** — interior sibling level nodes removed by
whole-line cuts, every kept byte verbatim, structure intact.

- **Upstream:** data.go.kr dataset **15115521** (one zip, 2.2 MB /
  22 MB unpacked: 36 members `kj_000.xml`..`kj_035.xml` +
  `history.dtd` + ONE stray `.jpg` with a CP949-mojibake name — the
  census counts it loudly, never parses it). Download is the three-step
  resolution `Nabu::DataGoKrFetch` implements.
- **Retrieved:** 2026-08-18 (whole zip; members below unpacked from
  it). In-zip file dates 2023-04-23.
- **License:** 이용허락범위 제한 없음 per the dataset page
  (https://www.data.go.kr/data/15115521/fileData.do, verified
  2026-08-18); owner ruling D47-a → `attribution`, credit
  국사편찬위원회.

## Upstream format reality (what these members preserve)

Korean History Database unified DTD — a comment-reflowed **ver 1.4**
variant (31,459 bytes, in-zip date 2023-05-18; same declarations as the
goryeosa/bibyeonsa copy, comments rewrapped and contributor emails
scrubbed) — shipped as `history.dtd` IN the zip. No `2nd_` filename
prefix. Members root at **level1** (one 卷 per file: level2 reign →
level3 year → level4 month → level5 article), EXCEPT `kj_000` — the
zip's ONE `<item>`-rooted member: four sibling level1 front-matter
sections with `$`-carrying ids (`kj_$s01`..`kj_$s04`). **NO 서기
calendar line exists**: article fronts lead with the lunar 음 machine
date (`date="1388-01-01L0"`), then 양 (solar), 일간지 (day cyclical,
text only) and 원문 (the original date phrase, text only); the level3
YEAR front carries a bare machine year (`date="1388"`, the cyclical
year name as text) — two levels below the root, so documents claim no
date. Root fronts carry `fileDesc` build provenance (2015/2019
database-construction credits) and a `coveragePeriod` prose line
instead. Text paragraphs carry `<index>` refs and `<annotation
type="소자쌍행">` interlinear notes whose noteTitle text flattens
inline.

## The members

| File | Why |
|---|---|
| `kj_000.xml` | **byte-verbatim** — the ONE `<item>`-rooted member: 進高麗史節要箋, 凡例, 修史官, 目錄 as four sibling level1 leaves; no dates |
| `kj_033.xml` | **trimmed** (3,271 → 208 lines: level5 siblings 0050–0090, the second level4 (2월) onward, removed) — 卷33 (辛禑四, 우왕 14년 = 1388): full level1→2→3→4→5 chain, four 음-dated articles incl. the 위화도 회군 year's opening purge, the level3 bare-year front (`date="1388"`) kept |
| `history.dtd` | the DTD verbatim (the 2023 comment-reflowed ver 1.4 copy) — the family's spec travels with the fixture |
