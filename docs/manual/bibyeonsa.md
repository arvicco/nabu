# 비변사등록 (bibyeonsa) — acquisition

The Records of the Border Defense Command (비변사, the de-facto
supreme state council of later Joseon; surviving registers 1617–1892)
in the original hanmun — NIKH bulk XML on data.go.kr.

**Normally no human steps are needed**: `bin/nabu sync bibyeonsa`
resolves the portal's current download URL and fetches unattended.
The first acquisition (2026-08-18) was a hand download in a browser;
this document keeps that route replayable.

## Manual route

1. Open <https://www.data.go.kr/data/15053636/fileData.do>
   (dataset 교육부 국사편찬위원회_한국사데이터베이스 정보_비변사등록 원문).
2. **License capture:** read the 이용허락범위 field and record its
   exact wording + the date. It reads **이용허락범위 제한 없음** (the
   KOGL framework) — verified 2026-08-18, re-verified 2026-08-27.
3. Click the **다운로드** button (다운로드(바로가기)); no login is
   required.

Route re-verified 2026-08-27: page live, download button present,
license field as above.

## Expected files

One zip, ~31 MB / ~180 MB unpacked: 273 XML members `bb_001`–`bb_273`
(no `_000`) + `history.dtd` ver 1.4. Hanmun 원문 only — the modern
Korean translation layer is NOT in the dump.

## Where it goes

No ManualDrop contract — the adapter fetches into
`canonical/bibyeonsa/` itself. A hand-downloaded zip goes to the
repo's gitignored intake folder (`.docs/inbox/`) as evidence/backup;
the sanctioned ingest is `bin/nabu sync bibyeonsa`.

## Refresh

The dataset page is the stable address (the terminal `atchFileId`
bumps on upstream replacement). Re-sync when the portal shows a newer
registration than the 2022-11-03 snapshot.
