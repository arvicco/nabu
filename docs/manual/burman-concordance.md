# Burman concordance — acquisition

Annie Burman's "Digital Concordance of Etruscan, Faliscan and Early
Latin Inscriptions from Etruria" (Uppsala): 14,986 rows crosswalking
Trismegistos, CIE, Rix, TLE and CIL identifiers — a links instrument,
one CSV.

**Normally no human steps are needed**: `bin/nabu sync
burman-concordance` downloads the CSV from the stable Zenodo file URL
unattended. The first acquisition (2026-08-17) was performed by hand
during the adapter build; this document keeps the route replayable.

## Manual route

1. Open <https://zenodo.org/records/7801485>
   (doi:10.5281/zenodo.7801485, v1.0.0).
2. **License capture:** the deposit's license field reads Public
   Domain, and the record's own `legalcode.txt` (7 kB, downloadable
   beside the data) is the CC0 legal code — record both at acquisition
   time (read 2026-08-17, re-verified 2026-08-27).
3. Download the data file: `A Digital Concordance of Etruscan,
   Faliscan and Etrurian Latin 1.0.0.csv` (~1.1 MB). The `Read me
   1.0.0.pdf` documents the column semantics — worth keeping beside
   the data.

Route re-verified 2026-08-27: record live at v1.0.0, CSV 1.1 MB,
license "Other (Public Domain)" + CC0 legalcode.

## Where it goes

No ManualDrop contract — the adapter downloads into
`canonical/burman-concordance/` as `burman-concordance.csv` itself.
A hand-downloaded copy goes to the repo's gitignored intake folder
(`.docs/inbox/`) as evidence/backup; the sanctioned ingest is
`bin/nabu sync burman-concordance`.

## Refresh

The deposit is a finished publication (v1.0.0, 2023) — expect no
churn. A new version would mint a new Zenodo file URL; the adapter
pins `CSV_URL`, so a bump is a small code change plus a re-sync.
