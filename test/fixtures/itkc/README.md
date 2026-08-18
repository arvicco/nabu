# ITKC fixtures (P78-7 — the open-licensed classical slice)

Real upstream samples of the **한국고전종합DB** export XML,
한국고전번역원 via data.go.kr (CLAUDE.md fixture rules). Two witnessed
works, both families:

- **Upstream:** data.go.kr datasets **15022432** (고운당필기 — the GP
  item family; NB the dataset title says "고전원문" and the fascicle
  files say "한국문집총간 교감표점서": upstream's own labels
  disagree across files of ONE work) and **15141442** (국조보감 — GO
  family, 2025-01-22 registration). One zip per work: a suffix-less
  서지 SIDECAR + one file per 권차 fascicle. Download via the
  `Nabu::DataGoKrFetch` three-step resolution.
- **Retrieved:** 2026-08-18 (both whole zips). In-zip file dates
  2024-08-30.
- **License:** 이용허락범위 제한 없음 per both dataset pages (KOGL
  framework); owner ruling D47-a → `attribution`, credit
  한국고전번역원. The itkc.or.kr site itself is ARR — ONLY the portal
  datasets carry the grant (the P78-7 scout's channel map).

## Upstream format reality (what these members preserve)

Korean-tag XML: 아이템 → 레벨1 (서지) → 레벨2 (권차) → the article
unit marked `type="최종정보"` — at 레벨3 in GP works, at 레벨4 in GO
(whose 레벨3 is a 문체 genre section): **the marker, not the level
name, is the grain**. Sidecars carry hanja/hangul title pairs, the
author with 생년/몰년 machine years, and the **원문간행년** original
print year (서기년 attr — 1780 / 1895 here; the 간행기간 2020s years
are the modern edition). `언어` says "coc" — ITKC-internal, NOT ISO
639-3 (which assigns coc to Cocopa); the text is hanmun. Article text
carries 고유명사 proper-noun tags and 페이지 markers; 연계정보 points
into ITKC's own 번역문 translation layer by id.

## The members

| File | Why |
|---|---|
| `ITKC_GP_1550A.xml` | 고운당필기 sidecar — trimmed to the 서지 메타정보 (the ~95 KB 해설정보 commentary removed; every kept byte verbatim) |
| `ITKC_GP_1550A_0010.xml` | 卷一, trimmed to the first two 레벨3 articles (圖書集成 with the full apparatus) |
| `ITKC_GO_1295A.xml` | 국조보감 sidecar — **whole, byte-verbatim** (2.4 KB) |
| `ITKC_GO_1295A_0010.xml` | 首卷, trimmed to the first two 레벨3 genre sections (레벨4 최종정보 articles — the GO nesting witness) |
