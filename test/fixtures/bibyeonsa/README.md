# Bibyeonsa fixtures (P78-3 — the goryeosa family, third sibling)

Real upstream samples of the **비변사등록 원문** (Records of the Border
Defense Command — the daily register of later Joseon's de-facto supreme
state council, surviving books 1617–1892, original hanmun), NIKH bulk
XML via data.go.kr (CLAUDE.md fixture rules). Both members are
**trimmed** — interior sibling level nodes removed by whole-line cuts,
every kept byte verbatim, structure intact (no member in the zip is
small: 288 KB–1.4 MB).

- **Upstream:** data.go.kr dataset **15053636** (one zip, 31 MB /
  180 MB unpacked: 273 members `bb_001.xml`..`bb_273.xml` — no `_000` —
  + `history.dtd`). Download is the three-step resolution
  `Nabu::DataGoKrFetch` implements.
- **Retrieved:** 2026-08-18 (whole zip; members below unpacked from
  it). In-zip file dates 2022-10-26.
- **License:** 이용허락범위 제한 없음 per the dataset page
  (https://www.data.go.kr/data/15053636/fileData.do, verified
  2026-08-18); owner ruling D47-a → `attribution`, credit
  국사편찬위원회.

## Upstream format reality (what these members preserve)

Korean History Database unified DTD **ver 1.4 (2020-07-30**, identical
bytes to the goryeosa zip's copy), shipped as `history.dtd` IN the zip.
No `2nd_` filename prefix. One member per 책 (register book), rooted at
**level1** — EXCEPT `bb_001`, the zip's ONE `<item>`-rooted member: its
single level1 carries NIKH's 1959 print-edition front (`publication`
with `dateIssued date="1959-04-05"`, library `holdings`, and the
modern-Korean 서문 preface as a front `introduction` — front apparatus,
never a passage). level2 = year with `value`/`간지`/`왕명`/`재위년도`
**attributes** (raw Korean attribute names; in `bb_001` the year
sections INTERLEAVE 1617 and 1616 non-monotonically), level3 = month,
level4 = the leaf entries: 좌목 attendance rosters (`<table>` markup,
flattened to text) and the daily memoranda/계 entries. The single
`dateOccured` per entry carries a machine date attr and **NO type
attribute at all** (the family's 서기 line does not exist here); book
(root) fronts are never dated → documents claim no date.

## The members

| File | Why |
|---|---|
| `bb_001.xml` | **trimmed** (9,301 → 356 lines: level2 siblings 003–007 removed) — the ONE `<item>`-rooted member: the 1959 print-edition front with the 서문 introduction, then TWO year sections in upstream's own non-monotonic order (1617 then 1616), one leaf each (a 좌목 roster table; a 계 memorandum dated 1616-12-30L0) |
| `bb_054.xml` | **trimmed** (3,334 → 224 lines: level4 siblings 0030 onward and level3 months 02–05 removed) — 54책 (숙종 30년 = 1704): the level1-rooted norm, level2 year attrs (`value="1704" 간지="갑신" 왕명="숙종" 재위년도="30"`), a 좌목 roster + the 비망기 entry |
| `history.dtd` | the DTD verbatim (ver 1.4, byte-identical to the goryeosa zip's) — the family's spec travels with the fixture |
