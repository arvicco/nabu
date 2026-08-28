# 고려사절요 (goryeosa-jeoryo) — acquisition

The Essentials of Goryeo History (1452; the chronological digest
compiled one year after the 고려사) in the original hanmun — NIKH
bulk XML on data.go.kr.

**Normally no human steps are needed**: `bin/nabu sync
goryeosa-jeoryo` resolves the portal's current download URL and
fetches unattended. The first acquisition (2026-08-18) was a hand
download in a browser; this document keeps that route replayable.

## Manual route

1. Open <https://www.data.go.kr/data/15115521/fileData.do>
   (dataset 교육부 국사편찬위원회_한국사데이터베이스 정보_고려사절요 원문).
2. **License capture — drift observed on this dataset, read
   carefully:** the 이용허락범위 field read **이용허락범위 제한 없음**
   when verified 2026-08-18, but as of 2026-08-27 the page shows
   **공공저작물 : 출처표시 (제 1유형)** — KOGL Type 1, attribution.
   Both are attribution-class grants and consistent with the source's
   ruled `license_class: attribution` (credit the institute), but
   capture whatever the page states at YOUR acquisition time,
   verbatim, with the date. If it ever names a KOGL type carrying
   non-commercial or no-derivatives conditions (types 2–4), stop and
   flag it before ingesting.
3. Click the **다운로드** button; no login is required.

Route re-verified 2026-08-27: page live, download button present,
license field as in step 2.

## Expected files

One zip, ~2.2 MB / ~22 MB unpacked: 36 XML members `kj_000`–`kj_035`
+ `history.dtd`, plus one stray `.jpg` with a CP949-mojibake name
(known upstream quirk — harmless, never parsed). Hanmun 원문 only —
the modern Korean translation layer is NOT in the dump.

## Where it goes

No ManualDrop contract — the adapter fetches into
`canonical/goryeosa-jeoryo/` itself. A hand-downloaded zip goes to
the repo's gitignored intake folder (`.docs/inbox/`) as
evidence/backup; the sanctioned ingest is `bin/nabu sync
goryeosa-jeoryo`.

## Refresh

The dataset page is the stable address (the terminal `atchFileId`
bumps on upstream replacement). The snapshot in the dataset title was
20230518 at acquisition time; re-sync when the portal shows a newer
registration.
