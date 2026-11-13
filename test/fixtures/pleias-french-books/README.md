# pleias-french-books fixtures

Upstream: Hugging Face dataset `PleIAs/French-PD-Books`
(https://huggingface.co/datasets/PleIAs/French-PD-Books), revision
`21abfb3f646a0f1846175c63709913a51abc9bcb` (main, last modified 2024-03-19).
Retrieved 2026-11-13. Texts: Gallica / Bibliothèque nationale de France OCR,
re-hosted by PleIAs. License: the dataset card's prose, "The entire
collection is in the public domain everywhere" (no YAML license field).

## Upstream's delivery grains

| Grain | What upstream serves | Adapter's take |
|---|---|---|
| repo file | `README.md` (the dataset card), `.gitattributes`, 145 shards `gallica_mono_<n>.parquet` | shards crawled; the card kept as `dataset-card.md`; `.gitattributes` ignored |
| shard | one parquet file, one row group of ~2,000 randomly assigned books | the crawl unit (sha256-pinned to the revision's LFS oid) |
| row | one book: `file_id` (Gallica ark name), `ocr`, `title`, `date`, `author`, `page_count`, `word_count`, `character_count`, `complete_text` | **the document** if its imprint envelope closes ≤ 1699; otherwise **skipped by rule** (its catalogue line kept, its text never) |
| page | `complete_text` joins pages with `"\n \n"` | **the passage** (cited by segment ordinal; blank pages mint nothing) |

Rejected-grain specimens pinned here: `bpt6k63598352` (1783 — printed after
the cone) and `bpt6k6533714m` (`1633-1742` — a range straddling 1700).

## Files

`fetch/` — what the tests serve through WebMock:

- `gallica_mono_1.parquet` — shard 1 trimmed to four real rows, kept in
  upstream order (upstream row indexes 22, 66, 545, 1415): `bpt6k63598352`
  (1783, out of cone), `bpt6k9671998b` (1626, Lettres patentes, Louis XIII),
  `bpt6k54293789` (1652, Mazarinade triolets), `bpt6k96930955` (1563, Édict,
  Charles IX).
- `gallica_mono_100.parquet` — shard 100 trimmed to one real row (upstream
  index 392), `bpt6k6533714m` (`1633-1742`); its `complete_text` is cut to
  its first three page segments (an out-of-cone row: its text is never kept).
- `README.md` — the dataset card, verbatim bytes at the pinned revision.
- `tree.json` — the revision's tree API response
  (`/api/datasets/PleIAs/French-PD-Books/tree/<revision>`), trimmed to the
  four files above/beside; the two parquet entries' `size`/`lfs.size`/
  `lfs.oid` are SWAPPED for the trimmed files' own (the fetch verifies the
  sha256 pin, so the stub must pin what it serves).
- `api-dataset.json` — the `/api/datasets/PleIAs/French-PD-Books` response,
  trimmed to its scalar fields and the four siblings above.

The workdir tree beside `fetch/` (`tree.json`, `dataset-card.md`,
`shards/1.json(l)`, `shards/100.json(l)`, `books/*.json.gz`) is what the
adapter's OWN fetch materializes from `fetch/` — regenerated, never edited:
`test_fetch_materializes_exactly_the_fixture_tree` asserts byte equality.
The catalogue lines' `index` is the row's index in the TRIMMED shard
(upstream's indexes are listed above).

## Trim recipe

1. Rows: the datasets-server `/rows` API (`dataset=PleIAs/French-PD-Books`,
   `config=default`, `split=train`, `length=1`; shard 1 is rows 0–1998,
   shard 100 starts at offset 3999 in that API's file order), full cells
   (`truncated_cells` empty), `file_id` asserted.
2. Shards: written with upstream's own writer, `fastparquet==2023.10.1`,
   `compression="SNAPPY"`, the nine columns in upstream order (`*_count`
   int64, the rest object) — the same footer shape as upstream's (flat
   OPTIONAL leaves, PLAIN, v1 pages, RLE definition levels, one row group).
3. Workdir: run the adapter's fetch against `fetch/` through WebMock
   (`PleiasFrenchBooks.new(delay: 0, jit: false).fetch(<this dir>)`), then
   delete the crawl ledger `.pleias-crawl.json` (crawl state, timings).
