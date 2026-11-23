# Kitchen et al. 2009 Semitic cognate sets (lexibank/kitchensemitic v2.1) — fixture

Retrieved 2026-11-23 from the Zenodo versioned record of the GitHub release v2.1: https://doi.org/10.5281/zenodo.17510140 — file `lexibank/kitchensemitic-v2.1.zip` (206760 B, md5 `1a023f5bc00258553ba50aa2dab6d065` as Zenodo publishes it; sha256 `4bde45028d2d45c7079ab2e30094dd426969a7630e29316f36a5ad9528e3be2a`, the adapter's hard pin). The zip unpacks under `lexibank-kitchensemitic-3a7f63b/`; every fixture file below is a byte-verbatim excerpt of that tree (records kept whole, record SET trimmed).

## Delivery grains

cldf/ (ACCEPTED — the CLDF Wordlist: forms, languages, parameters, cognates; no cognatesets/borrowings tables); raw/ (REJECTED — upstream's pre-CLDF source wordlists and coding sheets, csv/xls/xlsx; specimen raw/README.md, whole); etc/, the build script and the python packaging are machinery.

## Kept cognate sets

- `1_all-B` — 'All' — a singleton (Argobba)
- `2_ashes-F` — 'Ashes' — Aramaic + Akkadian; beside them the Akkadian second variant `Akkadian-2_ashes-2` (dikme:nu, split from the Value `tumru/dikme:nu`) is kept as an UNJUDGED form — it belongs to no set (one of upstream's 246 unjudged forms) and mints nothing, counted
- `17_dog-A` — 'Dog' — eleven members: Ge'ez, Tigre, Tigrinya, Hebrew, Ugaritic, Aramaic, Akkadian, Gibbali, Soqotri, Moroccan Arabic and the ISO-less Ogaden Arabic (display-only, Glottocode lang_code)

## Recipe

For the kept set ids: cognates.csv rows with those Cognateset_IDs; forms.csv rows those judgments name (plus the one unjudged specimen above); languages.csv / parameters.csv rows those forms name. Rows keep upstream's file order and raw bytes (every record is a single line upstream).

## Upstream count reconciliation

README: 25 varieties, 97 concepts, 2,396 lexemes; "2,150 cognates in 665 cognate sets (329 singletons)". Full-scale dry parse (2026-11-23): 665 entries, 2,150 reflex rows (0 loan-flagged — the Loan column is empty throughout; 347 rows display-only, the four ISO-less varieties); 246 forms outside the CognateTable mint nothing (counted). accepted 665 = upstream's 665.

## License

CC BY-NC 4.0 — README "This dataset is licensed under a https://creativecommons.org/licenses/by-nc/4.0/ license", the LICENSE file (Attribution-NonCommercial 4.0 International legal code) and cldf-metadata.json `dc:license` agree, as does the Zenodo record (cc-by-nc-4.0). No ND clause.
