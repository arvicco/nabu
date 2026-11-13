# MCD — Micronesian Comparative Dictionary (lexibank/mcd v2.0) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v2.0: https://doi.org/10.5281/zenodo.14608119 — file `lexibank/mcd-v2.0.zip` (4425554 B, md5 `e6814a687f1201c9a3ca0002f8b05f63` as Zenodo publishes it; sha256 `d3a50f4dafa321f95e202e1cc566cdb4f5408acc27e0204b584b54ddb028083a`, the adapter's hard pin). The zip unpacks under `lexibank-mcd-1cabc58/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED); raw/ (REJECTED — upstream's pre-CLDF source pages and tables; specimen raw/kosraean_barred_i_Part2.csv, whole); etc/, lib/ and the python packaging are machinery.

## Kept cognate sets

- `2978` — PMc *ae₁ 'crawl' — a doubtful set (Doubt true) with a comment; the head judgment itself doubtful
- `2979` — PMc *ae₂ 'this' — a Proto-Oceanic member (mapped to poz-oce-pro) with a doubtful judgment
- `3005` — PCMc *amʷii — a Proto-Central Micronesian head (display-only), Name repeats the head

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 60 varieties, 12,220 concepts, 20,689 lexemes, 17,583 cognates in 1,707 cognate sets. Full-scale dry parse: 1,707 entries, 16,592 reflex rows (61 uncertain); 2,430 forms in no set (cf. items) mint nothing, counted. accepted 1,707 = upstream's 1,707.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
