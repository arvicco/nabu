# dpd fixture

Trimmed REAL excerpt of the Digital Pāḷi Dictionary's plain-text export.
Retrieved 2026-11-02 from the dpd-db release v0.4.20261026 (published
2026-10-26), https://github.com/digitalpalidictionary/dpd-db/releases —
`dpd-txt.zip` (4,276,639 bytes, sha256
50ebe8f6b4b08651dd82d8ab1cfe48dee82aee103e52712c84b690a9ad2bccdd), one
member `dpd.txt` (22,972,952 bytes, sha256
4d5b82fdaccbc6ee076d14a992e31f7fc4bb696fc7f1efe4af512396a908ff0a,
89,763 blocks).

License (repo LICENSE): "Digital Pāḷi Dictionary / Copyright (c)
Bodhirasa Bhikkhu / SPDX-License-Identifier: CC-BY-NC-SA-4.0".

## Delivery grains

The release serves one dictionary in twelve formats: `dpd.db.tar.xz`
(the SQLite build database), reader packages (GoldenDict, MDict, slob,
Kindle epub/mobi, Kobo, Apple, Anki, PDF, mobile-db) and `dpd-txt.zip`.
The adapter fetches `dpd-txt.zip` only — its one `dpd.txt` is the
document, each blank-line-separated block an entry; the other formats
are renderings of the same headwords and are never fetched (no rejected
grain lands in the workdir). Reconciliation: 89,763 blocks = 89,763
unique DPD ids.

## Cut

The 4 blocks with ID 1, 7, 72479, 71509, byte-verbatim in upstream order
(0-based blocks 0, 5, 6, 89762 — the first and the last of the file),
joined by upstream's blank line: `a 1.1` (a homonym-numbered head with a
"(gram)" register label), `akakkasa` (a full block with construction,
compound and Sanskrit fields), `akakkasaṅga` (a ✘ minimal block),
`ṃa` (a ◑ block, the file's last).

## Refresh

Re-fetch dpd-txt.zip from the release and re-select the same IDs.
