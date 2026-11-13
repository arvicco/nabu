# parquet format fixtures (Nabu::Parquet)

Format specimens for the minimal parquet reader, both derived 2026-11-13
from the pleias-french-books trimmed shard
(`test/fixtures/pleias-french-books/fetch/gallica_mono_1.parquet`, real
upstream rows — see that directory's README):

- `multipage.parquet` — the same four-row table re-written by parquet-cpp
  (pyarrow 26.0.1: `use_dictionary=False`, `data_page_version="1.0"`,
  `compression="snappy"`, `data_page_size=1024`, `write_batch_size=1`,
  `write_statistics=False`) so every column chunk spans several v1 pages:
  the reader's page walk is tested against a second real writer.
- `empty.parquet` — a zero-row file with the upstream schema, written by
  upstream's writer (`fastparquet==2023.10.1`, SNAPPY): no row group at
  all, the shape a zero-row shard takes.
