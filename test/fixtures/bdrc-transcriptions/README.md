# bdrc-transcriptions fixture

Retrieved 2026-11-02 from the Hugging Face datasets-server rows API
(https://datasets-server.huggingface.co/rows, /filter for the ACIP
volume) over BDRC's three CC0 transcription releases:

| subdir | dataset | revision |
|---|---|---|
| `acip-sungbum/` | https://huggingface.co/datasets/BDRC/ALL-BDRC-alignments | (card measured 2026-09-01) |
| `palri-parkhang/` | https://huggingface.co/datasets/BDRC/palri-parkhang-transcriptions | (card measured 2026-08-18) |
| `berkeley/` | https://huggingface.co/datasets/BDRC/berkeley-transcriptions | ed7b6318146f00b48c01f5f15b7425ad3269489f |

Each subdir is exactly what `Nabu::HfRowsFetch` lands: one JSON Lines
file per etext volume (`VE….jsonl`), one row per line in scan-file
order, the upstream columns in upstream order with the `image` cell
removed; beside them the dataset card (`README.md`) and
`subset_info.json`, fetched verbatim.

## Delivery grains (every grain upstream serves)

Upstream serves ONE row grain — the page: `image` (embedded scan),
`transcription`, `id`, `mw_id`, `technology`, `script` and, in the
Palri and Berkeley releases, `script_4` — in sharded parquet, rows
shuffled across volumes. The row id carries the hierarchy:
`<release tag>:<collection>:<IE instance>:<VE volume>:<v>:<scan file>`.

| grain | taken? |
|---|---|
| etext volume (VE…) | TAKEN — the document (one file each) |
| page row | the passage (cited by the scan file stem) |
| etext instance (IE…), BDRC version (`mw_id`) | metadata only |
| page image | NEVER fetched (the fetch has no path to it) |
| dataset card + subset_info.json | rejected, pinned per release, skipped by rule (6 specimens here) |

## The volume cuts (real rows, first pages in scan order)

- `acip-sungbum/VE1ALS05274I.jsonl` — 3 of the volume's 67 pages
  (BDRC MW635, woodblock dbu can; the ACIP release has no `script_4`
  column);
- `palri-parkhang/VE1605_MA.jsonl` — 3 of 292 pages (MW21492, the *Chos
  'byung bstan pa'i nyi ma*: the title page, then the opening);
- `berkeley/VE2115_MA.jsonl` — 3 of 59 pages (MW23550, dbu med
  manuscript; the release's own filtering leaves scan-number gaps);
- `berkeley/VE4PD1489_MA.jsonl` — 3 of 319 pages (MW2PD17515, the
  release's woodblock portion, `script_4` null).

`fetch/` holds the HfRowsFetch fixtures: two real 3-row pages of the
Berkeley release (offsets 0 and 3) with `num_rows_total` trimmed from
8,866 to 6 and the signed image-asset query strings trimmed, the dataset
API record (trimmed to its identity fields) and the card files.

## Census (2026-11-02, the full text columns)

- berkeley: 8,866 rows = the card → 19 volumes / 14 instances, 0 blank,
  0 unparseable ids, stems unique within each volume.
- palri-parkhang: 11,133 rows = the card → 23 volumes / 6 instances,
  0 blank. Upstream defect: 15 pages (12 in VE2491_MA, 3 in VE2119_MA)
  carry པ where the tsheg belongs (ཅེསཔགསུངསཔམོདཔ…) — kept verbatim.
- acip-sungbum: 79,572 rows = the card → 1,118 volumes = its 1,118
  transcription volumes (one instance each; 119 BDRC versions), 0 blank.
- all three parsed through the adapter: 1,160 documents / 99,571 passages.
