# Sillok fixtures (P78-1 — the korean axis's anchor)

Real upstream samples of the **조선왕조실록 원문** (Veritable Records of
the Joseon Dynasty, original hanmun), NIKH bulk XML via data.go.kr
(CLAUDE.md fixture rules). Every member is **byte-verbatim** upstream;
only the member SET was selected — no trimming inside files.

- **Upstream:** data.go.kr dataset **15053647**
  (Taejo–Cheoljong, 137 MB zip / 674 files incl. `history.dtd`) +
  **15053646** (Gojong/Sunjong, 9.1 MB / 66 MB unpacked). Download is
  the three-step resolution `Nabu::DataGoKrFetch` implements
  (page → JSON → `/cmm/cmm/fileDownload.do?atchFileId=…` — the
  atchFileId bumps on upstream file replacement; see
  `.docs/p78-plan.md` §Acquisition for the 2026-08-18 resolved keys).
- **Retrieved:** 2026-08-18 (both whole zips; members below unpacked
  unmodified). In-zip file dates 2022-10-27/31.
- **License:** 이용허락범위 제한 없음 per both dataset pages
  (useScopeCode COEX07 in the resolution JSON, verified 2026-08-18);
  owner ruling D47-a → `attribution`, credit 국사편찬위원회. The
  query-only website (sillok.history.go.kr) is ARR — the dump is the
  sanctioned channel.

## Upstream format reality (what these members preserve)

Korean History Database unified DTD ver 1.3 (2015-11-30), shipped as
`history.dtd` IN the zip. Volume files root at **level1** (the `_000`
whole-reign preface members — root id is the bare reign code, only the
FILENAME disambiguates) or **level2** (per reign-year), nesting level3
(month) → level4 (day) → level5 (기사 article: modern-Korean editorial
mainTitle, docNo, 원본/태백산사고본/국편영인본 sources with page refs,
subjectClass rows). Dates carry up to SEVEN parallel calendars per
front (서기 with machine attr `date="1928-05-03L0"` — L = lunar flag —
간지/재위연도/개국연호/중국연호/단기/일본연호). Text paragraphs carry
`<index>` named-entity refs (persons `ref="M_…"`, places, era names)
and `<annotation type="원주">` interlinear notes with 【】 marks.

## The members

| File | Why |
|---|---|
| `2nd_wzc_121.xml` | the ANCHOR: level2 root, full level3→4→5 chain, two dated 기사 articles (Sunjong appendix year 21 = 1928 — the post-annexation volume, so the 일본연호 Shōwa line is FILLED and 개국연호 is empty; 간지 reads 陽曆, the solar-calendar marker) |
| `2nd_waa_200.xml` | Taejo appendix (附錄): level3 leaves, archive-source citations, NO dates — the honest-absence case |
| `2nd_wqa_000.xml` | Hyojong 總序: **level1 root** (the root-variance witness), single level2 leaf |
| `history.dtd` | the DTD verbatim — the family's spec travels with the fixture |
