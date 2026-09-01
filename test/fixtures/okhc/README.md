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
- Plus THREE real deposit rows (copied from the owner's 2026-09-01
  full retrieval — the deposit's CURRENT schema, whose
  `copyright_status` field the repo sample's older `copyright`
  spelling had drifted from):
  - `ilseongnok…` first record — the `Hanmun` language label;
  - `sagi:sg_001_0060_0130` — `copyright_status: Public Domain`,
    pinning the PD → open relabel against real-schema bytes;
  - `aks_collection:WU.1985.4886…` — one of the corpus's 73
    `CC BY-NC-ND 2.0 KR` records, pinning ND-earns-no-upgrade.

37 records over 7 files; languages Classical Chinese / Hanmun / Early
Modern Korean / Korean / Modern Korean; copyright "Public Domain" and
null; multiline bodies included.

## Provenance / license

Dataset CC BY-NC 4.0, confirmed by the author (by email, 2026-08-31):
personal-research ingestion welcomed; cite the OKHC paper
(arXiv:2510.24541 / LREC 2026) — the manifest credit line carries the
citation onto every serving surface.
