# ITKC 고전원문 (itkc) — acquisition

The open-licensed slice of the 한국고전종합DB: classical hanmun
originals published by the Institute for the Translation of Korean
Classics (한국고전번역원) as per-work file datasets on data.go.kr.
The ITKC website itself (db.itkc.or.kr) is all-rights-reserved and
its OpenAPI serves search snippets, not text — **the data.go.kr
datasets are the only ingestible channel**.

**Normally no human steps are needed**: `bin/nabu sync itkc` resolves
each registered dataset's current download URL and fetches unattended.
The first acquisitions (2026-08-18) were hand downloads in a browser;
this document keeps the route replayable — and documents the formal
request path for works not yet on the portal.

## Manual route (per dataset)

1. Open `https://www.data.go.kr/data/<pk>/fileData.do` for the
   dataset (the seventeen registered pks are the adapter's `DATASETS`
   table, listed below).
2. **License capture:** read the 이용허락범위 field and record its
   exact wording + the date. Every registered dataset reads
   **이용허락범위 제한 없음** (the KOGL framework) — verified
   2026-08-18; spot re-verified 2026-08-27 on 15141442 (국조보감) and
   15022432 (고전원문).
3. Click the **다운로드** button; no login is required.

The seventeen registered datasets (pk → work):

| pk | work |
|---|---|
| 15022432 | 고운당필기 |
| 15141442 | 국조보감 |
| 15141448 | 임하필기 |
| 15141450 | 전율통보 |
| 15141472 | 신증동국여지승람 |
| 15141473 | 동국여지지 |
| 15141474 | 여지도서 |
| 15141476 | 여도비지 |
| 15141477 | 대동지지 |
| 15141479 | 여재촬요 |
| 15141452 | 열성지장통기 |
| 15141458 | 세자행적 |
| 15141460 | 종반행적 |
| 15141464 | 국조인물고 |
| 15141467 | 인물고 |
| 15141469 | 영남인물고 |
| 15141470 | 동현주의 |

## Expected files

One zip per dataset. Each unpacks to per-fascicle XML files
(`ITKC_<XX>_<work id>_<NNNN>.xml` — the `_NNNN` 권차 suffix marks a
fascicle; the suffix-less sibling is the work's 서지 bibliographic
sidecar) — e.g. the 국조보감 zip is ~1.7 MB. Encoding UTF-8.

## The rest of the corpus — the request path

The portal slice is ~7% of the GO family's 257 works. ITKC
demonstrably publishes in exactly this format on request (the
2025-01-22 dataset batch): file a 공공데이터 제공신청 (public-data
provision request) through data.go.kr for a work you need. New
registrations arrive in waves — re-run the portal search for
한국고전번역원 datasets periodically and append new pks to the
adapter's `DATASETS` table.

## Where it goes

No ManualDrop contract — the adapter fetches each dataset into its
own pk-named subdir of `canonical/itkc/` itself. Hand-downloaded zips
go to the repo's gitignored intake folder (`.docs/inbox/`) as
evidence/backup; the sanctioned ingest is `bin/nabu sync itkc`.

## Refresh

Dataset pages are the stable addresses (the terminal `atchFileId`
bumps on upstream replacement). Re-sync when a page shows a newer
registration date; watch the portal for new ITKC dataset waves.
