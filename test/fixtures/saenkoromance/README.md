# Saenko 2015 Romance Swadesh wordlists (lexibank/saenkoromance v1.1) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v1.1: https://doi.org/10.5281/zenodo.13163492 — file `lexibank/saenkoromance-v1.1.zip` (334498 B, md5 `0b0d30e665dc897928f80f9571b0b6af` as Zenodo publishes it; sha256 `f02dbdde7540775d00a3696b477488c7241c8d9b5dec541b357a116ae2448a63`, the adapter's hard pin). The zip unpacks under `lexibank-saenkoromance-10320bb/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED); raw/ (REJECTED — upstream's pre-CLDF source tables; specimen raw/sources.bib, whole); etc/ and the python packaging are machinery.

## Kept cognate sets

- `23` — 'bite' — Balkan Romance; the Aromanian Value carries two ~ variants, one with a Private Use Area character (U+EDC1) in its orthography
- `34` — 'breast' — a Piedmontese Value with no braced orthography (the transcription stays the word)
- `-456` — 'yellow' — a loan singleton (Loan true) with two ~ variants

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 43 varieties, 110 concepts, 4,853 lexemes, 4,853 cognates in 465 cognate sets. Full-scale dry parse: 465 entries, 5,092 reflex rows (the ~ variants split; 174 loan-flagged). accepted 465 = upstream's 465.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
