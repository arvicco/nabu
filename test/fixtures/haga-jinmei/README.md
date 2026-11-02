# haga-jinmei fixture

Retrieved 2026-11-02 from Zenodo record 23804456 (v0.1.0, 2026-10-29),
file `NIHU-jp/haga-jinmei-dataset-v0.1.0.zip` (2,461,955 bytes, md5
d3041e4c92a02d52d7573a6ca26dd22e = the record's checksum; sha256
410c05fa…deec, the adapter's pin), via
https://zenodo.org/api/records/23804456/files/NIHU-jp/haga-jinmei-dataset-v0.1.0.zip/content

The tree is the zip as ZipFetch lands it (the single top directory
`NIHU-jp-haga-jinmei-dataset-c89044f/` stripped). This README replaces
the deposit's own README.md (same path); `.gitignore`, `.zenodo.json` and
`RELEASE_CHECKLIST.md` are not copied.

## Delivery grains (every grain the deposit serves)

| grain | file(s) | taken? |
|---|---|---|
| entry row | `data/haga_jinmei_records.csv` (54,558 rows, 6 columns) | TAKEN — one dictionary document, one entry per row |
| release manifest | `data/release_manifest.json` (counts + sha256 pins) | rejected, skipped by rule (pinned) |
| schema | `schema/public_record.schema.json` | rejected, skipped by rule (pinned) |
| documentation | LICENSE, RIGHTS.md, DATA_DICTIONARY.md, MULTI_PERSON_ENTRIES.md, CITATION.cff, CHANGELOG.md, data/README.md, README.md | rejected, skipped by rule (pinned) |

## The CSV cut

`data/haga_jinmei_records.csv` keeps the header and seven real rows
(byte-identical lines), chosen for their shapes:

- 000001, 000002 — plain entries (000002 a gō heading with the family
  name in brackets, 靄崖（高久）);
- 000005 — a bare `⇒ユウザン` see-reference by reading (8,559 such rows
  upstream = the manifest's `redirect_like_count`);
- 000357 — a blank `full_name` (2 upstream);
- 002562 — the deposit's ONE CSV-quoted row: its `full_name` cell holds a
  description fragment containing a comma ("幕末-明治時代の司法官,画家。");
- 017048 — 式佐（岸沢）, the multi-person entry MULTI_PERSON_ENTRIES.md
  names (the sixth to eighth holders of the name in one text);
- 035816 — a blank `description` (3 upstream).

Reconciliation (full CSV, 2026-11-02): 54,558 rows = `record_count`;
8,559 bare-⇒ rows = `redirect_like_count`; 2 blank full_name and 3 blank
description = the manifest's blank counts; entry_no unique.
