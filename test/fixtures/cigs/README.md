# cigs fixtures

Trimmed from the REAL CIGS v1.7 CSV (Cuneiform Inscriptions Geographical
Site Index; Uppsala "Geomapping Landscapes of Writing", published through
CDLI's journal — CDLJ 2021-1), retrieved 2026-08-08 from the stable Zenodo
URL `https://zenodo.org/records/14568765/files/cigs_v1_7_20241215.csv?download=1`
(full file: 598 lines / 157,668 bytes, sha256
0e35c06fac38e02ad55ecb8d7e2319a889152a3cf5f62e5bf220a31f2fad60e2).

- License (Zenodo record verbatim): "Creative Commons Attribution 4.0
  International".
- `cigs.csv`: header + 8 real rows — GIR (Girsu), JOK (Umma), KNS
  (Kanesh), MAR (Mari — carrying Pleiades 286681704, which resolves the
  survey's "Mari absent from Pleiades?" question: it is a post-4.1-dump
  addition), NIP (Nippur), UGA (Ugarit), ADA (an "uncertain" site), HAY
  (NO pleiades/geonames links — the honest-absent crosswalk case).
- Load-bearing field facts: `legacy_name` is EXACTLY the CDLI house
  composite ("Girsu (mod. Tello)") — the seed key for the nabu-places
  cdli section; `cdli_provenience_id` is a full proveniences URL;
  `pleiades_url`/`geonames_url` are full URLs; lon comes BEFORE lat
  (`lon_wgs1984,lat_wgs1984`).

Never hand-edit; re-trim from a fresh Zenodo download.
