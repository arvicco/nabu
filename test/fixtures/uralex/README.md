# UraLex 2.0 (lexibank/uralex v2.0) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v2.0: https://doi.org/10.5281/zenodo.4777568 — file `lexibank/uralex-v2.0.zip` (670697 B, md5 `32bf3a3d0a266dcd12ad951ab6254704` as Zenodo publishes it; sha256 `5e2f2e4e385dbf5308c2f2c264b0fb89d844c8ffe5aef06567957c3357b1afb3`, the adapter's hard pin). The zip unpacks under `lexibank-uralex-a37bb22/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED); raw/ (REJECTED — upstream's pre-CLDF source tables; specimen raw/Meaning_list_descriptions.tsv, whole); etc/ and the python packaging are machinery.

## Kept cognate sets

- `100-f` — 'hard' — Proto-Uralic *kämä ? heads (declared proto variety 0), Erzya + Hungarian members
- `104-j` — 'wild animal' — Proto-Uralic *śurmi̮ heads, two Samoyed members without ISO codes
- `106-x` — 'bad' — two Finnic loans from Germanic (borrowings.csv, Likelihood probable); no reconstruction, the concept heads

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 27 varieties, 313 concepts, 10,231 lexemes, 9,751 cognates in 3,792 cognate sets. Full-scale dry parse: 3,792 entries (136 headed by a Proto-Uralic reconstruction, the rest by their concept), 9,614 reflex rows (2,180 loan-flagged); 480 forms in no set mint nothing, counted. accepted 3,792 = upstream's 3,792.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
