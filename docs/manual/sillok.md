# 조선왕조실록 (sillok) — acquisition

The Veritable Records of the Joseon Dynasty in the original hanmun —
NIKH (국사편찬위원회) bulk XML published on the Korean open-data
portal data.go.kr as two file datasets. The query website
(sillok.history.go.kr) is all-rights-reserved; **the data.go.kr dump
is the sanctioned channel**.

**Normally no human steps are needed**: `bin/nabu sync sillok`
resolves the portal's current download URL per dataset and fetches
unattended (no login, no captcha — the portal serves file datasets
from a public endpoint). The first acquisition (2026-08-18) was
performed by hand in a browser while that automation was being built;
this document keeps the browser route replayable — it is also the
fallback if the portal's page shape changes or its captcha lane (seen
in the portal's JS, never triggered live) ever arms.

## Manual route

Two datasets, one zip each:

1. **Taejo–Cheoljong (the 25 dynastic reigns):** open
   <https://www.data.go.kr/data/15053647/fileData.do>
   (dataset 교육부 국사편찬위원회_조선왕조실록 정보_실록원문).
2. **Gojong/Sunjong (the two colonial-era supplements):** open
   <https://www.data.go.kr/data/15053646/fileData.do>
   (dataset …_고순종실록 원문).
3. **License capture:** on each page, read the 이용허락범위 field in
   the metadata table and record its exact wording + the date. Both
   read **이용허락범위 제한 없음** ("no restriction on scope of use",
   the KOGL framework) as verified 2026-07-26, 2026-08-18 and
   re-verified 2026-08-27. If the field ever names a KOGL type
   instead, capture that verbatim (the goryeosa-jeoryo dataset has
   already drifted that way — see its doc).
4. Click the **다운로드** button on each page; no login is required.

Route re-verified 2026-08-27: both pages live, download buttons
present, license fields as above.

## Expected files

| Dataset | Zip | Contents |
|---|---|---|
| 15053647 | ~137 MB | 674 XML volume files (reign code + volume number, e.g. `wzc_121`), UTF-8, `history.dtd` |
| 15053646 | ~9 MB | the Gojong/Sunjong supplement volumes, same DTD family |

The dumps carry the 원문 (original Literary Chinese) only — the
modern Korean translation layer is NOT in them and is possibly
separately copyrighted; never acquire it from the website.

## Where it goes

No ManualDrop contract — the adapter fetches each dataset into its own
subdir of `canonical/sillok/` (`taejo-cheoljong/`, `gojong-sunjong/`)
itself. Hand-downloaded zips go to the repo's gitignored intake folder
(`.docs/inbox/`) as evidence/backup; the sanctioned ingest is
`bin/nabu sync sillok`.

## Refresh

The portal re-mints the terminal download id (`atchFileId`) on every
upstream file replacement — the dataset page is the stable address.
The dump snapshot is dated in the dataset title (20221103 as of this
writing); re-sync when the portal shows a newer registration date.
