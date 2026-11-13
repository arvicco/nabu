# Sagart et al. 2019 Sino-Tibetan Database of Lexical Cognates (lexibank/sagartst v2.1) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v2.1: https://doi.org/10.5281/zenodo.13162889 — file `lexibank/sagartst-v2.1.zip` (1603383 B, md5 `dd275cc96c498aed554c12c6f0f5002e` as Zenodo publishes it; sha256 `7175b7c512897a16d217a013205196ebc8d5023b2777c091e43463205801bfc7`, the adapter's hard pin). The zip unpacks under `lexibank-sagartst-c6df5f3/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED); raw/ (REJECTED — upstream's pre-CLDF source data; specimen raw/README.md, whole); scripts/, etc/ and the python packaging are machinery.

## Kept cognate sets

- `20-above` — 'above' — Old Tibetan, Limbu, Old Chinese *daŋʔ-s (a member, never a head) and three Sinitic points without ISO codes
- `2526-thethunder` — 'the thunder' — Old Tibetan + Japhug, the Japhug form Loan true
- `3827-thesea` — 'the sea' — Jingpho (Loan true), Old Burmese, Rangoon Burmese

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 50 varieties, 250 concepts, 12,179 lexemes, 12,179 cognates in 5,120 cognate sets. Full-scale dry parse: 5,120 entries, 12,179 reflex rows (540 loan-flagged). accepted 5,120 = upstream's 5,120.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
