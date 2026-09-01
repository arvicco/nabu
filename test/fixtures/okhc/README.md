# okhc fixtures

Real records of the Open Korean Historical Corpus (Song et al., KAIST;
CC BY-NC 4.0 — redistributable non-commercially, exactly this use), for
the P91-1 adapter.

- Source rows: the deposit's own published sample
  (github.com/seyoungsong/OKHC `sample.jsonl`, retrieved 2026-09-01),
  filtered to the adapter's included corpora, ≤3 rows per id-prefix,
  routed into per-file subdirs named exactly as the adapter lays them out (one FileFetch state/doomed-scope per file) — so the
  fixtures mirror the real multi-file, multi-prefix layout
  (`aks_kyu_nhm.jsonl` carries six id-prefixes, as upstream).
- Plus ONE live-probed row appended to
  `ilseongnok_part_001_of_003.jsonl` (the deposit's real first record,
  range-GET 2026-09-01): the `Hanmun` language label and the
  null-copyright state, which the sample happens not to carry —
  pinning the lzh mapping and the no-override path against real bytes.

37 records over 7 files; languages Classical Chinese / Hanmun / Early
Modern Korean / Korean / Modern Korean; copyright "Public Domain" and
null; multiline bodies included.

## Provenance / license

Dataset CC BY-NC 4.0, confirmed by the author (by email, 2026-08-31):
personal-research ingestion welcomed; cite the OKHC paper
(arXiv:2510.24541 / LREC 2026) — the manifest credit line carries the
citation onto every serving surface.
