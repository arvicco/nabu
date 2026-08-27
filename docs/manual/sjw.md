# 승정원일기 (sjw) — acquisition

The Daily Records of the Royal Secretariat of Joseon — NIKH bulk XML
on data.go.kr, the library's largest single source by characters. The
query website (sjw.history.go.kr) is all-rights-reserved; **the
data.go.kr dump is the sanctioned channel**.

**Normally no human steps are needed**: `bin/nabu sync sjw` resolves
the portal's current download URL and fetches unattended. The first
acquisition (2026-08-18) was a hand download in a browser; this
document keeps that route replayable (and is the fallback if the
portal's page shape changes).

## Manual route

1. Open <https://www.data.go.kr/data/15064218/fileData.do>
   (dataset 교육부 국사편찬위원회_승정원일기 정보).
2. **License capture:** read the 이용허락범위 field and record its
   exact wording + the date. It reads **이용허락범위 제한 없음** (the
   KOGL framework) — verified 2026-08-18, re-verified 2026-08-27.
3. Click the **다운로드** button; no login is required. This is a
   large download (~418 MB zip) — give it time.

Route re-verified 2026-08-27: page live, download button present,
license field as above.

## Expected files

One zip, ~418 MB / 2.44 GB unpacked: 298 reign-year XML members
(`2nd_K00.sjw.y.xml` …, members 0.5–19 MB) — the 2022-11-03 dump.
Hanmun 원문 only; the modern Korean translation layer is NOT in the
dump and is never acquired.

## Where it goes

No ManualDrop contract — the adapter fetches into `canonical/sjw/`
itself. A hand-downloaded zip goes to the repo's gitignored intake
folder (`.docs/inbox/`) as evidence/backup; the sanctioned ingest is
`bin/nabu sync sjw`.

## Refresh

The dataset page is the stable address (the terminal `atchFileId`
bumps on every upstream replacement). Re-sync when the portal shows a
newer registration than the 2022-11-03 snapshot.
