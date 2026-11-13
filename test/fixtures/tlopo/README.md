# TLoPO — The lexicon of Proto Oceanic (lexibank/tlopo v0.1.1) — fixture

Retrieved 2026-11-13 from the Zenodo versioned record of the GitHub release v0.1.1: https://doi.org/10.5281/zenodo.23688418 — file `tlopo-v0.1.1.zip` (318500366 B, md5 `019b2177f479ff1298c4a4d141a3da51` as Zenodo publishes it; sha256 `fac45c143c93cd957f64e75f9f3f6ef86c9cdde708c22ceebc1d772b79578704`, the adapter's hard pin). The zip unpacks under `tlopo-0.1.1/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED); raw/ (REJECTED — the OCR'd source volumes, ~1.5 MB each; specimen raw/README.md, whole — the only small file in the grain); out/ (REJECTED — the rendered book chapters as HTML/Markdown; specimen out/pandoc_book.css, whole); etc/, templates/, tlopo_commands/, lib/, doc/ and the python packaging are machinery. The archive is 318 MB for ~10 MB of CLDF.

## Kept cognate sets

- `1-3-3-4-55-POc-sajaq-a` — PMP sasa(h,q) head (Level PMP) with a POc member mapped to poz-oce-pro
- `1-4-2-2-76-POc-burua-a` — POc buruŋ(a) head — the parenthesized Value beside the plain Form
- `1-4-3-1-81-PEOc-ibe-a` — PEOc ibe head (Proto Eastern Oceanic, display-only)

## Recipe

For the kept set ids: cognatesets.csv rows with those IDs; cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments (and the cognatesets' Form_ID heads) name; languages.csv / parameters.csv rows those forms name; borrowings.csv rows targeting a kept form; etyma.csv rows the kept sets' Etymon_ID name. Rows keep upstream's file order and raw bytes (the CSV reader's own line text, so quoted multi-line cells survive).

## Upstream count reconciliation

README: 755 varieties, 19,935 concepts, 43,037 lexemes, 40,960 cognates in 2,821 cognate sets. Full-scale dry parse: 2,821 entries, 38,139 reflex rows; 3,582 forms in no set mint nothing, counted. accepted 2,821 = upstream's 2,821.

## License

CC BY 4.0 — README "This dataset is licensed under a CC-BY-4.0 license", the LICENSE file (the CC BY 4.0 legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record.
