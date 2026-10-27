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

- Plus THREE real deposit rows for the named-entity markup (P146,
  copied byte-verbatim from the same retrieval, 2026-10-27):
  - `aks_royal:RD00158` — the AKS royal-court documents' `ner_person` /
    `ner_place` spans in `content.body_xml`;
  - `ilseongnok:1778-06-0-05-정조-GK12811_00-63-000-011` — a title-only
    record whose only span is `ner_세주` (interlinear small-note — text
    structure, skipped by rule);
  - `klc:ITKC_MO_0220A_0120_000_0060` — klc's `ner_948a54` spans (a
    colour class over 吐 reading particles — skipped by rule).
  The earlier ilseongnok rows already carry name spans in both
  `title_xml` (title-only record) and `body_xml`.

42 records over 7 files (the adapter test's discover count); languages Classical Chinese / Hanmun / Early
Modern Korean / Korean / Modern Korean; copyright "Public Domain" and
null; multiline bodies included.

## Provenance / license

Dataset CC BY-NC 4.0, confirmed by the author (by email, 2026-08-31):
personal-research ingestion welcomed; cite the OKHC paper
(arXiv:2510.24541 / LREC 2026) — the manifest credit line carries the
citation onto every serving surface.
