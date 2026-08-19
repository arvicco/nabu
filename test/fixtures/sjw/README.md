# SJW fixtures (P78-2 — the scale test)

Real upstream samples of the **승정원일기** (Daily Records of the Royal
Secretariat of Joseon), NIKH bulk XML via data.go.kr (CLAUDE.md fixture
rules). Both members are **hand-trimmed slices of real files** — the
smallest whole members run 0.5–19 MB, so each keeps its level2 front
verbatim plus the FIRST month → first day → first three articles, with
every kept byte upstream-verbatim (interior sibling level nodes
removed, structure intact; the trim recipe is in the manifest).

- **Upstream:** data.go.kr dataset **15064218**
  (교육부 국사편찬위원회_승정원일기 정보_20221103): one zip, 298
  members / 2.44 GB unpacked, members 0.5–19 MB, `history.dtd`
  shipped in the zip. Download via the `Nabu::DataGoKrFetch`
  three-step resolution (see `.docs/p78-plan.md` §Acquisition).
- **Retrieved:** 2026-08-18 (whole zip; members below extracted and
  trimmed). In-zip file dates 2022-10-27.
- **License:** 이용허락범위 제한 없음 (useScopeCode COEX07 in the
  resolution JSON — the NIKH family's uniform grant); owner ruling
  D47-a → `attribution`, credit 국사편찬위원회. The query-only website
  (sjw.history.go.kr) is ARR — the dump is the sanctioned channel.

## Upstream format reality (what these slices preserve)

Same Korean History Database unified DTD ver 1.3 as sillok, with the
sjw-specific apparatus: level2 roots carry `type="연"` (year) and ids
`SJW-<reign letter><year>` ("SJW-K00" = Gojong accession year); level3
`type="월"`, level4 `type="일"` days whose fronts carry the WEATHER
record (`<description><weather>晴</weather>`) and 원본/탈초본 source
page numbers; level5 articles (`type="좌목"` duty rosters + untitled
기사, ids `SJW-K00120130-00000` shape) with inline
`<explanation type="근무현황">` duty-status glosses and `<index>`
named-entity refs in the text.

## The members

| File | Why |
|---|---|
| `2nd_K00.sjw.y.xml` | Gojong accession year (1863) — the 座目 roster with 근무현황 glosses + two 기사; weather 晴 on the day front |
| `2nd_L04.sjw.y.xml` | Sunjong year 4 (1910, the dynasty's last) — same shape at the far end of the run; 일본연호 明治 43 in the year front |
| `history.dtd` | the shared family DTD verbatim (byte-identical to the sillok fixture's copy except the in-zip date stamp) |
